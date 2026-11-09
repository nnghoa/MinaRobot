import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/assistant_profile.dart';
import '../models/mina_state.dart';
import '../services/mina_audio_service.dart';
import '../services/mina_platform.dart';
import '../services/mina_web_tools.dart';

/// Máy chủ MCP (JSON-RPC 2.0) chạy ngay trong Mina Visbot.
/// XiaoZhi gọi các công cụ này khi người dùng ra lệnh bằng giọng nói.
class MinaMcpServer {
  final MinaAudioService audioService;
  final void Function(MinaEmotion emotion) onEmotionChanged;

  /// Yêu cầu chuyển sang trợ lý khác. Chạy SAU khi đã trả kết quả cho server.
  final void Function(String assistantId) onSwitchAssistant;

  /// Báo cho controller biết vừa bật radio/nhạc/video: controller tạm dừng media,
  /// để AI nói xong câu xác nhận, rồi đóng phiên và phát media.
  final Future<void> Function() onMediaStarted;

  /// Định danh thiết bị hiện tại (dùng cho header khi gửi ảnh lên server vision)
  final String Function() deviceMac;
  final String Function() clientId;
  final String Function() activeAssistantId;
  final void Function(String tag, String msg)? onLog;

  String? _visionUrl;
  String? _visionToken;

  MinaMcpServer({
    required this.audioService,
    required this.onEmotionChanged,
    required this.onSwitchAssistant,
    required this.onMediaStarted,
    required this.deviceMac,
    required this.clientId,
    required this.activeAssistantId,
    this.onLog,
  });

  bool get hasVision => (_visionUrl ?? '').isNotEmpty;

  void resetSession() {
    _visionUrl = null;
    _visionToken = null;
  }

