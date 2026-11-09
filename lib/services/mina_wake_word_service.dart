import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Engine TinyML nhận diện từ khóa đánh thức Offline ("Mina", "Chào Mina", "Hey Mina", "Mina ơi")
/// Chạy hoàn toàn trên một Background Isolate độc lập (numThreads: 1) với cơ chế chống dồn ứ
/// (in-flight backpressure) để luồng giao diện chính (1.ui) của Visbot MT8167 luôn mượt 100%.
class MinaWakeWordService {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerSendPort;

  bool _enabled = false;
  bool _initialized = false;
  bool _workerBusy = false;
  int _silentFrames = 0;
  DateTime _lastDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Bộ đệm gộp tối đa 4 khung (240ms = 7680 bytes) khi Isolate đang bận giải mã
  final BytesBuilder _pendingPcm = BytesBuilder(copy: false);
  static const int _maxPendingBytes = 1920 * 4;

  final void Function(String keyword) onWakeWordDetected;
  final void Function(String tag, String msg)? onLog;

  MinaWakeWordService({
    required this.onWakeWordDetected,
    this.onLog,
  });

  bool get isInitialized => _initialized;
  bool get isEnabled => _enabled;

  Future<bool> init() async {
    if (_initialized) return true;
    try {
      final modelDir = await _copyAssetsToLocal();
      final rp = ReceivePort();
      _receivePort = rp;

      final initCompleter = Completer<bool>();

      rp.listen((dynamic message) {
        if (message is SendPort) {
          _workerSendPort = message;
          return;
        }
        if (message is Map) {
          final type = message['type'];
          if (type == 'init_ok') {
            _initialized = true;
            _enabled = true;
            if (!initCompleter.isCompleted) initCompleter.complete(true);
            onLog?.call(
              'KWS',
              'Sherpa-ONNX KWS (Background Isolate) đã sẵn sàng! Đánh thức: "Mina", "Chào Mina", "Mina ơi"',
            );
          } else if (type == 'init_err') {
            final err = message['error']?.toString() ?? 'Unknown error';
            onLog?.call('KWS', 'Lỗi khởi tạo Sherpa-ONNX KWS: $err');
            if (!initCompleter.isCompleted) initCompleter.complete(false);
          } else if (type == 'ack') {
            _workerBusy = false;
            final kw = (message['kw'] as String?)?.trim() ?? '';
            if (kw.isNotEmpty && _enabled) {
              final now = DateTime.now();
              if (now.difference(_lastDetectedAt).inMilliseconds > 1200) {
                _lastDetectedAt = now;
                onLog?.call('KWS', 'Phát hiện từ khóa đánh thức: $kw');
                onWakeWordDetected(kw);
              }
            }
            // Nếu có mẫu âm thanh mới chờ sẵn và đang bật thì gửi tiếp
            _flushPendingToWorker();
          }
        }
      });

      _isolate = await Isolate.spawn<_KwsIsolateInit>(
        _kwsIsolateMain,
        _KwsIsolateInit(
          mainSendPort: rp.sendPort,
          modelDir: modelDir,
        ),
        debugName: 'MinaKwsWorker',
      );

      return await initCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          onLog?.call('KWS', 'Quá thời gian khởi tạo Sherpa-ONNX Isolate');
          return false;
        },
      );
    } catch (e) {
      onLog?.call('KWS', 'Lỗi khởi tạo Sherpa-ONNX KWS: $e');
      return false;
    }
  }

  void setEnabled(bool value) {
    _enabled = value;
    _pendingPcm.clear();
    _silentFrames = 0;
    if (value) {
      _workerSendPort?.send(const {'cmd': 'reset'});
    }
  }

  /// Đưa khung PCM16 16kHz (1920 bytes = 960 mẫu) vào hàng đợi của Background Isolate
  void feedPcm16(Uint8List pcmBytes) {
    if (!_initialized || !_enabled || _workerSendPort == null) return;
    if (pcmBytes.isEmpty) return;

    // Kiểm tra nhanh biên độ âm thanh để bỏ qua khi phòng hoàn toàn im lặng > 1.5 giây
    final bd = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.length ~/ 2;
    int maxAbs = 0;
    for (int i = 0; i < sampleCount; i += 4) {
      final v = bd.getInt16(i * 2, Endian.little).abs();
      if (v > maxAbs) maxAbs = v;
    }

    if (maxAbs < 130) {
      _silentFrames++;
      if (_silentFrames > 25) {
        // Sau 1.5 giây im lặng liên tiếp, nghỉ giải mã để CPU về 0%
        return;
      }
    } else {
      _silentFrames = 0;
    }

    // Nếu bộ đệm chờ đã đầy (do CPU bận), chỉ giữ lại phần âm thanh mới nhất
    if (_pendingPcm.length + pcmBytes.length > _maxPendingBytes) {
      _pendingPcm.clear();
    }
    _pendingPcm.add(pcmBytes);

    if (!_workerBusy) {
      _flushPendingToWorker();
    }
  }

  void _flushPendingToWorker() {
    if (_workerBusy || !_enabled || _workerSendPort == null || _pendingPcm.isEmpty) {
      return;
    }
    final bytes = _pendingPcm.takeBytes();
    _workerBusy = true;
    _workerSendPort!.send(TransferableTypedData.fromList([bytes]));
  }

  Future<String> _copyAssetsToLocal() async {
    final docDir = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(docDir.path, 'mina_kws_v1'));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    const files = [
      'encoder.int8.onnx',
      'decoder.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
      'keywords.txt',
    ];

    for (final fileName in files) {
      final outFile = File(p.join(targetDir.path, fileName));
      if (!outFile.existsSync() || fileName == 'keywords.txt') {
        final data = await rootBundle.load('assets/models/kws/$fileName');
        await outFile.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
    return targetDir.path;
  }

  void dispose() {
    _enabled = false;
    _pendingPcm.clear();
    _workerSendPort?.send(const {'cmd': 'dispose'});
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort = null;
    _workerSendPort = null;
    _initialized = false;
  }
}

