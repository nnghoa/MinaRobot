import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// C signatures chuẩn của libopus.so
typedef _OpusEncoderCreateC = ffi.Pointer<ffi.Void> Function(
  ffi.Int32 fs,
  ffi.Int32 channels,
  ffi.Int32 application,
  ffi.Pointer<ffi.Int32> error,
);
typedef _OpusEncoderCreateDart = ffi.Pointer<ffi.Void> Function(
  int fs,
  int channels,
  int application,
  ffi.Pointer<ffi.Int32> error,
);

typedef _OpusEncodeC = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> st,
  ffi.Pointer<ffi.Int16> pcm,
  ffi.Int32 frameSize,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Int32 maxDataBytes,
);
typedef _OpusEncodeDart = int Function(
  ffi.Pointer<ffi.Void> st,
  ffi.Pointer<ffi.Int16> pcm,
  int frameSize,
  ffi.Pointer<ffi.Uint8> data,
  int maxDataBytes,
);

typedef _OpusEncoderDestroyC = ffi.Void Function(ffi.Pointer<ffi.Void> st);
typedef _OpusEncoderDestroyDart = void Function(ffi.Pointer<ffi.Void> st);

typedef _OpusDecoderCreateC = ffi.Pointer<ffi.Void> Function(
  ffi.Int32 fs,
  ffi.Int32 channels,
  ffi.Pointer<ffi.Int32> error,
);
typedef _OpusDecoderCreateDart = ffi.Pointer<ffi.Void> Function(
  int fs,
  int channels,
  ffi.Pointer<ffi.Int32> error,
);

typedef _OpusDecodeC = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> st,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Int32 len,
  ffi.Pointer<ffi.Int16> pcm,
  ffi.Int32 frameSize,
  ffi.Int32 decodeFec,
);
typedef _OpusDecodeDart = int Function(
  ffi.Pointer<ffi.Void> st,
  ffi.Pointer<ffi.Uint8> data,
  int len,
  ffi.Pointer<ffi.Int16> pcm,
  int frameSize,
  int decodeFec,
);

typedef _OpusDecoderDestroyC = ffi.Void Function(ffi.Pointer<ffi.Void> st);
typedef _OpusDecoderDestroyDart = void Function(ffi.Pointer<ffi.Void> st);

/// FFI trực tiếp tới `libopus.so` (không qua MP3, độ trễ < 20ms theo đúng quy chuẩn XiaoZhi)
class MinaOpusCodec {
  static const int opusApplicationVoip = 2048;

  ffi.DynamicLibrary? _lib;
  late final _OpusEncoderCreateDart _encoderCreate;
  late final _OpusEncodeDart _encode;
  late final _OpusEncoderDestroyDart _encoderDestroy;
  late final _OpusDecoderCreateDart _decoderCreate;
  late final _OpusDecodeDart _decode;
  late final _OpusDecoderDestroyDart _decoderDestroy;

  ffi.Pointer<ffi.Void> _encoder = ffi.nullptr;
  ffi.Pointer<ffi.Void> _decoder = ffi.nullptr;
  int _decoderSampleRate = 24000;

  // Bộ đệm tái sử dụng để tránh cấp phát bộ nhớ liên tục trên chip A33
  final ffi.Pointer<ffi.Int16> _encPcmBuf = calloc<ffi.Int16>(960); // 60ms @ 16kHz
  final ffi.Pointer<ffi.Uint8> _encOutBuf = calloc<ffi.Uint8>(4000);
  final ffi.Pointer<ffi.Uint8> _decInBuf = calloc<ffi.Uint8>(4000);
  final ffi.Pointer<ffi.Int16> _decOutPcmBuf = calloc<ffi.Int16>(5760); // Tối đa 120ms @ 48kHz

  bool get isReady => _lib != null;

