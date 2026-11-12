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
/// - Chuyển trợ lý tức thì (Kiểu A: ~0.5s, không chặn bởi HTTP OTA hay socket cũ)
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
  String? _ignoreSttEchoText;
  String? _customListeningSubtitle;
  DateTime _ttsStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sendingMicOpus = false;
  bool _mediaPausedByMina = false;
  bool _endSessionAfterTts = false;
  int _connectEpoch = 0;
  Timer? _connectWatchdog;
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
  bool get isInConversation =>
      _status == MinaVoiceStatus.aiSpeaking ||
      _status == MinaVoiceStatus.listeningUser ||
      _status == MinaVoiceStatus.connectingCloud;

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
      onResetTopic: () => resetTopicAndListen(reason: 'MCP reset_topic'),
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

    MinaPlatform.setBroadcastCommandHandler((say, assistant, resetTopic) async {
      if (resetTopic) {
        await resetTopicAndListen(reason: 'Broadcast resetTopic');
        return;
      }
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

  /// Đổi trợ lý đang hoạt động:
  /// ngắt phiên cũ không chặn (non-blocking), bỏ qua HTTP OTA, mở thẳng WebSocket và để trợ lý mới tự chào ngay (~1.2–2s).
  Future<void> switchAssistant(String id, {bool startTalking = false}) async {
    final target = AssistantCatalog.byId(id);
    _addLog('ASSISTANT', 'Chuyển nhanh sang ${target.name}');
    _connectEpoch++;
    _sendingMicOpus = false;
    unawaited(audioService.stopAndFlushPlayer());
    await _disconnectSocketOnly();

    _activeAssistantId = target.id;
    unawaited(
      SharedPreferences.getInstance().then((prefs) => prefs.setString(_prefActiveAssistant, target.id)),
    );

    if (startTalking) {
      // Dùng từ khóa ngắn "Xin chào" chuẩn giao thức detect để máy chủ phát lời chào ngay (~0.4s vào TTS)
      await startVoiceConversation(initialPromptText: 'Xin chào');
    } else {
      await refreshOtaStatus();
      _enterWakeWordStandby();
    }
  }

  Future<void> refreshOtaStatus({bool forceRemoteCheck = false}) async {
    final ota = await otaService.checkOtaAndPairing(
      _activeAssistantId,
      forceRemoteCheck: forceRemoteCheck,
    );
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
      final ota = await otaService.checkOtaAndPairing(a.id, forceRemoteCheck: true);
      _pairingByAssistant[a.id] =
          (ota.activationCode?.isNotEmpty ?? false) ? ota.activationCode : null;
      if (a.id == _activeAssistantId) {
        _pairingCode = _pairingByAssistant[a.id];
      }
      notifyListeners();
    }
  }

  void _onPcmFrameFromMic(Uint8List pcmBytes) {
    // 1. Chế độ chờ hoặc đang phát giọng AI (barge-in): đưa âm thanh vào Sherpa-ONNX để bắt khẩu lệnh
    if (_status == MinaVoiceStatus.standbyWakeWord ||
        _status == MinaVoiceStatus.pairingRequired ||
        _status == MinaVoiceStatus.aiSpeaking) {
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

    // Khi AI đang nói (barge-in): bỏ qua từ đơn "@Mina" và 900ms đầu câu chào để tránh loa tự kích hoạt chính mình,
    // chỉ cắt lời khi người dùng gọi cụm rõ ràng ("Mina ơi", "Chào Mina", "Đổi chủ đề", "Mina dừng lại").
    if (_status == MinaVoiceStatus.aiSpeaking) {
      if (keyword == '@Mina') return;
      if (DateTime.now().difference(_ttsStartedAt).inMilliseconds < 900) return;

      if (keyword == '@Đổi_chủ_đề' || keyword == '@Mina_dừng_lại') {
        unawaited(resetTopicAndListen(reason: 'Khẩu lệnh ngắt lời "$cleanWord"'));
      } else {
        _addLog('KWS', 'Ngắt lời AI bằng khẩu lệnh "$cleanWord"');
        unawaited(abortCurrentSpeechAndListen());
      }
      return;
    }

    _subtitle = 'Dạ, ${activeAssistant.name} nghe đây!';
    _emotion = MinaEmotion.surprised;
    notifyListeners();
    startVoiceConversation(wakeWordText: cleanWord);
  }

  /// Chạm vào khuôn mặt: bắt đầu nói chuyện / ngắt lời giữ mạch bài học / kết thúc
  Future<void> onFaceTapped() async {
    if (_status == MinaVoiceStatus.aiSpeaking) {
      await abortCurrentSpeechAndListen();
      return;
    }
    if (_status == MinaVoiceStatus.listeningUser || _status == MinaVoiceStatus.connectingCloud) {
      await closeVoiceSession();
      return;
    }
    await startVoiceConversation();
  }

  /// Ấn nút cứng phía trước trên thân robot Visbot:
  /// - Khi đang học / AI đang giảng dài hoặc lạc đề: dừng tiếng ngay lập tức (0ms) + xóa sạch ngữ cảnh cũ + mở mic chủ đề mới (~0.5s).
  /// - Khi đang ở chế độ chờ (Standby): đánh thức gia sư nghe ngay không cần gọi tên.
  Future<void> onFrontButtonPressed({String source = 'front_button'}) async {
    _addLog('BUTTON', 'Ấn nút phía trước ($source) khi status=$_status');
    if (isInConversation) {
      await resetTopicAndListen(reason: 'Nút cứng phía trước');
    } else {
      await startVoiceConversation();
    }
  }

  /// Dừng ngay lập tức câu nói hiện tại VÀ mở phiên WebSocket mới tinh (xóa sạch mạch lạc đề cũ trên server),
  /// vào thẳng chế độ lắng nghe chủ đề mới (~0.5s, không lặp lại câu chào dài dòng).
  Future<void> resetTopicAndListen({String reason = 'Đổi chủ đề'}) async {
    _addLog('TOPIC', '$reason -> Xóa ngữ cảnh cũ, mở chủ đề mới (${activeAssistant.name})');
    _connectEpoch++;
    _sendingMicOpus = false;
    _endSessionAfterTts = false;
    _endSessionFallback?.cancel();
    await audioService.stopAndFlushPlayer();
    await _disconnectSocketOnly();
    await startVoiceConversation(
      connectingSubtitle: '🔄 Đã dừng! Đang mở chủ đề mới...',
      listeningSubtitle: '🔄 Chủ đề mới — ${activeAssistant.name} đang lắng nghe...',
    );
  }

  Future<void> _pauseMediaForConversation() async {
    try {
      await MinaPlatform.holdAudioFocus();
      final st = await MinaPlatform.mediaState();
      if (st['playing'] == true) {
        await MinaPlatform.mediaPause();
        _mediaPausedByMina = true;
      }
    } catch (_) {}
  }

  Future<void> _resumeMediaAfterConversation() async {
    try {
      await MinaPlatform.releaseAudioFocus();
    } catch (_) {}
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

  Future<void> startVoiceConversation({
    String? wakeWordText,
    String? initialPromptText,
    String? connectingSubtitle,
    String? listeningSubtitle,
    int retryCount = 0,
  }) async {
    final myEpoch = ++_connectEpoch;
    _connectWatchdog?.cancel();
    _pendingPromptText = initialPromptText;
    _customListeningSubtitle = listeningSubtitle;
    _sendingMicOpus = false;
    wakeWordService.setEnabled(false);
    _status = MinaVoiceStatus.connectingCloud;
    _emotion = MinaEmotion.thinking;
    _subtitle = connectingSubtitle ?? '${activeAssistant.name} đang kết nối...';
    notifyListeners();

    unawaited(_pauseMediaForConversation());

    final ota = await otaService.checkOtaAndPairing(_activeAssistantId);
    if (myEpoch != _connectEpoch) return;

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

    // Chống treo tuyệt đối khi Wi-Fi khách sạn chuyển AP (roaming) hoặc mất gói tin hello
    _connectWatchdog = Timer(const Duration(seconds: 6), () {
      if (myEpoch != _connectEpoch || _status != MinaVoiceStatus.connectingCloud) return;
      _addLog('WS', 'Quá 6s chờ bắt tay (${activeAssistant.name}), tự động kết nối lại...');
      unawaited(_disconnectSocketOnly());
          if (retryCount < 1) {
            unawaited(
              startVoiceConversation(
                wakeWordText: wakeWordText,
                initialPromptText: initialPromptText,
                connectingSubtitle: connectingSubtitle,
                listeningSubtitle: listeningSubtitle,
                retryCount: retryCount + 1,
              ),
            );
          } else {
        _enterWakeWordStandby();
      }
    });

    try {
      _addLog('WS', 'Kết nối nhanh ${activeAssistant.name} (MAC ${ota.deviceMac})...');
      final sock = await WebSocket.connect(
        ota.wsUrl,
        headers: {
          'Authorization': 'Bearer ${ota.wsToken}',
          'Protocol-Version': '1',
          'Device-Id': ota.deviceMac,
          'Client-Id': ota.clientId,
        },
      ).timeout(const Duration(seconds: 5));

      if (myEpoch != _connectEpoch) {
        unawaited(
          sock.close().timeout(const Duration(milliseconds: 300), onTimeout: () => null).catchError((_) => null),
        );
        return;
      }

      sock.pingInterval = const Duration(seconds: 10);
      _ws = sock;

      sock.listen(
        (dynamic data) => _onSocketData(sock, data),
        onDone: () {
          if (!identical(sock, _ws)) return;
          _addLog('WS', 'Phiên đàm thoại kết thúc.');
          _enterWakeWordStandby();
        },
        onError: (Object err) {
          if (!identical(sock, _ws)) return;
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
      if (myEpoch != _connectEpoch) return;
      _connectWatchdog?.cancel();
      _connectWatchdog = null;
      _addLog('WS', 'Không kết nối được máy chủ giọng nói: $e');
      if (retryCount < 1) {
        unawaited(
          startVoiceConversation(
            wakeWordText: wakeWordText,
            initialPromptText: initialPromptText,
            connectingSubtitle: connectingSubtitle,
            listeningSubtitle: listeningSubtitle,
            retryCount: retryCount + 1,
          ),
        );
        return;
      }
      _status = MinaVoiceStatus.error;
      _subtitle = 'Chưa kết nối được mạng/server. Gọi "Mina" hoặc chạm màn hình để thử lại nhé!';
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (myEpoch == _connectEpoch) _enterWakeWordStandby();
      });
    }
  }

  /// Nhận diện trực tiếp các câu lệnh giọng nói đổi trợ lý ("Quay lại Mina", "Chuyển sang Gia sư Toán"...)
  /// để chuyển tức thì (< 0.5s) mà không bị phụ thuộc vào việc LLM trên server có gọi MCP hay không.
  String? _matchVoiceSwitchTarget(String rawText) {
    final s = rawText.trim().toLowerCase();
    if (s.isEmpty) return null;

    const switchVerbs = [
      'quay lại',
      'quay về',
      'trở lại',
      'trở về',
      'về với',
      'chuyển sang',
      'chuyển qua',
      'đổi sang',
      'đổi qua',
      'cho gặp',
      'muốn gặp',
      'gặp ',
      'gọi ',
      'switch to',
      'back to',
      'return to',
    ];
    final hasSwitchIntent = switchVerbs.any((v) => s.contains(v));
    if (!hasSwitchIntent) return null;

    if (s.contains('tiếng anh') || s.contains('anh văn') || s.contains('english')) {
      return 'gia_su_tieng_anh';
    }
    if (s.contains('gia sư toán') || s.contains('thầy toán') || s.contains('cô toán') || s.contains('môn toán')) {
      return 'gia_su_toan';
    }
    if (s.contains('gia sư văn') ||
        s.contains('ngữ văn') ||
        s.contains('tiếng việt') ||
        s.contains('cô văn') ||
        s.contains('môn văn')) {
      return 'gia_su_van';
    }
    if (s.contains('kể chuyện') || s.contains('đọc truyện') || s.contains('cổ tích')) {
      return 'ke_chuyen';
    }
    if (s.contains('mina') || s.contains('mi na')) {
      return 'mina';
    }
    return null;
  }

  /// Nhận diện trực tiếp các khẩu lệnh muốn dừng mạch lan man / đổi chủ đề mới ngay lập tức (~0.5s)
  /// mà không để AI giải thích dài dòng thêm trên phiên hội thoại cũ.
  bool _isVoiceTopicResetCommand(String rawText) {
    final clean = rawText
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?;:"“”…]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return false;

    const exactStopCommands = {
      'dừng lại',
      'dừng lại đi',
      'dừng lại nhé',
      'thôi dừng lại',
      'thôi dừng lại đi',
      'mina dừng lại',
      'ngừng lại',
      'ngừng lại đi',
      'dừng nói',
      'thôi đừng nói nữa',
      'stop',
      'new topic',
      'change topic',
    };
    if (exactStopCommands.contains(clean)) return true;

    // Câu ngắn (<= 48 ký tự) yêu cầu đổi chủ đề / qua bài khác / báo lạc đề
    if (clean.length <= 48) {
      const resetPhrases = [
        'đổi chủ đề',
        'chủ đề mới',
        'chủ đề khác',
        'sang chủ đề khác',
        'qua chủ đề khác',
        'học bài khác',
        'qua bài khác',
        'sang bài khác',
        'đổi bài khác',
        'bài học mới',
        'bài học khác',
        'lạc đề rồi',
        'đang lạc đề',
        'bỏ qua bài này',
        'bỏ qua chủ đề này',
      ];
      if (resetPhrases.any((p) => clean.contains(p))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _onSocketData(WebSocket sourceSocket, dynamic data) async {
    if (!identical(sourceSocket, _ws)) return;

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
        _connectWatchdog?.cancel();
        _connectWatchdog = null;
        _sessionId = msg['session_id']?.toString() ?? '';
        final audioParams = (msg['audio_params'] as Map?)?.cast<String, dynamic>();
        final serverSampleRate = (audioParams?['sample_rate'] as num?)?.toInt() ?? 24000;
        opusCodec.initDecoder(serverSampleRate);
        await audioService.initPlayer(serverSampleRate);
        if (!identical(sourceSocket, _ws)) return;

        _addLog('WS', 'Bắt tay xong (${activeAssistant.name})! session=$_sessionId');
        final prompt = _pendingPromptText;
        _pendingPromptText = null;
        if (prompt != null && prompt.isNotEmpty) {
          _ignoreSttEchoText = prompt;
          _subtitle = '${activeAssistant.name} đang chào bạn...';
          notifyListeners();
          _sendJson({
            'session_id': _sessionId,
            'type': 'listen',
            'state': 'detect',
            'text': prompt,
          });
          // Nếu Wi-Fi đổi AP làm rớt gói tin quá 4s chưa phát tiếng thì tự mở mic lắng nghe, không bao giờ kẹt
          _connectWatchdog = Timer(const Duration(seconds: 4), () {
            if (identical(sourceSocket, _ws) && _status == MinaVoiceStatus.connectingCloud) {
              _ignoreSttEchoText = null;
              _startListeningTurn();
            }
          });
        } else {
          _ignoreSttEchoText = null;
          _startListeningTurn();
        }
        break;

      case 'stt':
        final text = msg['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          // Ẩn bản tin STT phản chiếu từ chính gói kích hoạt câu chào tự động ("Xin chào")
          if (_ignoreSttEchoText != null &&
              text.trim().toLowerCase() == _ignoreSttEchoText!.trim().toLowerCase()) {
            _ignoreSttEchoText = null;
            break;
          }
          _ignoreSttEchoText = null;
          _lastUserSpeech = text;
          _subtitle = 'Bạn: "$text"';
          _emotion = MinaEmotion.thinking;
          _sendingMicOpus = false;
          _addLog('STT', text);
          notifyListeners();

          final fastTarget = _matchVoiceSwitchTarget(text);
          if (fastTarget != null && fastTarget != _activeAssistantId) {
            _addLog('ASSISTANT', 'Chuyển tức thì qua giọng nói -> $fastTarget');
            unawaited(switchAssistant(fastTarget, startTalking: true));
            return;
          }

          if (_isVoiceTopicResetCommand(text)) {
            unawaited(resetTopicAndListen(reason: 'Khẩu lệnh "$text"'));
            return;
          }
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
          _connectWatchdog?.cancel();
          _connectWatchdog = null;
          _sendingMicOpus = false;
          _ttsStartedAt = DateTime.now();
          _status = MinaVoiceStatus.aiSpeaking;
          if (_emotion == MinaEmotion.listening || _emotion == MinaEmotion.thinking) {
            _emotion = MinaEmotion.speaking;
          }
          // Cho phép cắt lời bằng khẩu lệnh ("Mina ơi", "Đổi chủ đề", "Mina dừng lại") khi gia sư đang nói dài
          wakeWordService.setEnabled(true);
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
            final cleanSubtitle = text.replaceAll(RegExp(r'lily', caseSensitive: false), activeAssistant.name);
            _subtitle = cleanSubtitle;
            _addLog(activeAssistant.name.toUpperCase(), cleanSubtitle);
            notifyListeners();
          }
        } else if (state == 'stop') {
          // Chờ đuôi âm thanh phát hết rồi nghe lượt tiếp theo
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (!identical(sourceSocket, _ws)) return;
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
          if (!identical(sourceSocket, _ws)) return;
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
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
    wakeWordService.setEnabled(false);
    _status = MinaVoiceStatus.listeningUser;
    _emotion = MinaEmotion.listening;
    final customSub = _customListeningSubtitle;
    _customListeningSubtitle = null;
    _subtitle = customSub ?? '${activeAssistant.name} đang lắng nghe...';
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
    _connectEpoch++;
    _sendingMicOpus = false;
    await audioService.stopAndFlushPlayer();
    await _disconnectSocketOnly();
    _enterWakeWordStandby();
  }

  void _enterWakeWordStandby() {
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
    _sendingMicOpus = false;
    _status = _pairingCode != null ? MinaVoiceStatus.pairingRequired : MinaVoiceStatus.standbyWakeWord;
    _emotion = MinaEmotion.idle;
    if (_pairingCode == null) {
      _subtitle = 'Gọi "Mina", ấn nút trước hoặc chạm màn hình để gặp ${activeAssistant.name}';
    }
    wakeWordService.setEnabled(true);
    _resumeMediaAfterConversation();
    notifyListeners();
  }

  Future<void> _disconnectSocketOnly() async {
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
    final old = _ws;
    _ws = null;
    _sessionId = '';
    if (old != null) {
      // Đóng bất đồng bộ có giới hạn thời gian để không bao giờ bị kẹt khi Wi-Fi đổi trạm phát (AP roaming)
      unawaited(
        old.close().timeout(const Duration(milliseconds: 400), onTimeout: () => null).catchError((_) => null),
      );
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
    _connectWatchdog?.cancel();
    _endSessionFallback?.cancel();
    _micSub?.cancel();
    _disconnectSocketOnly();
    wakeWordService.dispose();
    opusCodec.dispose();
    audioService.dispose();
    super.dispose();
  }
}
