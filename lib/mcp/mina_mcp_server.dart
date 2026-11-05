import '../models/mina_state.dart';
import '../robot/robonova_actions.dart';
import '../robot/robonova_serial_driver.dart';
import '../services/mina_audio_service.dart';

/// Máy chủ MCP (Model Context Protocol - JSON-RPC 2.0) tích hợp ngay bên trong Robot Mina.
/// Phơi bày toàn bộ 63 động tác & hệ thống cảm biến của mạch MR-C3024FX cho AI XiaoZhi gọi tự động không giới hạn!
class MinaMcpServer {
  final RobonovaSerialDriver robotDriver;
  final MinaAudioService audioService;
  final void Function(MinaEmotion emotion) onEmotionChanged;
  final bool Function()? isObstacleSafeWalkEnabled;
  final Future<void> Function({
    bool? hardwareReflex,
    bool? autoGreet,
    bool? autoStandup,
    bool? obstacleSafeWalk,
  })? onUpdateSafetyConfig;
  final void Function(String tag, String msg)? onLog;

  MinaMcpServer({
    required this.robotDriver,
    required this.audioService,
    required this.onEmotionChanged,
    this.isObstacleSafeWalkEnabled,
    this.onUpdateSafetyConfig,
    this.onLog,
  });

  /// Xử lý gói JSON-RPC `payload` bên trong message `{"type": "mcp", "payload": ...}` từ XiaoZhi
  Future<Map<String, dynamic>?> handleJsonRpc(Map<String, dynamic> rpc) async {
    final method = rpc['method'] as String? ?? '';
    final id = rpc['id']; // Notification sẽ không có id

    onLog?.call('MCP', 'Nhận lệnh AI MCP: $method (id=$id)');

    if (method == 'notifications/initialized') {
      return null;
    }

    if (method == 'initialize') {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {},
          },
          'serverInfo': {
            'name': 'MinaHumanoidRobot',
            'version': '1.0.0',
          },
        },
      };
    }

    if (method == 'tools/list') {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': _buildToolsCatalog(),
        },
      };
    }

    if (method == 'tools/call') {
      final params = (rpc['params'] as Map?)?.cast<String, dynamic>() ?? const {};
      final toolName = params['name'] as String? ?? '';
      final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};

      final outputText = await _executeTool(toolName, args);
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {
              'type': 'text',
              'text': outputText,
            }
          ],
          'isError': false,
        },
      };
    }

    if (id != null) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32601,
          'message': 'Method not found: $method',
        },
      };
    }
    return null;
  }

  List<Map<String, dynamic>> _buildToolsCatalog() {
    final allSlugs = RobonovaActionCatalog.all.map((a) => a.slug).toList();
    final actionDescriptions = RobonovaActionCatalog.all
        .map((a) => '${a.slug} (${a.id}: ${a.nameVi})')
        .join(', ');

    return [
      {
        'name': 'self.mina.walk',
        'description':
            'Điều khiển robot Mina đi bộ, chạy, quay trái/phải, bước ngang, leo cầu thang. '
            'Dùng khi người dùng bảo tiến lên, lùi lại, sang trái, sang phải, quay lại, chạy nhanh.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': [
                'walk_forward',
                'walk_backward',
                'turn_left',
                'turn_right',
                'shift_left',
                'shift_right',
                'fast_walk',
                'very_fast_walk',
                'fast_run',
                'fast_turn_left_1',
                'fast_turn_right_1',
                'climb_upstair',
              ],
              'description': 'Hướng hoặc kiểu di chuyển của robot Mina.',
            },
            'steps': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 5,
              'description': 'Số lần lặp lại nhịp bước (mặc định 1).',
            },
          },
          'required': ['direction'],
        },
      },
      {
        'name': 'self.mina.greet',
        'description':
            'Điều khiển robot Mina chào hỏi, bắt tay, vỗ tay, vẫy tay, giơ hai tay, cổ vũ ăn mừng.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'gesture': {
              'type': 'string',
              'enum': [
                'bow',
                'honor_bow',
                'hand_shake',
                'hand_clap',
                'wave_arms',
                'hands_up',
                'cheer_up',
                'big_reach',
              ],
              'description': 'Cử chỉ giao tiếp xã hội của Mina.',
            },
          },
          'required': ['gesture'],
        },
      },
      {
        'name': 'self.mina.dance_and_acrobatics',
        'description':
            'Điều khiển robot Mina nhảy múa (Dance 1, Dance 2, Dance 3, Break Dance), chống đẩy/hít đất, '
            'trồng chuối (handstand), đứng một chân, hoặc nhào lộn trước/sau/trái/phải.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'move': {
              'type': 'string',
              'enum': [
                'dance_1',
                'dance_2',
                'dance_3',
                'break_dance',
                'push_up',
                'pushup_music',
                'handstand',
                'single_foot_stand',
                'forward_tumbling',
                'back_tumbling',
                'left_tumbling',
                'right_tumbling',
                'body_shake',
                'foot_up',
              ],
              'description': 'Bài nhảy hoặc động tác nhào lộn thể lực.',
            },
          },
          'required': ['move'],
        },
      },
      {
        'name': 'self.mina.martial_arts',
        'description':
            'Điều khiển robot Mina biểu diễn võ thuật (5 thế võ kungfu), đấm thẳng, đấm trái/phải, '
            'sút bóng, làm thủ môn bắt bóng, hoặc né đòn kiểu Matrix.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'skill': {
              'type': 'string',
              'enum': [
                'martial_arts_1',
                'martial_arts_2',
                'martial_arts_3',
                'martial_arts_4',
                'martial_arts_5',
                'forward_punch',
                'left_attack',
                'right_attack',
                'big_toss',
                'avoid_matrix',
                'shoot_left_right',
                'goalkeeper',
              ],
              'description': 'Chiêu thức võ thuật hoặc thể thao.',
            },
          },
          'required': ['skill'],
        },
      },
      {
        'name': 'self.mina.posture_and_standup',
        'description':
            'Điều khiển robot Mina ngồi xuống, tự đứng dậy khi bị ngã ngửa hoặc ngã sấp, hoặc nghỉ tắt motor.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'posture': {
              'type': 'string',
              'enum': [
                'sit_down',
                'stand_up_from_back',
                'stand_up_from_front',
                'toggle_motor_sit',
                'toggle_sit_pose_2',
              ],
              'description': 'Tư thế ngồi hoặc đứng dậy.',
            },
          },
          'required': ['posture'],
        },
      },
      {
        'name': 'self.mina.perform_any_action',
        'description':
            'Thực thi bất kỳ hành động nào trong tổng số 63 hành động gốc (K1..K68) của Mina theo mã K hoặc slug: '
            '$actionDescriptions',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': allSlugs,
              'description': 'Slug của hành động trong danh mục 63 động tác Robonova-II.',
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'self.mina.set_emotion',
        'description': 'Đổi biểu cảm khuôn mặt hoạt hình trên màn hình ngực của Mina.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'emotion': {
              'type': 'string',
              'enum': ['happy', 'love', 'martial', 'surprised', 'sleepy', 'idle'],
            },
          },
          'required': ['emotion'],
        },
      },
      {
        'name': 'self.mina.set_volume',
        'description': 'Điều chỉnh âm lượng loa của robot Mina (từ 0 đến 100%).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'volume': {
              'type': 'integer',
              'minimum': 0,
              'maximum': 100,
              'description': 'Mức âm lượng phần trăm (0-100).',
            },
          },
          'required': ['volume'],
        },
      },
      {
        'name': 'self.mina.read_sensors',
        'description':
            'Đọc dữ liệu cảm biến thời gian thực gắn trên mạch Robonova-II (MR-C3024FX): '
            'cảm biến siêu âm trên mắt (cm), cảm biến khoảng cách 10k (ADC 0-255 & cm ước tính), '
            'điện áp pin (V & %), và tư thế nghiêng/ngã. Dùng khi người dùng hỏi phía trước có vật cản không, '
            'khoảng cách bao xa, còn bao nhiêu pin, hoặc kiểm tra đường đi.',
        'inputSchema': {
          'type': 'object',
          'properties': {},
        },
      },
      {
        'name': 'self.mina.set_safety_reflex',
        'description':
            'Bật hoặc tắt các chế độ phản xạ thông minh từ cảm biến của Mina: '
            'tự tránh vật cản khi bước tới, tự vẫy tay chào khi mắt siêu âm thấy người đứng trước mặt, '
            'và tự đứng dậy khi bị ngã.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'hardware_reflex': {
              'type': 'boolean',
              'description': 'Bật/tắt phản xạ tự tránh vật cản & chống ngã ngay trên chip MR-C3024FX.',
            },
            'obstacle_safe_walk': {
              'type': 'boolean',
              'description': 'Bật/tắt kiểm tra vật cản an toàn trước khi Mina bước tiến.',
            },
            'auto_greet_sonar': {
              'type': 'boolean',
              'description': 'Bật/tắt tự động vẫy tay chào khi mắt siêu âm thấy người lại gần (15-65 cm).',
            },
            'auto_standup_fall': {
              'type': 'boolean',
              'description': 'Bật/tắt tự động đứng dậy (K19/K25) khi cảm biến nghiêng phát hiện bị ngã.',
            },
          },
        },
      },
    ];
  }

  static const Set<String> _forwardSlugs = {
    'walk_forward',
    'fast_walk',
    'very_fast_walk',
    'fast_run',
    'climb_upstair',
  };

  Future<String> _executeTool(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'self.mina.walk':
        final slug = args['direction']?.toString() ?? 'walk_forward';
        final steps = _asInt(args['steps']) ?? 1;
        final checkSafety = isObstacleSafeWalkEnabled?.call() ?? true;
        if (checkSafety && _forwardSlugs.contains(slug)) {
          final s = await robotDriver.requestSensorSnapshot();
          if (s.hasObstacle) {
            onEmotionChanged(MinaEmotion.surprised);
            final sonarDesc = s.sonarCm != null ? '${s.sonarCm} cm' : 'ngoài tầm';
            return 'CẢNH BÁO VẬT CẢN PHÍA TRƯỚC: Mắt siêu âm đo được $sonarDesc '
                '(ngưỡng < ${s.sonarObstacleThresholdCm} cm), cảm biến khoảng cách 10k ADC=${s.dist10kRaw} '
                '(ngưỡng > ${s.dist10kObstacleThreshold}). Mina đã tự động dừng bước tiến để tránh va chạm! '
                'Hãy báo cho người dùng biết có vật cản trước mặt và đề nghị đi lùi (walk_backward) hoặc rẽ hướng khác.';
          }
        }
        return _runRobotSlug(slug, repeat: steps);

      case 'self.mina.greet':
        onEmotionChanged(MinaEmotion.happy);
        final slug = args['gesture']?.toString() ?? 'bow';
        return _runRobotSlug(slug);

      case 'self.mina.dance_and_acrobatics':
        onEmotionChanged(MinaEmotion.happy);
        final slug = args['move']?.toString() ?? 'dance_1';
        return _runRobotSlug(slug);

      case 'self.mina.martial_arts':
        onEmotionChanged(MinaEmotion.martial);
        final slug = args['skill']?.toString() ?? 'martial_arts_1';
        return _runRobotSlug(slug);

      case 'self.mina.posture_and_standup':
        final slug = args['posture']?.toString() ?? 'sit_down';
        return _runRobotSlug(slug);

      case 'self.mina.perform_any_action':
        final slug = args['action']?.toString() ?? 'bow';
        return _runRobotSlug(slug);

      case 'self.mina.set_emotion':
        final emoStr = args['emotion']?.toString() ?? 'happy';
        onEmotionChanged(parseEmotionFromXiaozhi(emoStr));
        return 'Mina đã đổi biểu cảm khuôn mặt sang $emoStr.';

      case 'self.mina.set_volume':
        final vol = (_asInt(args['volume']) ?? 80).clamp(0, 100).toInt();
        await audioService.setVolume(vol);
        return 'Đã đặt âm lượng loa của Mina thành $vol%.';

      case 'self.mina.read_sensors':
        final s = await robotDriver.requestSensorSnapshot();
        if (!s.hasData) {
          return 'Chưa nhận được gói dữ liệu ETX 9600 từ mạch Robonova-II (kiểm tra dây nối MR-C3024FX ETX -> Android RX và nạp firmware code_robonova2_mina_sensors.bas).';
        }
        final sonarStr = s.sonarCm != null ? '${s.sonarCm} cm' : 'Thông thoáng / Ngoài tầm đo';
        final d10kEst = s.dist10kApproxCm != null ? ' (~${s.dist10kApproxCm!.toStringAsFixed(0)} cm)' : '';
        final obstacleStr = s.hasObstacle
            ? 'CÓ VẬT CẢN GẦN PHÍA TRƯỚC!'
            : 'Đường phía trước thông thoáng, an toàn.';
        return 'Trạng thái cảm biến Robonova-II hiện tại:\n'
            '- Mắt siêu âm SONAR(5): $sonarStr\n'
            '- Cảm biến khoảng cách 10k AD(0): ADC ${s.dist10kRaw}/255$d10kEst\n'
            '- Đánh giá vật cản: $obstacleStr\n'
            '- Điện áp Pin AD(6): ${s.batteryVolts.toStringAsFixed(2)}V (~${s.batteryPercent}%)${s.isBatteryLow ? " [PIN YẾU < 5.8V]" : ""}\n'
            '- Tư thế cơ thể AD(5): ${s.postureLabel} (ADC ${s.tiltRaw})';

      case 'self.mina.set_safety_reflex':
        final hw = _asBool(args['hardware_reflex']);
        final safeWalk = _asBool(args['obstacle_safe_walk']);
        final autoGreet = _asBool(args['auto_greet_sonar']);
        final autoStandup = _asBool(args['auto_standup_fall']);
        await onUpdateSafetyConfig?.call(
          hardwareReflex: hw,
          obstacleSafeWalk: safeWalk,
          autoGreet: autoGreet,
          autoStandup: autoStandup,
        );
        return 'Đã cập nhật cấu hình phản xạ cảm biến cho Mina thành công.';

      default:
        return 'Không tìm thấy công cụ $name.';
    }
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return num.tryParse(v.toString().trim())?.toInt();
  }

  static bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'on' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'off' || s == 'no') return false;
    return null;
  }

  Future<String> _runRobotSlug(String slug, {int repeat = 1}) async {
    final action = RobonovaActionCatalog.findBySlugOrId(slug);
    if (action == null) {
      return 'Không tìm thấy động tác "$slug" trong bảng điều khiển MR-C3024FX.';
    }
    final sentUart = await robotDriver.executeAction(action, repeat: repeat);
    return 'Mina đang thực hiện động tác "${action.nameVi}" (Mã ${action.id}, ASCII ${action.asciiByte}, '
        'lặp $repeat lần, UART=${sentUart ? "Đã truyền tới MR-C3024FX" : "Mô phỏng"}).';
  }
}
