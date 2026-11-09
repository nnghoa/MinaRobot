import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mcp/mina_mcp_server.dart';
import '../models/mina_state.dart';
import '../robot/robonova_actions.dart';
import '../robot/robonova_serial_driver.dart';
import 'mina_audio_service.dart';
import 'mina_wake_word_service.dart';
import 'opus_codec_ffi.dart';
import 'xiaozhi_ota_service.dart';

/// Điều phối viên trung tâm của Robot Mina:
/// - Standby lắng nghe từ khóa "Mina" / "Chào Mina" / "Mina ơi" bằng Sherpa-ONNX Offline
/// - Đàm thoại thời gian thực hai chiều qua WebSocket XiaoZhi + Opus
/// - Xử lý lệnh MCP điều khiển toàn bộ 63 động tác & đọc cảm biến siêu âm / 10k trên mạch MR-C3024FX
class MinaBrainController extends ChangeNotifier {
  static const String _prefHwReflex = 'mina_hw_reflex';
  static const String _prefSafeWalk = 'mina_safe_walk';
  static const String _prefAutoGreetSonar = 'mina_auto_greet_sonar';
  static const String _prefAutoStandup = 'mina_auto_standup';
  static const String _prefSonarLimit = 'mina_sonar_limit_cm';
  static const String _prefDist10kLimit = 'mina_dist10k_limit';

  final MinaAudioService audioService = MinaAudioService();
  final XiaozhiOtaService otaService = XiaozhiOtaService();
  final MinaOpusCodec opusCodec = MinaOpusCodec();

  late final RobonovaSerialDriver robotDriver;
  late final MinaWakeWordService wakeWordService;
  late final MinaMcpServer mcpServer;

  MinaEmotion _emotion = MinaEmotion.idle;
  MinaVoiceStatus _status = MinaVoiceStatus.initializing;
  String _subtitle = 'Đang khởi động hệ thống thần kinh của Mina...';
  String _lastUserSpeech = '';
  String? _pairingCode;
  String _deviceMac = '';
  final List<MinaLogEntry> _logs = [];

