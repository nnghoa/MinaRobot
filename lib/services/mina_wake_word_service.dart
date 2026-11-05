import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Engine TinyML nhận diện từ khóa đánh thức Offline ("Mina", "Chào Mina", "Hey Mina", "Mina ơi")
/// Chạy trực tiếp trên CPU ARMv7 Allwinner A33 bằng model Zipformer int8 siêu nhẹ.
class MinaWakeWordService {
  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  bool _enabled = false;
  bool _initialized = false;
  DateTime _lastDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);

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
      sherpa.initBindings();
      final modelDir = await _copyAssetsToLocal();

      final transducer = sherpa.OnlineTransducerModelConfig(
        encoder: p.join(modelDir, 'encoder.int8.onnx'),
        decoder: p.join(modelDir, 'decoder.onnx'),
        joiner: p.join(modelDir, 'joiner.int8.onnx'),
      );

      final modelConfig = sherpa.OnlineModelConfig(
        transducer: transducer,
        tokens: p.join(modelDir, 'tokens.txt'),
        numThreads: 2, // Tối ưu cho Quad-Core Allwinner A33 (dành 2 nhân cho UI & Audio)
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

      _spotter = sherpa.KeywordSpotter(kwsConfig);
      _stream = _spotter!.createStream();
      _initialized = true;
      _enabled = true;
      onLog?.call('KWS', 'Sherpa-ONNX KWS đã sẵn sàng! Đánh thức: "Mina", "Chào Mina", "Mina ơi"');
      return true;
    } catch (e) {
      onLog?.call('KWS', 'Lỗi khởi tạo Sherpa-ONNX KWS: $e');
      return false;
    }
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (value && _spotter != null && _stream != null) {
      _spotter!.reset(_stream!);
    }
  }

  /// Đưa khung PCM16 16kHz (1920 bytes = 960 mẫu) vào bộ nhận diện Wake-word
  void feedPcm16(Uint8List pcmBytes) {
    if (!_initialized || !_enabled || _spotter == null || _stream == null) return;

    final sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) return;

    final samples = Float32List(sampleCount);
    final bd = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }

    _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
    while (_spotter!.isReady(_stream!)) {
      _spotter!.decode(_stream!);
    }

    final result = _spotter!.getResult(_stream!);
    final kw = result.keyword.trim();
    if (kw.isNotEmpty) {
      _spotter!.reset(_stream!);
      final now = DateTime.now();
      if (now.difference(_lastDetectedAt).inMilliseconds > 1200) {
        _lastDetectedAt = now;
        onLog?.call('KWS', 'Phát hiện từ khóa đánh thức: $kw');
        onWakeWordDetected(kw);
      }
    }
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
      // Luôn cập nhật keywords.txt để dễ tinh chỉnh từ khóa, các file model lớn chỉ chép 1 lần
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
    _stream?.free();
    _spotter?.free();
    _stream = null;
    _spotter = null;
    _initialized = false;
  }
}
