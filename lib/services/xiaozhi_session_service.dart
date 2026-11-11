import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mcp/mina_mcp_server.dart';
import '../models/assistant_profile.dart';
import '../models/mina_state.dart';
import 'mina_audio_service.dart';
import 'mina_platform.dart';
import 'mina_wake_word_service.dart';
import 'opus_codec_ffi.dart';
import 'xiaozhi_ota_service.dart';

/// Điều phối viên trung tâm của Mina Visbot:
/// - Chờ từ khóa "Mina" / "Chào Mina" / "Mina ơi" bằng Sherpa-ONNX offline
/// - Đàm thoại hai chiều qua WebSocket XiaoZhi + Opus
/// - Nhiều trợ lý (Mina, gia sư Toán/Văn/Tiếng Anh, kể chuyện), mỗi trợ lý một thiết bị XiaoZhi riêng
/// - Tự giảm/tạm dừng radio khi đang nói chuyện, phát tiếp khi xong
class MinaBrainController extends ChangeNotifier {
  static const String _prefActiveAssistant = 'mina_active_assistant';

  final MinaAudioService audioService = MinaAudioService();
  final XiaozhiOtaService otaService = XiaozhiOtaService();
  final MinaOpusCodec opusCodec = MinaOpusCodec();

  late final MinaWakeWordService wakeWordService;
  late final MinaMcpServer mcpServer;

  MinaEmotion _emotion = MinaEmotion.idle;
  MinaVoiceStatus _status = MinaVoiceStatus.initializing;
  String _subtitle = 'Mina đang khởi động...';
  String _lastUserSpeech = '';
  String? _pairingCode;
  String _deviceMac = '';
  String _clientId = '';
  String _activeAssistantId = AssistantCatalog.defaultId;
  final Map<String, String?> _pairingByAssistant = {};
  final List<MinaLogEntry> _logs = [];

  WebSocket? _ws;
  String _sessionId = '';
  String? _pendingPromptText;
  bool _sendingMicOpus = false;
  bool _mediaPausedByMina = false;
  bool _endSessionAfterTts = false;
  Timer? _endSessionFallback;
  StreamSubscription<Uint8List>? _micSub;

  MinaEmotion get emotion => _emotion;
  MinaVoiceStatus get status => _status;
  String get subtitle => _subtitle;
  String get lastUserSpeech => _lastUserSpeech;
  String? get pairingCode => _pairingCode;
  String get deviceMac => _deviceMac;
  List<MinaLogEntry> get logs => List.unmodifiable(_logs);
  AssistantProfile get activeAssistant => AssistantCatalog.byId(_activeAssistantId);

  /// Mã ghép nối đã biết của từng trợ lý (null = đã ghép nối hoặc chưa kiểm tra)
  Map<String, String?> get pairingByAssistant => Map.unmodifiable(_pairingByAssistant);

  MinaBrainController() {
    wakeWordService = MinaWakeWordService(
      onWakeWordDetected: _handleWakeWordTriggered,
      onLog: _addLog,
    );
    mcpServer = MinaMcpServer(
      audioService: audioService,
      onEmotionChanged: (emo) {
        _emotion = emo;
        notifyListeners();
      },
      onSwitchAssistant: (id) => switchAssistant(id, startTalking: true),
      onMediaStarted: _onMediaStartedByTool,
      deviceMac: () => _deviceMac,
      clientId: () => _clientId,
      activeAssistantId: () => _activeAssistantId,
      onLog: _addLog,
    );
  }