  // Cấu hình phản xạ thông minh từ cảm biến trên Robonova-II
  bool _hardwareReflexEnabled = true;
  bool _obstacleSafeWalk = true;
  bool _autoGreetOnSonar = true;
  bool _autoStandupOnFall = false;
  int _sonarThresholdCm = 25;
  int _dist10kThreshold = 85;
  int _personInFrontHits = 0;
  bool _sonarSawClearSinceGreet = true; // Chỉ chào khi có người "tiến lại gần" (tránh chào mãi một bức tường)
  DateTime _lastAutoGreetAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFallRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);

  WebSocket? _ws;
  String _sessionId = '';
  bool _sendingMicOpus = false;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _idleResetTimer;

  MinaEmotion get emotion => _emotion;
  MinaVoiceStatus get status => _status;
  String get subtitle => _subtitle;
  String get lastUserSpeech => _lastUserSpeech;
  String? get pairingCode => _pairingCode;
  String get deviceMac => _deviceMac;
  List<MinaLogEntry> get logs => List.unmodifiable(_logs);

  RobonovaSensorState get sensorState => robotDriver.sensorState;
  bool get hardwareReflexEnabled => _hardwareReflexEnabled;
  bool get obstacleSafeWalk => _obstacleSafeWalk;
  bool get autoGreetOnSonar => _autoGreetOnSonar;
  bool get autoStandupOnFall => _autoStandupOnFall;
  int get sonarThresholdCm => _sonarThresholdCm;
  int get dist10kThreshold => _dist10kThreshold;

  MinaBrainController() {
    robotDriver = RobonovaSerialDriver(
      onLog: _addLog,
      onSensorUpdated: _handleSensorTelemetry,
    );
    wakeWordService = MinaWakeWordService(
      onWakeWordDetected: _handleWakeWordTriggered,
      onLog: _addLog,
    );
    mcpServer = MinaMcpServer(
      robotDriver: robotDriver,
      audioService: audioService,
      onEmotionChanged: (emo) {
        _emotion = emo;
        notifyListeners();
      },
      isObstacleSafeWalkEnabled: () => _obstacleSafeWalk,
      onUpdateSafetyConfig: updateSafetyConfig,
      onLog: _addLog,
    );
  }

  Future<void> initializeAll() async {
    _addLog('SYSTEM', 'Khởi tạo Mina AI v1.2.0 (Tích hợp Cảm biến Robonova-II)...');
    await _loadSensorPrefs();
    opusCodec.init(encodeSampleRate: 16000, decodeSampleRate: 24000);
    await audioService.initPlayer(24000);
    // Ghi nhớ trạng thái phản xạ mong muốn TRƯỚC khi mở cổng; openPort() sẽ tự gửi 'm'/'n' xuống MR-C3024FX
    robotDriver.setHardwareAutoReflex(_hardwareReflexEnabled);
    await robotDriver.initFromPrefs();

    final kwsOk = await wakeWordService.init();
    final micOk = await audioService.startMic();
    _addLog('AUDIO', 'Trạng thái Mic 16kHz: $micOk | Sherpa-ONNX KWS: $kwsOk');

    _micSub = audioService.pcm16kFrames.listen(_onPcmFrameFromMic);

    await refreshOtaStatus();
    _enterWakeWordStandby();
  }

  Future<void> _loadSensorPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _hardwareReflexEnabled = prefs.getBool(_prefHwReflex) ?? true;
    _obstacleSafeWalk = prefs.getBool(_prefSafeWalk) ?? true;
    _autoGreetOnSonar = prefs.getBool(_prefAutoGreetSonar) ?? true;
    // Mặc định TẮT: chương trình gốc đã comment `GOSUB robot_tilt`, chân AD(5) có thể chưa cắm cảm biến nghiêng
    _autoStandupOnFall = prefs.getBool(_prefAutoStandup) ?? false;
    _sonarThresholdCm = prefs.getInt(_prefSonarLimit) ?? 25;
    _dist10kThreshold = prefs.getInt(_prefDist10kLimit) ?? 85;
    robotDriver.updateThresholds(
      sonarThresholdCm: _sonarThresholdCm,
      dist10kThreshold: _dist10kThreshold,
    );
  }

  Future<void> updateSafetyConfig({
    bool? hardwareReflex,
    bool? obstacleSafeWalk,
    bool? autoGreet,
    bool? autoStandup,
    int? sonarThresholdCm,
    int? dist10kThreshold,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (hardwareReflex != null) {
      _hardwareReflexEnabled = hardwareReflex;
      await prefs.setBool(_prefHwReflex, hardwareReflex);
      robotDriver.setHardwareAutoReflex(hardwareReflex);
    }
    if (obstacleSafeWalk != null) {
      _obstacleSafeWalk = obstacleSafeWalk;
      await prefs.setBool(_prefSafeWalk, obstacleSafeWalk);
    }
    if (autoGreet != null) {
      _autoGreetOnSonar = autoGreet;
      await prefs.setBool(_prefAutoGreetSonar, autoGreet);
    }
    if (autoStandup != null) {
      _autoStandupOnFall = autoStandup;
      await prefs.setBool(_prefAutoStandup, autoStandup);
    }
    if (sonarThresholdCm != null) {
      _sonarThresholdCm = sonarThresholdCm;
      await prefs.setInt(_prefSonarLimit, sonarThresholdCm);
    }
    if (dist10kThreshold != null) {
      _dist10kThreshold = dist10kThreshold;
      await prefs.setInt(_prefDist10kLimit, dist10kThreshold);
    }
    robotDriver.updateThresholds(
      sonarThresholdCm: _sonarThresholdCm,
      dist10kThreshold: _dist10kThreshold,
    );
    notifyListeners();
  }

  void _handleSensorTelemetry(RobonovaSensorState s) {
    final now = DateTime.now();

    // 1. Phản xạ tự đứng dậy khi cảm biến nghiêng AD(5) báo ngã ngửa / ngã sấp (cooldown 8 giây)
    if (_autoStandupOnFall &&
        (s.isFallenBack || s.isFallenFront) &&
        now.difference(_lastFallRecoveryAt).inSeconds >= 8) {
      _lastFallRecoveryAt = now;
      _emotion = MinaEmotion.surprised;
      final slug = s.isFallenBack ? 'stand_up_from_back' : 'stand_up_from_front';
      final act = RobonovaActionCatalog.findBySlugOrId(slug);
      _subtitle = s.isFallenBack
          ? 'Ái chà! Mina bị ngã ngửa rồi, để Mina tự đứng dậy (K19) nhé!'
          : 'Ối! Mina bị ngã sấp rồi, Mina tự chống tay đứng dậy (K25) đây!';
      _addLog('REFLEX', 'Phát hiện ${s.postureLabel} (AD5=${s.tiltRaw}) -> Tự động gọi $slug');
      if (act != null) {
        // Android là nơi ra quyết định đứng dậy (firmware để CONST TILT_ON = 0 để tránh 2 bên cùng kích hoạt)
        robotDriver.executeAction(act);
      }
      notifyListeners();
      return;
    }

    // 2. Phản xạ chủ động vẫy tay & bắt chuyện khi mắt siêu âm SONAR(5) thấy người tiến lại gần (15..65 cm)
    final sonar = s.sonarCm;
    if (sonar == null || sonar > 90) {
      _sonarSawClearSinceGreet = true;
    }
    if (_autoGreetOnSonar &&
        _sonarSawClearSinceGreet &&
        _status == MinaVoiceStatus.standbyWakeWord &&
        sonar != null &&
        sonar >= 15 &&
        sonar <= 65) {
      _personInFrontHits++;
      if (_personInFrontHits >= 2 && now.difference(_lastAutoGreetAt).inSeconds >= 45) {
        _personInFrontHits = 0;
        _sonarSawClearSinceGreet = false;
        _lastAutoGreetAt = now;
        _emotion = MinaEmotion.happy;
        _subtitle = 'Mắt siêu âm thấy có người ở cách ${s.sonarCm} cm! Xin chào nhé!';
        _addLog('REFLEX', 'Mắt siêu âm phát hiện người (${s.sonarCm} cm) -> Vẫy tay K7 & Mở hội thoại');
        final waveAct = RobonovaActionCatalog.findBySlugOrId('wave_arms');
        if (waveAct != null) {
          robotDriver.executeAction(waveAct);
        }
        startVoiceConversation(wakeWordText: 'Phát hiện người đứng trước mặt Mina');
        return;
      }
    } else {
      _personInFrontHits = 0;
    }

    notifyListeners();
  }

  Future<void> refreshOtaStatus() async {
    final ota = await otaService.checkOtaAndPairing();
    _deviceMac = ota.deviceMac;
    _pairingCode = ota.activationCode;
    if (_pairingCode != null && _pairingCode!.isNotEmpty) {
      _status = MinaVoiceStatus.pairingRequired;
      _subtitle = 'Nhập mã $_pairingCode trên trang xiaozhi.me để kích hoạt Mina miễn phí!';
      _addLog('OTA', 'Mã ghép nối XiaoZhi của Mina (MAC $_deviceMac): $_pairingCode');
    } else {
      _addLog('OTA', 'Thiết bị Mina (MAC $_deviceMac) đã sẵn sàng kết nối XiaoZhi!');
    }
    notifyListeners();
  }

  void _onPcmFrameFromMic(Uint8List pcmBytes) {
    // 1. Khi ở chế độ chờ: đưa âm thanh vào Sherpa-ONNX để bắt từ khóa "Mina"
    if (_status == MinaVoiceStatus.standbyWakeWord || _status == MinaVoiceStatus.pairingRequired) {
      wakeWordService.feedPcm16(pcmBytes);
      return;
    }

    // 2. Khi đang lắng nghe người dùng nói chuyện với AI: nén sang Opus và đẩy thẳng lên WebSocket
    if (_sendingMicOpus && _ws != null && _ws!.readyState == WebSocket.open) {
      final opusPacket = opusCodec.encodePcm16Frame(pcmBytes);
      if (opusPacket != null) {
        _ws!.add(opusPacket);
      }
    }
  }

  void _handleWakeWordTriggered(String keyword) {
    final cleanWord = keyword.replaceAll('@', '').replaceAll('_', ' ');
    _subtitle = 'Dạ, Mina nghe đây! ($cleanWord)';
    _emotion = MinaEmotion.surprised;
    notifyListeners();
    startVoiceConversation(wakeWordText: cleanWord);
  }

  /// Người dùng gọi "Mina" hoặc chạm vào màn hình khuôn mặt của Mina
  Future<void> onFaceTapped() async {
    if (_status == MinaVoiceStatus.aiSpeaking) {
      // Barge-in: Ngắt lời AI để người dùng nói câu mới ngay lập tức
      await abortCurrentSpeechAndListen();
      return;
    }
    if (_status == MinaVoiceStatus.listeningUser) {
      await closeVoiceSession();
      return;
    }
    await startVoiceConversation();
  }

  Future<void> startVoiceConversation({String? wakeWordText}) async {
    wakeWordService.setEnabled(false);
    _status = MinaVoiceStatus.connectingCloud;
    _emotion = MinaEmotion.thinking;
    _subtitle = 'Mina đang kết nối...';
    notifyListeners();

    final ota = await otaService.checkOtaAndPairing();
    _deviceMac = ota.deviceMac;
    if (ota.activationCode != null && ota.activationCode!.isNotEmpty) {
      _pairingCode = ota.activationCode;
      _status = MinaVoiceStatus.pairingRequired;
      _emotion = MinaEmotion.happy;
      _subtitle = 'Mã kích hoạt của Mina là: ${ota.activationCode} (nhập tại xiaozhi.me)';
      wakeWordService.setEnabled(true);
      notifyListeners();
      return;
    }
    _pairingCode = null;

    await _disconnectSocketOnly();

    try {
      _addLog('WS', 'Kết nối tới ${ota.wsUrl}...');
      _ws = await WebSocket.connect(
        ota.wsUrl,
        headers: {
          'Authorization': 'Bearer ${ota.wsToken}',
          'Protocol-Version': '1',
          'Device-Id': ota.deviceMac,
          'Client-Id': ota.clientId,
        },
      ).timeout(const Duration(seconds: 10));

      _ws!.listen(
        _onSocketData,
        onDone: () {
          _addLog('WS', 'Phiên đàm thoại kết thúc.');
          _enterWakeWordStandby();
        },
        onError: (Object err) {
          _addLog('WS', 'Lỗi WebSocket: $err');
          _enterWakeWordStandby();
        },
      );

      // Gửi gói bắt tay Hello đăng ký chuẩn âm thanh Opus 16kHz + bật tính năng MCP Tools!
      final helloMsg = {
        'type': 'hello',
        'version': 1,
        'features': {
          'mcp': true,
        },
        'transport': 'websocket',
        'audio_params': {
          'format': 'opus',
          'sample_rate': 16000,
          'channels': 1,
          'frame_duration': 60,
        },
      };
      _sendJson(helloMsg);
    } catch (e) {
      _addLog('WS', 'Không kết nối được máy chủ giọng nói: $e');
      _status = MinaVoiceStatus.error;
      _subtitle = 'Chưa kết nối được Wi-Fi/Server. Hãy gọi "Mina" để thử lại nhé!';
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 3), _enterWakeWordStandby);
    }
  }

  Future<void> _onSocketData(dynamic data) async {
    // 1. Khung âm thanh nhị phân Opus từ AI trả về -> Giải mã và phát loa tức thì
    if (data is List<int>) {
      final opusBytes = data is Uint8List ? data : Uint8List.fromList(data);
      final pcm = opusCodec.decodeOpusPacket(opusBytes);
      if (pcm != null) {
        await audioService.writePcm(pcm);
      }
      return;
    }

    // 2. Bản tin điều khiển JSON (hello, stt, llm, tts, mcp)
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type']?.toString() ?? '';
    switch (type) {
      case 'hello':
        _sessionId = msg['session_id']?.toString() ?? '';
        final audioParams = (msg['audio_params'] as Map?)?.cast<String, dynamic>();
        final serverSampleRate = (audioParams?['sample_rate'] as num?)?.toInt() ?? 24000;
        opusCodec.initDecoder(serverSampleRate);
        await audioService.initPlayer(serverSampleRate);
        _addLog('WS', 'Bắt tay thành công! session=$_sessionId, TTS=${serverSampleRate}Hz');
        _startListeningTurn();
        break;

      case 'stt':
        final text = msg['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          _lastUserSpeech = text;
          _subtitle = 'Anh: "$text"';
          _emotion = MinaEmotion.thinking;
          _sendingMicOpus = false;
          _addLog('STT', text);
          notifyListeners();
        }
        break;

      case 'llm':
        final emo = msg['emotion']?.toString() ?? '';
        if (emo.isNotEmpty) {
          _emotion = parseEmotionFromXiaozhi(emo);
          notifyListeners();
        }
        break;

      case 'tts':
        final state = msg['state']?.toString() ?? '';
        if (state == 'start') {
          _sendingMicOpus = false;
          _status = MinaVoiceStatus.aiSpeaking;
          if (_emotion == MinaEmotion.listening || _emotion == MinaEmotion.thinking) {
            _emotion = MinaEmotion.speaking;
          }
          notifyListeners();
        } else if (state == 'sentence_start') {
          final text = msg['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            _subtitle = text;
            _addLog('MINA', text);
            notifyListeners();
          }
        } else if (state == 'stop') {
          // Chờ đuôi âm thanh trong hàng đợi phát hết rồi tự động nghe lượt tiếp theo (Continuous Chat)
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (_ws != null && _ws!.readyState == WebSocket.open) {
            _startListeningTurn();
          }
        }
        break;

      case 'mcp':
        final payload = (msg['payload'] as Map?)?.cast<String, dynamic>();
        if (payload != null) {
          final rpcResponse = await mcpServer.handleJsonRpc(payload);
          if (rpcResponse != null) {
            _sendJson({
              'session_id': _sessionId,
              'type': 'mcp',
              'payload': rpcResponse,
            });
          }
        }
        break;

      case 'goodbye':
        await closeVoiceSession();
        break;
    }
  }

  void _startListeningTurn() {
    if (_ws == null || _ws!.readyState != WebSocket.open) return;
    _status = MinaVoiceStatus.listeningUser;
    _emotion = MinaEmotion.listening;
    _subtitle = 'Mina đang lắng nghe anh nói...';
    _sendingMicOpus = true;
    _sendJson({
      'session_id': _sessionId,
      'type': 'listen',
      'state': 'start',
      'mode': 'auto',
    });
    notifyListeners();
  }

  Future<void> abortCurrentSpeechAndListen() async {
    await audioService.stopAndFlushPlayer();
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      _sendJson({
        'session_id': _sessionId,
        'type': 'abort',
        'reason': 'wake_word_detected',
      });
      _startListeningTurn();
    }
  }

  Future<void> closeVoiceSession() async {
    _sendingMicOpus = false;
    await audioService.stopAndFlushPlayer();
    await _disconnectSocketOnly();
    _enterWakeWordStandby();
  }

  void _enterWakeWordStandby() {
    _idleResetTimer?.cancel();
    _sendingMicOpus = false;
    _status = _pairingCode != null ? MinaVoiceStatus.pairingRequired : MinaVoiceStatus.standbyWakeWord;
    _emotion = MinaEmotion.idle;
    if (_pairingCode == null) {
      _subtitle = 'Gọi "Mina", "Chào Mina" hoặc chạm màn hình để trò chuyện';
    }
    wakeWordService.setEnabled(true);
    notifyListeners();
  }

  Future<void> _disconnectSocketOnly() async {
    final old = _ws;
    _ws = null;
    _sessionId = '';
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      _ws!.add(jsonEncode(data));
    }
  }

  void _addLog(String tag, String message) {
    _logs.insert(0, MinaLogEntry(time: DateTime.now(), tag: tag, message: message));
    if (_logs.length > 150) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _idleResetTimer?.cancel();
    _micSub?.cancel();
    _disconnectSocketOnly();
    robotDriver.closePort();
    wakeWordService.dispose();
    opusCodec.dispose();
    audioService.dispose();
    super.dispose();
  }
}
