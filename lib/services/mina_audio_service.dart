import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Quản lý luồng thu âm 16kHz PCM từ mảng Mic ZNJ và phát loa PCM độ trễ thấp qua MainActivity
class MinaAudioService {
  static const MethodChannel _audioChannel = MethodChannel('com.mtc.mina_robot/audio');
  static const EventChannel _micEventChannel = EventChannel('com.mtc.mina_robot/mic_stream');

  final StreamController<Uint8List> _pcmFrameController = StreamController<Uint8List>.broadcast();
  StreamSubscription<dynamic>? _nativeSub;
  bool _micRunning = false;

  /// Mỗi phần tử là 1 khung PCM 16-bit Mono 16kHz dài đúng 60ms (1920 bytes = 960 samples)
  Stream<Uint8List> get pcm16kFrames => _pcmFrameController.stream;

  Future<bool> startMic() async {
    if (_micRunning) return true;
    _nativeSub ??= _micEventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Uint8List) {
        _pcmFrameController.add(event);
      }
    });
    final ok = await _audioChannel.invokeMethod<bool>('startMic') ?? false;
    _micRunning = ok;
    return ok;
  }

  Future<void> stopMic() async {
    _micRunning = false;
    await _audioChannel.invokeMethod('stopMic');
  }

  Future<void> initPlayer(int sampleRate) async {
    await _audioChannel.invokeMethod('initPlayer', {'sampleRate': sampleRate});
  }

  Future<void> writePcm(Uint8List pcmBytes) async {
    await _audioChannel.invokeMethod('writePcm', {'pcm': pcmBytes});
  }

  Future<void> stopAndFlushPlayer() async {
    await _audioChannel.invokeMethod('stopPlayer');
  }

  Future<void> setVolume(int percent) async {
    await _audioChannel.invokeMethod('setVolume', {'percent': percent.clamp(0, 100)});
  }

  Future<int> getVolume() async {
    return await _audioChannel.invokeMethod<int>('getVolume') ?? 80;
  }

  Future<void> dispose() async {
    await stopMic();
    await stopAndFlushPlayer();
    await _nativeSub?.cancel();
    await _pcmFrameController.close();
  }
}