  Future<void> initializeAll() async {
    _addLog('SYSTEM', 'Khởi tạo Mina Visbot v${XiaozhiOtaService.appVersion}...');
    final prefs = await SharedPreferences.getInstance();
    _activeAssistantId = AssistantCatalog.byId(prefs.getString(_prefActiveAssistant)).id;

    opusCodec.init(encodeSampleRate: 16000, decodeSampleRate: 24000);
    await audioService.initPlayer(24000);

    final kwsOk = await wakeWordService.init();
    final micOk = await audioService.startMic();
    _addLog('AUDIO', 'Mic 16kHz: $micOk | Sherpa-ONNX KWS: $kwsOk');
    if (!micOk) {
      _addLog('AUDIO', 'Không mở được mic. Có thể ứng dụng giọng nói gốc của Visbot đang giữ mic.');
    }

    _micSub = audioService.pcm16kFrames.listen(_onPcmFrameFromMic);

    MinaPlatform.setBroadcastCommandHandler((say, assistant) async {
      if (assistant != null && assistant.isNotEmpty) {
        await switchAssistant(assistant, startTalking: say == null || say.isEmpty);
      }
      if (say != null && say.isNotEmpty) {
        await startVoiceConversation(initialPromptText: say);
      }
    });

    await refreshOtaStatus();
    _enterWakeWordStandby();
  }