  /// Xử lý gói JSON-RPC `payload` bên trong message `{"type": "mcp", "payload": ...}` từ XiaoZhi
  Future<Map<String, dynamic>?> handleJsonRpc(Map<String, dynamic> rpc) async {
    final method = rpc['method'] as String? ?? '';
    final id = rpc['id']; // Notification sẽ không có id

    onLog?.call('MCP', 'Nhận lệnh AI MCP: $method (id=$id)');

    if (method == 'notifications/initialized') {
      return null;
    }

    if (method == 'initialize') {
      // Server XiaoZhi gửi kèm địa chỉ dịch vụ phân tích ảnh (vision) trong capabilities
      final params = (rpc['params'] as Map?)?.cast<String, dynamic>() ?? const {};
      final caps = (params['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
      final vision = (caps['vision'] as Map?)?.cast<String, dynamic>();
      _visionUrl = vision?['url']?.toString();
      _visionToken = vision?['token']?.toString();
      onLog?.call('MCP', hasVision ? 'Server hỗ trợ phân tích ảnh camera.' : 'Server không gửi cấu hình vision.');
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {},
          },
          'serverInfo': {
            'name': 'MinaVisbot',
            'version': '2.0.0',
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

      String outputText;
      var isError = false;
      try {
        outputText = await _executeTool(toolName, args);
      } catch (e) {
        outputText = 'Lỗi khi chạy công cụ $toolName: $e';
        isError = true;
      }
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
          'isError': isError,
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
    final assistantDesc =
        AssistantCatalog.all.map((a) => '${a.id} (${a.name}: ${a.subtitle})').join(', ');
    final radioDesc = RadioCatalog.all.map((s) => '${s.id} (${s.name})').join(', ');

    return [
      {
        'name': 'self.assistant.switch',
        'description':
            'Chuyển sang trợ lý / gia sư khác khi người dùng muốn học hoặc gọi tên trợ lý '
            '(ví dụ "cho gặp gia sư toán", "học tiếng Anh", "kể chuyện cho bé"). '
            'Danh sách: $assistantDesc. Sau khi gọi, phiên hiện tại sẽ kết thúc và trợ lý mới tự chào.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'assistant': {
              'type': 'string',
              'enum': AssistantCatalog.all.map((a) => a.id).toList(),
            },
          },
          'required': ['assistant'],
        },
      },
      {
        'name': 'self.camera.take_photo',
        'description':
            'Chụp ảnh bằng camera trước của robot và hỏi AI về nội dung ảnh. Dùng khi người dùng hỏi '
            '"đây là cái gì", "nhìn bài tập này", "đọc giúp trang sách này", "bạn thấy gì".',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description': 'Câu hỏi về bức ảnh, ví dụ "Đề bài toán trong ảnh là gì?"',
            },
          },
          'required': ['question'],
        },
      },
      {
        'name': 'self.media.play_radio',
        'description': 'Phát kênh radio trực tiếp. Các kênh: $radioDesc.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'station': {
              'type': 'string',
              'enum': RadioCatalog.all.map((s) => s.id).toList(),
            },
          },
          'required': ['station'],
        },
      },
      {
        'name': 'self.media.play_url',
        'description': 'Phát một luồng âm thanh hoặc file nhạc từ đường link trực tiếp (mp3, m3u8, aac).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'title': {'type': 'string'},
          },
          'required': ['url'],
        },
      },
      {
        'name': 'self.media.control',
        'description': 'Điều khiển nhạc/radio đang phát: tạm dừng, phát tiếp, hoặc tắt hẳn.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['pause', 'resume', 'stop', 'status'],
            },
          },
          'required': ['action'],
        },
      },
      {
        'name': 'self.youtube.search',
        'description':
            'Mở YouTube và tìm video / bài hát theo từ khóa trên màn hình robot. Dùng khi người dùng '
            'muốn xem video, nghe một bài hát cụ thể, hoặc xem hoạt hình.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Từ khóa tìm kiếm, ví dụ "nhạc thiếu nhi"'},
          },
          'required': ['query'],
        },
      },
      {
        'name': 'self.web.search',
        'description':
            'Tìm kiếm thông tin trên Internet (tin tức, giá cả, thời tiết, kiến thức). Trả về danh sách '
            'tiêu đề, đường link và đoạn tóm tắt. Có thể gọi tiếp self.web.read_page để đọc chi tiết.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
      },
      {
        'name': 'self.web.read_page',
        'description':
            'Đọc nội dung chính của một trang web dưới dạng chữ (đã bỏ quảng cáo, menu) để tóm tắt cho người dùng.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
          },
          'required': ['url'],
        },
      },
      {
        'name': 'self.browser.open',
        'description': 'Mở trang web trên màn hình robot bằng trình duyệt chặn quảng cáo.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
          },
          'required': ['url'],
        },
      },
      {
        'name': 'self.browser.close',
        'description': 'Đóng trình duyệt / YouTube đang mở trên màn hình, quay về khuôn mặt Mina.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'self.screen.set_emotion',
        'description': 'Đổi biểu cảm khuôn mặt trên màn hình robot.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'emotion': {
              'type': 'string',
              'enum': ['happy', 'love', 'surprised', 'sleepy', 'thinking', 'idle'],
            },
          },
          'required': ['emotion'],
        },
      },
      {
        'name': 'self.audio_speaker.set_volume',
        'description': 'Chỉnh âm lượng loa của robot (0-100).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'volume': {'type': 'integer', 'minimum': 0, 'maximum': 100},
          },
          'required': ['volume'],
        },
      },
      {
        'name': 'self.robot.move',
        'description':
            'Yêu cầu robot di chuyển hoặc quay đầu. Hiện Mina CHƯA có quyền điều khiển bánh xe và đầu của '
            'Visbot (do hệ thống UBTECH khóa); robot tự di chuyển theo chương trình gốc. Gọi công cụ này để '
            'biết trạng thái và giải thích cho người dùng.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['forward', 'backward', 'turn_left', 'turn_right', 'head_left', 'head_right', 'stop'],
            },
          },
          'required': ['direction'],
        },
      },
    ];
  }

  Future<String> _executeTool(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'self.assistant.switch':
        final target = AssistantCatalog.byId(args['assistant']?.toString());
        if (target.id == activeAssistantId()) {
          return 'Bạn đang là ${target.name} rồi.';
        }
        // Chuyển sau một nhịp để server kịp nhận kết quả và nói câu chuyển tiếp
        Future<void>.delayed(const Duration(milliseconds: 2500), () => onSwitchAssistant(target.id));
        return 'Đang chuyển sang ${target.name}. Hãy nói một câu ngắn như "Mình chuyển sang ${target.name} nhé" rồi dừng.';

      case 'self.camera.take_photo':
        return _takePhotoAndExplain(args['question']?.toString() ?? 'Trong ảnh có gì?');

      case 'self.media.play_radio':
        final st = RadioCatalog.byId(args['station']?.toString());
        if (st == null) return 'Không có kênh radio này.';
        final ok = await MinaPlatform.mediaPlay(st.url, title: st.name);
        onEmotionChanged(MinaEmotion.happy);
        if (ok) await onMediaStarted();
        return ok
            ? 'Đã bật ${st.name}. Hãy xác nhận thật ngắn, radio sẽ phát ngay sau câu trả lời.'
            : 'Không mở được ${st.name}, có thể mạng đang yếu.';

      case 'self.media.play_url':
        final url = args['url']?.toString() ?? '';
        if (url.isEmpty) return 'Thiếu đường link.';
        final ok = await MinaPlatform.mediaPlay(url, title: args['title']?.toString() ?? '');
        if (ok) await onMediaStarted();
        return ok ? 'Đang phát (sau câu trả lời).' : 'Không phát được đường link này.';

      case 'self.media.control':
        final action = args['action']?.toString() ?? 'status';
        switch (action) {
          case 'pause':
            await MinaPlatform.mediaPause();
            return 'Đã tạm dừng.';
          case 'resume':
            await MinaPlatform.mediaResume();
            await onMediaStarted();
            return 'Sẽ phát tiếp sau câu trả lời.';
          case 'stop':
            await MinaPlatform.mediaStop();
            return 'Đã tắt nhạc/radio.';
          default:
            final st = await MinaPlatform.mediaState();
            return st['playing'] == true ? 'Đang phát: ${st['title'] ?? ''}' : 'Không có gì đang phát.';
        }

      case 'self.youtube.search':
        final q = args['query']?.toString() ?? '';
        await MinaPlatform.mediaStop();
        await MinaPlatform.openBrowser(
            'https://m.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}');
        // Kết thúc phiên sau câu trả lời để mic không thu tiếng video
        await onMediaStarted();
        return 'Đã mở kết quả YouTube cho "$q" trên màn hình. Người dùng chạm vào video để xem. Hãy xác nhận thật ngắn.';

      case 'self.web.search':
        final q = args['query']?.toString() ?? '';
        final results = await MinaWebTools.search(q);
        if (results.isEmpty) return 'Không tìm thấy kết quả cho "$q".';
        final buf = StringBuffer('Kết quả tìm kiếm cho "$q":\n');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          buf.writeln('${i + 1}. ${r.title}\n   ${r.url}\n   ${r.snippet}');
        }
        return buf.toString();

      case 'self.web.read_page':
        return MinaWebTools.readPage(args['url']?.toString() ?? '');

      case 'self.browser.open':
        var url = args['url']?.toString() ?? '';
        if (!url.startsWith('http')) url = 'https://$url';
        await MinaPlatform.openBrowser(url);
        return 'Đã mở trang $url (đã bật chặn quảng cáo).';

      case 'self.browser.close':
        await MinaPlatform.closeBrowser();
        return 'Đã đóng trình duyệt.';

      case 'self.screen.set_emotion':
        final emoStr = args['emotion']?.toString() ?? 'happy';
        onEmotionChanged(parseEmotionFromXiaozhi(emoStr));
        return 'Đã đổi biểu cảm sang $emoStr.';

      case 'self.audio_speaker.set_volume':
        final vol = (_asInt(args['volume']) ?? 80).clamp(0, 100).toInt();
        await audioService.setVolume(vol);
        return 'Đã đặt âm lượng $vol%.';

      case 'self.robot.move':
        return 'Mina chưa có quyền điều khiển bánh xe/đầu của robot Visbot: hệ thống UBTECH chỉ cho phép '
            'ứng dụng có chữ ký của hãng. Robot vẫn tự di chuyển theo chương trình gốc. '
            'Hãy giải thích ngắn gọn điều này cho người dùng.';

      default:
        return 'Không tìm thấy công cụ $name.';
    }
  }

  Future<String> _takePhotoAndExplain(String question) async {
    if (!hasVision) {
      return 'Server XiaoZhi chưa bật tính năng phân tích ảnh cho thiết bị này (không có cấu hình vision).';
    }
    onEmotionChanged(MinaEmotion.thinking);
    final jpeg = await MinaPlatform.takePhoto();
    if (jpeg == null || jpeg.isEmpty) {
      return 'Không chụp được ảnh từ camera.';
    }
    onLog?.call('VISION', 'Đã chụp ảnh ${jpeg.length ~/ 1024} KB, gửi phân tích...');

    final req = http.MultipartRequest('POST', Uri.parse(_visionUrl!))
      ..headers['Device-Id'] = deviceMac()
      ..headers['Client-Id'] = clientId()
      ..fields['question'] = question
      ..files.add(http.MultipartFile.fromBytes('file', jpeg,
          filename: 'camera.jpg', contentType: MediaType('image', 'jpeg')));
    if ((_visionToken ?? '').isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $_visionToken';
    }
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      return 'Server phân tích ảnh báo lỗi HTTP ${streamed.statusCode}: $body';
    }
    // Server thường trả JSON {"success":true,"result":"..."}; nếu không thì trả nguyên văn
    try {
      final m = jsonDecode(body);
      if (m is Map && m['result'] != null) return m['result'].toString();
    } catch (_) {}
    return body;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return num.tryParse(v.toString().trim())?.toInt();
  }
}