  bool init({int encodeSampleRate = 16000, int decodeSampleRate = 24000}) {
    if (_lib == null) {
      try {
        if (Platform.isAndroid || Platform.isLinux) {
          _lib = ffi.DynamicLibrary.open('libopus.so');
        } else {
          return false;
        }
        _encoderCreate = _lib!.lookupFunction<_OpusEncoderCreateC, _OpusEncoderCreateDart>('opus_encoder_create');
        _encode = _lib!.lookupFunction<_OpusEncodeC, _OpusEncodeDart>('opus_encode');
        _encoderDestroy = _lib!.lookupFunction<_OpusEncoderDestroyC, _OpusEncoderDestroyDart>('opus_encoder_destroy');
        _decoderCreate = _lib!.lookupFunction<_OpusDecoderCreateC, _OpusDecoderCreateDart>('opus_decoder_create');
        _decode = _lib!.lookupFunction<_OpusDecodeC, _OpusDecodeDart>('opus_decode');
        _decoderDestroy = _lib!.lookupFunction<_OpusDecoderDestroyC, _OpusDecoderDestroyDart>('opus_decoder_destroy');
      } catch (_) {
        _lib = null;
        return false;
      }
    }

    initEncoder(encodeSampleRate);
    initDecoder(decodeSampleRate);
    return _encoder != ffi.nullptr && _decoder != ffi.nullptr;
  }

  void initEncoder(int sampleRate) {
    if (_lib == null) return;
    if (_encoder != ffi.nullptr) {
      _encoderDestroy(_encoder);
      _encoder = ffi.nullptr;
    }
    final err = calloc<ffi.Int32>(1);
    try {
      _encoder = _encoderCreate(sampleRate, 1, opusApplicationVoip, err);
    } finally {
      calloc.free(err);
    }
  }

  void initDecoder(int sampleRate) {
    if (_lib == null) return;
    if (_decoder != ffi.nullptr && _decoderSampleRate == sampleRate) return;
    if (_decoder != ffi.nullptr) {
      _decoderDestroy(_decoder);
      _decoder = ffi.nullptr;
    }
    _decoderSampleRate = sampleRate;
    final err = calloc<ffi.Int32>(1);
    try {
      _decoder = _decoderCreate(sampleRate, 1, err);
    } finally {
      calloc.free(err);
    }
  }

  /// Mã hóa 1 khung PCM16 16kHz 60ms (1920 bytes = 960 mẫu) sang gói Opus
  Uint8List? encodePcm16Frame(Uint8List pcmBytes) {
    if (_encoder == ffi.nullptr || pcmBytes.length < 1920) return null;
    final bd = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < 960; i++) {
      _encPcmBuf[i] = bd.getInt16(i * 2, Endian.little);
    }
    final encodedBytes = _encode(_encoder, _encPcmBuf, 960, _encOutBuf, 4000);
    if (encodedBytes <= 0) return null;
    return Uint8List.fromList(_encOutBuf.asTypedList(encodedBytes));
  }

  /// Giải mã 1 gói Opus từ server XiaoZhi ra mảng byte PCM 16-bit Little Endian để phát loa
  Uint8List? decodeOpusPacket(Uint8List opusPacket) {
    if (_decoder == ffi.nullptr || opusPacket.isEmpty || opusPacket.length > 4000) return null;
    _decInBuf.asTypedList(opusPacket.length).setAll(0, opusPacket);
    // frame_size tối đa cho 120ms ở tần số lấy mẫu hiện tại
    final maxSamples = (_decoderSampleRate * 120) ~/ 1000;
    final decodedSamples = _decode(
      _decoder,
      _decInBuf,
      opusPacket.length,
      _decOutPcmBuf,
      maxSamples,
      0,
    );
    if (decodedSamples <= 0) return null;

    final outBytes = Uint8List(decodedSamples * 2);
    final bd = ByteData.sublistView(outBytes);
    for (int i = 0; i < decodedSamples; i++) {
      bd.setInt16(i * 2, _decOutPcmBuf[i], Endian.little);
    }
    return outBytes;
  }

  void dispose() {
    if (_encoder != ffi.nullptr && _lib != null) {
      _encoderDestroy(_encoder);
      _encoder = ffi.nullptr;
    }
    if (_decoder != ffi.nullptr && _lib != null) {
      _decoderDestroy(_decoder);
      _decoder = ffi.nullptr;
    }
    calloc.free(_encPcmBuf);
    calloc.free(_encOutBuf);
    calloc.free(_decInBuf);
    calloc.free(_decOutPcmBuf);
  }
}