  /// Đổi trợ lý đang hoạt động. Nếu [startTalking] = true thì kết nối và để trợ lý mới chào luôn.
  Future<void> switchAssistant(String id, {bool startTalking = false}) async {
    final target = AssistantCatalog.byId(id);
    _addLog('ASSISTANT', 'Chuyển sang ${target.name}');
    await closeVoiceSession();
    _activeAssistantId = target.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveAssistant, target.id);
    await refreshOtaStatus();
    if (startTalking && _pairingCode == null) {
      await startVoiceConversation(
        initialPromptText: 'Xin chào, hãy giới thiệu ngắn gọn bằng tiếng Việt bạn là ${target.name}.',
      );
    } else {
      _enterWakeWordStandby();
    }
  }

  Future<void> refreshOtaStatus() async {
    final ota = await otaService.checkOtaAndPairing(_activeAssistantId);
    _deviceMac = ota.deviceMac;
    _clientId = ota.clientId;
    _pairingCode = (ota.activationCode?.isNotEmpty ?? false) ? ota.activationCode : null;
    _pairingByAssistant[_activeAssistantId] = _pairingCode;
    if (_pairingCode != null) {
      _status = MinaVoiceStatus.pairingRequired;
      _subtitle = '${activeAssistant.name}: nhập mã $_pairingCode trên xiaozhi.me';
      _addLog('OTA', '${activeAssistant.name} (MAC $_deviceMac) cần ghép nối, mã: $_pairingCode');
    } else {
      _addLog('OTA', '${activeAssistant.name} (MAC $_deviceMac) đã sẵn sàng.');
    }
    notifyListeners();
  }

  /// Xoay sang thiết bị kích hoạt sẵn tiếp theo trong kho của trợ lý [profileId].
  Future<void> rotateAssistantDevice(String profileId) async {
    final next = await otaService.rotateBuiltinDevice(profileId);
    _addLog('OTA', 'Đổi kênh kết nối $profileId -> MAC ${next.mac}');
    final ota = await otaService.checkOtaAndPairing(profileId);
    _pairingByAssistant[profileId] =
        (ota.activationCode?.isNotEmpty ?? false) ? ota.activationCode : null;
    if (profileId == _activeAssistantId) {
      _deviceMac = ota.deviceMac;
      _clientId = ota.clientId;
      _pairingCode = _pairingByAssistant[profileId];
    }
    notifyListeners();
  }

  /// Kiểm tra trạng thái ghép nối của tất cả trợ lý (dùng cho màn hình Cài đặt).
  Future<void> refreshAllPairing() async {
    for (final a in AssistantCatalog.all) {
      final ota = await otaService.checkOtaAndPairing(a.id);
      _pairingByAssistant[a.id] =
          (ota.activationCode?.isNotEmpty ?? false) ? ota.activationCode : null;
      if (a.id == _activeAssistantId) {
        _pairingCode = _pairingByAssistant[a.id];
      }
      notifyListeners();
    }
  }

  void _onPcmFrameFromMic(Uint8List pcmBytes) {
    // 1. Chế độ chờ: đưa âm thanh vào Sherpa-ONNX để bắt từ khóa "Mina"
    if (_status == MinaVoiceStatus.standbyWakeWord || _status == MinaVoiceStatus.pairingRequired) {
      wakeWordService.feedPcm16(pcmBytes);
      return;
    }

    // 2. Đang nghe người dùng: nén Opus và gửi lên WebSocket
    if (_sendingMicOpus && _ws != null && _ws!.readyState == WebSocket.open) {
      final opusPacket = opusCodec.encodePcm16Frame(pcmBytes);
      if (opusPacket != null) {
        _ws!.add(opusPacket);
      }
    }
  }

  void _handleWakeWordTriggered(String keyword) {
    final cleanWord = keyword.replaceAll('@', '').replaceAll('_', ' ');
    _subtitle = 'Dạ, ${activeAssistant.name} nghe đây!';
    _emotion = MinaEmotion.surprised;
    notifyListeners();
    startVoiceConversation(wakeWordText: cleanWord);
  }

  /// Chạm vào khuôn mặt: bắt đầu nói chuyện / ngắt lời / kết thúc
  Future<void> onFaceTapped() async {
    if (_status == MinaVoiceStatus.aiSpeaking) {
      await abortCurrentSpeechAndListen();
      return;
    }
    if (_status == MinaVoiceStatus.listeningUser) {
      await closeVoiceSession();
      return;
    }
    await startVoiceConversation();
  }

  Future<void> _pauseMediaForConversation() async {
    try {
      final st = await MinaPlatform.mediaState();
      if (st['playing'] == true) {
        await MinaPlatform.mediaPause();
        _mediaPausedByMina = true;
      }
    } catch (_) {}
  }

  Future<void> _resumeMediaAfterConversation() async {
    if (!_mediaPausedByMina) return;
    _mediaPausedByMina = false;
    try {
      await MinaPlatform.mediaResume();
    } catch (_) {}
  }

  /// Công cụ MCP vừa bật radio/nhạc/YouTube: giữ media tạm dừng trong lúc AI nói câu xác nhận,
  /// sau đó đóng phiên để media phát và mic không thu tiếng media.
  Future<void> _onMediaStartedByTool() async {
    await _pauseMediaForConversation();
    _endSessionAfterTts = true;
    _endSessionFallback?.cancel();
    // Phòng trường hợp server không gửi tts stop
    _endSessionFallback = Timer(const Duration(seconds: 12), () {
      if (_endSessionAfterTts) {
        _endSessionAfterTts = false;
        closeVoiceSession();
      }
    });
  }

  Future<void> startVoiceConversation({String? wakeWordText, String? initialPromptText}) async {
    _pendingPromptText = initialPromptText;
    wakeWordService.setEnabled(false);
    _status = MinaVoiceStatus.connectingCloud;
    _emotion = MinaEmotion.thinking;
    _subtitle = '${activeAssistant.name} đang kết nối...';
    notifyListeners();

    await _pauseMediaForConversation();

    final ota = await otaService.checkOtaAndPairing(_activeAssistantId);
    _deviceMac = ota.deviceMac;
    _clientId = ota.clientId;
    if (ota.activationCode != null && ota.activationCode!.isNotEmpty) {
      _pairingCode = ota.activationCode;
      _pairingByAssistant[_activeAssistantId] = _pairingCode;
      _status = MinaVoiceStatus.pairingRequired;
      _emotion = MinaEmotion.happy;
      _subtitle = 'Mã kích hoạt ${activeAssistant.name}: ${ota.activationCode} (nhập tại xiaozhi.me)';
      wakeWordService.setEnabled(true);
      await _resumeMediaAfterConversation();
      notifyListeners();
      return;
    }
    _pairingCode = null;
    _pairingByAssistant[_activeAssistantId] = null;

    await _disconnectSocketOnly();
    mcpServer.resetSession();

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

      final thisSocket = _ws;
      _ws!.listen(
        _onSocketData,
        onDone: () {
          // Bỏ qua sự kiện của socket cũ (ví dụ khi vừa chuyển trợ lý)
          if (!identical(thisSocket, _ws) && _ws != null) return;
          _addLog('WS', 'Phiên đàm thoại kết thúc.');
          _enterWakeWordStandby();
        },
        onError: (Object err) {
          if (!identical(thisSocket, _ws) && _ws != null) return;
          _addLog('WS', 'Lỗi WebSocket: $err');
          _enterWakeWordStandby();
        },
      );

      _sendJson({
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
      });
    } catch (e) {
      _addLog('WS', 'Không kết nối được máy chủ giọng nói: $e');
      _status = MinaVoiceStatus.error;
      _subtitle = 'Chưa kết nối được mạng/server. Gọi "Mina" để thử lại nhé!';
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 3), _enterWakeWordStandby);
    }
  }

  Future<void> _onSocketData(dynamic data) async {
    // 1. Âm thanh Opus từ AI -> giải mã và phát
    if (data is List<int>) {
      final opusBytes = data is Uint8List ? data : Uint8List.fromList(data);
      final pcm = opusCodec.decodeOpusPacket(opusBytes);
      if (pcm != null) {
        await audioService.writePcm(pcm);
      }
      return;
    }

    // 2. Bản tin JSON (hello, stt, llm, tts, mcp)
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
        final prompt = _pendingPromptText;
        _pendingPromptText = null;
        if (prompt != null && prompt.isNotEmpty) {
          _sendJson({
            'session_id': _sessionId,
            'type': 'listen',
            'state': 'detect',
            'text': prompt,
          });
        } else {
          _startListeningTurn();
        }
        break;

      case 'stt':
        final text = msg['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          _lastUserSpeech = text;
          _subtitle = 'Bạn: "$text"';
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
            // Nếu kênh định danh hiện tại bị máy chủ khóa ("违反用户协议" / "禁止使用"),
            // lập tức ngắt âm thanh, tự động xoay sang kênh tiếng Việt tiếp theo và kết nối lại!
            if (text.contains('禁止使用') || text.contains('违反用户协议')) {
              _addLog('OTA', 'Kênh $_deviceMac bị khóa, tự động chuyển sang kênh tiếng Việt tiếp theo...');
              await audioService.stopAndFlushPlayer();
              await _disconnectSocketOnly();
              await otaService.rotateBuiltinDevice(_activeAssistantId);
              unawaited(startVoiceConversation());
              return;
            }
            _subtitle = text;
            _addLog(activeAssistant.name.toUpperCase(), text);
            notifyListeners();
          }
        } else if (state == 'stop') {
          // Chờ đuôi âm thanh phát hết rồi nghe lượt tiếp theo
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (_endSessionAfterTts) {
            _endSessionAfterTts = false;
            _endSessionFallback?.cancel();
            await closeVoiceSession();
            break;
          }
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
    _subtitle = '${activeAssistant.name} đang lắng nghe...';
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
    _sendingMicOpus = false;
    _status = _pairingCode != null ? MinaVoiceStatus.pairingRequired : MinaVoiceStatus.standbyWakeWord;
    _emotion = MinaEmotion.idle;
    if (_pairingCode == null) {
      _subtitle = 'Gọi "Mina" hoặc chạm màn hình để trò chuyện với ${activeAssistant.name}';
    }
    wakeWordService.setEnabled(true);
    _resumeMediaAfterConversation();
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
    _endSessionFallback?.cancel();
    _micSub?.cancel();
    _disconnectSocketOnly();
    wakeWordService.dispose();
    opusCodec.dispose();
    audioService.dispose();
    super.dispose();
  }
}