class _KwsIsolateInit {
  final SendPort mainSendPort;
  final String modelDir;

  const _KwsIsolateInit({
    required this.mainSendPort,
    required this.modelDir,
  });
}

void _kwsIsolateMain(_KwsIsolateInit initMsg) {
  final workerPort = ReceivePort();
  initMsg.mainSendPort.send(workerPort.sendPort);

  sherpa.KeywordSpotter? spotter;
  sherpa.OnlineStream? stream;

  try {
    sherpa.initBindings();
    final modelDir = initMsg.modelDir;

    final transducer = sherpa.OnlineTransducerModelConfig(
      encoder: p.join(modelDir, 'encoder.int8.onnx'),
      decoder: p.join(modelDir, 'decoder.onnx'),
      joiner: p.join(modelDir, 'joiner.int8.onnx'),
    );

    final modelConfig = sherpa.OnlineModelConfig(
      transducer: transducer,
      tokens: p.join(modelDir, 'tokens.txt'),
      // QUAN TRỌNG: numThreads = 1 để tránh OpenMP spin-wait chiếm trọn 4 nhân CPU trên MT8167
      numThreads: 1,
      provider: 'cpu',
      debug: false,
    );

    final kwsConfig = sherpa.KeywordSpotterConfig(
      feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: modelConfig,
      keywordsFile: p.join(modelDir, 'keywords.txt'),
      maxActivePaths: 4,
      numTrailingBlanks: 1,
      keywordsScore: 1.5,
      keywordsThreshold: 0.20,
    );

    spotter = sherpa.KeywordSpotter(kwsConfig);
    stream = spotter.createStream();
    initMsg.mainSendPort.send(const {'type': 'init_ok'});
  } catch (e) {
    initMsg.mainSendPort.send({'type': 'init_err', 'error': e.toString()});
    return;
  }

  workerPort.listen((dynamic msg) {
    if (spotter == null || stream == null) return;

    if (msg is Map) {
      final cmd = msg['cmd'];
      if (cmd == 'reset') {
        spotter!.reset(stream!);
      } else if (cmd == 'dispose') {
        stream?.free();
        spotter?.free();
        stream = null;
        spotter = null;
        workerPort.close();
      }
      return;
    }

    if (msg is TransferableTypedData) {
      String detectedKw = '';
      try {
        final pcmBytes = msg.materialize().asUint8List();
        final sampleCount = pcmBytes.length ~/ 2;
        if (sampleCount > 0) {
          final samples = Float32List(sampleCount);
          final bd = ByteData.sublistView(pcmBytes);
          for (int i = 0; i < sampleCount; i++) {
            samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
          }

          stream!.acceptWaveform(samples: samples, sampleRate: 16000);
          while (spotter!.isReady(stream!)) {
            spotter!.decode(stream!);
          }

          final result = spotter!.getResult(stream!);
          final kw = result.keyword.trim();
          if (kw.isNotEmpty) {
            spotter!.reset(stream!);
            detectedKw = kw;
          }
        }
      } catch (_) {}

      initMsg.mainSendPort.send({
        'type': 'ack',
        'kw': detectedKw,
      });
    }
  });
}
