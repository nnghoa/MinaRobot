import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mina_state.dart';
import 'robonova_actions.dart';

// POSIX libc bindings trên Android Linux (tương thích cả armeabi-v7a 32-bit Allwinner A33 và arm64-v8a)
typedef _OpenNative = ffi.Int32 Function(ffi.Pointer<Utf8> path, ffi.Int32 flags);
typedef _OpenDart = int Function(ffi.Pointer<Utf8> path, int flags);

typedef _CloseNative = ffi.Int32 Function(ffi.Int32 fd);
typedef _CloseDart = int Function(int fd);

typedef _WriteNative = ffi.IntPtr Function(ffi.Int32 fd, ffi.Pointer<ffi.Uint8> buf, ffi.IntPtr count);
typedef _WriteDart = int Function(int fd, ffi.Pointer<ffi.Uint8> buf, int count);

typedef _ReadNative = ffi.IntPtr Function(ffi.Int32 fd, ffi.Pointer<ffi.Uint8> buf, ffi.IntPtr count);
typedef _ReadDart = int Function(int fd, ffi.Pointer<ffi.Uint8> buf, int count);

typedef _TcgetattrNative = ffi.Int32 Function(ffi.Int32 fd, ffi.Pointer<ffi.Uint8> termiosPtr);
typedef _TcgetattrDart = int Function(int fd, ffi.Pointer<ffi.Uint8> termiosPtr);

typedef _CfmakerawNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> termiosPtr);
typedef _CfmakerawDart = void Function(ffi.Pointer<ffi.Uint8> termiosPtr);

typedef _CfsetspeedNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8> termiosPtr, ffi.Uint32 speed);
typedef _CfsetspeedDart = int Function(ffi.Pointer<ffi.Uint8> termiosPtr, int speed);

typedef _TcsetattrNative = ffi.Int32 Function(
  ffi.Int32 fd,
  ffi.Int32 optionalActions,
  ffi.Pointer<ffi.Uint8> termiosPtr,
);
typedef _TcsetattrDart = int Function(int fd, int optionalActions, ffi.Pointer<ffi.Uint8> termiosPtr);

/// Driver giao tiếp song công 2 chiều (Full-Duplex UART 9600 8N1) với mạch MR-C3024FX (Robonova-II):
/// - Chiều TX (Android TX -> MR-C3024FX ERX): gửi mã lệnh động tác (40..108) & lệnh cảm biến ('s'=115, 'm'=109, 'n'=110)
/// - Chiều RX (MR-C3024FX ETX -> Android RX): nhận khung nhị phân 8 byte [0xAA, 0x55, SonarHi, SonarLo, Dist10k, Batt, Tilt, Chk]
class RobonovaSerialDriver {
  static const MethodChannel _hwChannel = MethodChannel('com.mtc.mina_robot/hardware');
  static const MethodChannel _usbChannel = MethodChannel('com.mtc.mina_robot/usb_serial');
  static const EventChannel _usbEvents = EventChannel('com.mtc.mina_robot/usb_serial_events');
  static const String _prefPortKey = 'mina_uart_port';
  static const String _prefBaudKey = 'mina_uart_baud';

  /// Tên cổng đặc biệt: dùng mạch USB-UART (CP2102 / CH340...) cắm qua cáp OTG của điện thoại
  static const String usbPortName = 'usb';

  // Mã lệnh mở rộng gửi xuống ERX 9600 trên mạch Robonova-II
  static const int cmdRequestSensors = 115; // 's'
  static const int cmdEnableHwReflex = 109; // 'm'
  static const int cmdDisableHwReflex = 110; // 'n'

  // Cờ POSIX cho Linux ARM
  static const int _oRdwr = 0x0002;
  static const int _oNoctty = 0x0100;
  static const int _oNonblock = 0x0800;
  static const int _tcsaNow = 0;

  late final _OpenDart _open;
  late final _CloseDart _close;
  late final _WriteDart _write;
  late final _ReadDart _read;
  late final _TcgetattrDart _tcgetattr;
  late final _CfmakerawDart _cfmakeraw;
  late final _CfsetspeedDart _cfsetispeed;
  late final _CfsetspeedDart _cfsetospeed;
  late final _TcsetattrDart _tcsetattr;

  bool _ffiReady = false;
  bool _termiosFfiReady = false;
  int _fd = -1;
  String _portPath = '/dev/ttyS1';
  int _baudrate = 9600; // MR-C3024FX chạy lệnh `ERX 9600` & `ETX 9600` ở tốc độ chuẩn 9600 baud!

  // Chế độ USB OTG (điện thoại Android + mạch CP2102/CH340)
  bool _usbMode = false;
  bool _usbOpen = false;
  String _usbStatus = '';
  StreamSubscription<dynamic>? _usbSub;

  final List<int> _rxBuf = <int>[];
  Timer? _rxPollTimer;
  Timer? _sensorRequestTimer;
  DateTime _busyUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTxAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _desiredHwReflex = true;
  RobonovaSensorState _sensorState = const RobonovaSensorState();

  final void Function(String tag, String msg)? onLog;
  void Function(RobonovaSensorState state)? onSensorUpdated;

  RobonovaSerialDriver({
    this.onLog,
    this.onSensorUpdated,
  }) {
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        final libc = ffi.DynamicLibrary.process();
        // open/close/read/write luôn có mặt trên mọi phiên bản Android Bionic (kể cả Android 4.4 Allwinner A33)
        _open = libc.lookupFunction<_OpenNative, _OpenDart>('open');
        _close = libc.lookupFunction<_CloseNative, _CloseDart>('close');
        _write = libc.lookupFunction<_WriteNative, _WriteDart>('write');
        _read = libc.lookupFunction<_ReadNative, _ReadDart>('read');
        _ffiReady = true;

        // termios C symbols có sẵn từ Android 5.0+ (API 21+); trên Android 4.4 đã có stty hỗ trợ ở tầng Kotlin
        try {
          _tcgetattr = libc.lookupFunction<_TcgetattrNative, _TcgetattrDart>('tcgetattr');
          _cfmakeraw = libc.lookupFunction<_CfmakerawNative, _CfmakerawDart>('cfmakeraw');
          _cfsetispeed = libc.lookupFunction<_CfsetspeedNative, _CfsetspeedDart>('cfsetispeed');
          _cfsetospeed = libc.lookupFunction<_CfsetspeedNative, _CfsetspeedDart>('cfsetospeed');
          _tcsetattr = libc.lookupFunction<_TcsetattrNative, _TcsetattrDart>('tcsetattr');
          _termiosFfiReady = true;
        } catch (_) {
          _termiosFfiReady = false;
        }
      } catch (e) {
        onLog?.call('UART', 'Không tải được POSIX I/O FFI: $e');
      }
    }
  }

  String get portPath => _portPath;
  int get baudrate => _baudrate;
  bool get isConnected => _fd >= 0 || (_usbMode && _usbOpen);
  bool get isUsbMode => _usbMode;

  /// Thông báo trạng thái gần nhất của cổng USB OTG (để hiển thị cho người dùng)
  String get usbStatus => _usbStatus;
  RobonovaSensorState get sensorState => _sensorState;

  void updateThresholds({
    int? sonarThresholdCm,
    int? dist10kThreshold,
  }) {
    // Chỉ cập nhật ngưỡng, KHÔNG phát onSensorUpdated (tránh kích hoạt phản xạ giả khi chưa có gói dữ liệu mới)
    _sensorState = _sensorState.copyWith(
      sonarObstacleThresholdCm: sonarThresholdCm,
      dist10kObstacleThreshold: dist10kThreshold,
    );
  }

  Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Điện thoại Android thường không có /dev/ttyS1 -> mặc định dùng USB OTG (CP2102/CH340)
    final defaultPort = File('/dev/ttyS1').existsSync() ? '/dev/ttyS1' : usbPortName;
    _portPath = prefs.getString(_prefPortKey) ?? defaultPort;
    _baudrate = prefs.getInt(_prefBaudKey) ?? 9600;
    await openPort(_portPath, _baudrate);
  }

  Future<List<String>> listAvailablePorts() async {
    final ports = <String>[usbPortName];
    try {
      final res = await _hwChannel.invokeListMethod<String>('listSerialPorts');
      if (res != null && res.isNotEmpty) return [...ports, ...res];
    } catch (_) {}
    return [...ports, '/dev/ttyS1', '/dev/ttyS0', '/dev/ttyS2', '/dev/ttyS3', '/dev/ttyUSB0'];
  }

  /// Danh sách mạch USB-serial đang cắm qua OTG (ví dụ "Cp21xx (10C4:EA60)")
  Future<List<String>> listUsbDevices() async {
    try {
      return await _usbChannel.invokeListMethod<String>('list') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  void _ensureUsbEvents() {
    _usbSub ??= _usbEvents.receiveBroadcastStream().listen((dynamic evt) {
      if (evt is! Map) return;
      final type = evt['type'];
      if (type == 'data') {
        final bytes = evt['bytes'];
        if (bytes is Uint8List) {
          _consumeRxBytes(bytes.map((b) => b & 0xFF).toList());
        }
      } else if (type == 'status') {
        final wasOpen = _usbOpen;
        _usbOpen = evt['open'] == true;
        _usbStatus = evt['message']?.toString() ?? '';
        onLog?.call('USB', _usbStatus);
        // Cắm lại cáp OTG -> tự đồng bộ lại chế độ phản xạ và lấy cảm biến
        if (_usbMode && _usbOpen && !wasOpen) {
          _startTelemetryLoops();
          _writeSingleByte(_desiredHwReflex ? cmdEnableHwReflex : cmdDisableHwReflex);
          _lastTxAt = DateTime.now();
        }
      }
    }, onError: (_) {});
  }

  Future<bool> _openUsb(int baudrate) async {
    _usbMode = true;
    _ensureUsbEvents();
    bool ok = false;
    try {
      ok = await _usbChannel.invokeMethod<bool>('open', {'baudrate': baudrate}) ?? false;
    } catch (e) {
      onLog?.call('USB', 'Lỗi mở USB-serial: $e');
    }
    _usbOpen = ok;
    _rxBuf.clear();
    _startTelemetryLoops();
    if (ok) {
      onLog?.call('UART', 'Đã kết nối USB OTG @ $baudrate baud (CP2102/CH340 -> MR-C3024FX)');
      _writeSingleByte(_desiredHwReflex ? cmdEnableHwReflex : cmdDisableHwReflex);
      _lastTxAt = DateTime.now();
    } else {
      onLog?.call('UART', 'Chưa mở được USB OTG. Cắm mạch CP2102 qua cáp OTG rồi bấm Cho phép.');
    }
    return ok;
  }

  Future<bool> openPort(String path, int baudrate) async {
    closePort();
    _portPath = path;
    _baudrate = baudrate;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPortKey, path);
    await prefs.setInt(_prefBaudKey, baudrate);

    if (path == usbPortName) {
      return _openUsb(baudrate);
    }
    _usbMode = false;

    if (!_ffiReady) return false;

    // Yêu cầu tầng Android cấp quyền chmod 666 & stty nếu chạy trên board Allwinner root
    try {
      await _hwChannel.invokeMethod('prepareSerialPort', {
        'path': path,
        'baudrate': baudrate,
      });
    } catch (_) {}

    final cPath = path.toNativeUtf8();
    final termiosBuf = calloc<ffi.Uint8>(128);
    try {
      final fd = _open(cPath, _oRdwr | _oNoctty | _oNonblock);
      if (fd < 0) {
        onLog?.call('UART', 'Mở $path thất bại (chế độ mô phỏng / chưa cắm mạch).');
        return false;
      }

      if (_termiosFfiReady) {
        final speedConst = _baudToLinuxConstant(baudrate);
        if (_tcgetattr(fd, termiosBuf) == 0) {
          _cfmakeraw(termiosBuf);
          _cfsetispeed(termiosBuf, speedConst);
          _cfsetospeed(termiosBuf, speedConst);
          _tcsetattr(fd, _tcsaNow, termiosBuf);
        }
      }

      _fd = fd;
      _rxBuf.clear();
      _startTelemetryLoops();
      onLog?.call('UART', 'Đã kết nối song công 2 chiều $path @ $baudrate baud (fd=$_fd)');
      // Đồng bộ lại trạng thái phản xạ (MR-C3024FX mặc định RFX_ON = 1 sau mỗi lần reset),
      // lệnh 'm'/'n' cũng khiến mạch gửi luôn bản tin cảm biến đầu tiên.
      _writeSingleByte(_desiredHwReflex ? cmdEnableHwReflex : cmdDisableHwReflex);
      _lastTxAt = DateTime.now();
      return true;
    } finally {
      calloc.free(cPath);
      calloc.free(termiosBuf);
    }
  }

  void _startTelemetryLoops() {
    _rxPollTimer?.cancel();
    _sensorRequestTimer?.cancel();

    // Đọc non-blocking đường RX (nối từ chân ETX của MR-C3024FX) mỗi 80ms
    _rxPollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _pollRxOnce();
    });

    // Định kỳ hỏi cảm biến ('s' = 115) mỗi 1200ms khi robot đang rảnh (không bận múa/đi)
    _sensorRequestTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (isConnected && DateTime.now().isAfter(_busyUntil)) {
        _writeSingleByte(cmdRequestSensors);
        _lastTxAt = DateTime.now();
      }
    });
  }

  /// Đọc tức thì toàn bộ dữ liệu đang chờ trên bộ đệm RX UART (nối từ ETX 9600 của Robonova-II)
  void _pollRxOnce() {
    if (_fd < 0 || !_ffiReady) return;
    final buf = calloc<ffi.Uint8>(64);
    try {
      while (true) {
        final n = _read(_fd, buf, 64);
        if (n <= 0) break;
        final chunk = <int>[];
        for (int i = 0; i < n; i++) {
          chunk.add(buf[i] & 0xFF);
        }
        _consumeRxBytes(chunk);
      }
    } catch (_) {
      // Non-blocking EAGAIN / EWOULDBLOCK bỏ qua bình thường
    } finally {
      calloc.free(buf);
    }
  }

  /// Giải mã gói nhị phân 8 byte từ MR-C3024FX:
  /// [0xAA, 0x55, SONAR_HI, SONAR_LO, DIST_10K, BATT_RAW, TILT_RAW, CHK_BYTE]
  void _consumeRxBytes(List<int> incoming) {
    _rxBuf.addAll(incoming);
    if (_rxBuf.length > 256) {
      _rxBuf.removeRange(0, _rxBuf.length - 128);
    }

    while (_rxBuf.length >= 8) {
      // Tìm 2 byte đồng bộ đầu khung 0xAA (170), 0x55 (85)
      if (_rxBuf[0] != 0xAA) {
        _rxBuf.removeAt(0);
        continue;
      }
      if (_rxBuf[1] != 0x55) {
        _rxBuf.removeAt(0);
        continue;
      }

      final sonarHi = _rxBuf[2];
      final sonarLo = _rxBuf[3];
      final dist10k = _rxBuf[4];
      final battRaw = _rxBuf[5];
      final tiltRaw = _rxBuf[6];
      final chkByte = _rxBuf[7];

      final expectedChk = (sonarHi + sonarLo + dist10k + battRaw + tiltRaw) & 0xFF;
      if (expectedChk != chkByte) {
        // Lệch khung hoặc nhiễu đường truyền -> dịch 2 byte tìm khung kế tiếp
        _rxBuf.removeRange(0, 2);
        continue;
      }

      // Khung hợp lệ -> tiêu thụ 8 byte và cập nhật trạng thái cảm biến
      _rxBuf.removeRange(0, 8);
      final sonarRaw = (sonarHi << 8) | sonarLo;

      _sensorState = _sensorState.copyWith(
        sonarRaw: sonarRaw,
        dist10kRaw: dist10k,
        batteryRaw: battRaw,
        tiltRaw: tiltRaw,
        updatedAt: DateTime.now(),
      );
      onSensorUpdated?.call(_sensorState);
    }
  }

  /// Chủ động gửi lệnh 's' (115) xuống ERX để lấy mẫu cảm biến mới nhất ngay lập tức
  Future<RobonovaSensorState> requestSensorSnapshot({
    Duration waitTimeout = const Duration(milliseconds: 180),
  }) async {
    // Khi robot đang bận thực hiện động tác, MR-C3024FX không đọc ERX -> trả về số liệu gần nhất
    if (isConnected && DateTime.now().isAfter(_busyUntil)) {
      _writeSingleByte(cmdRequestSensors);
      _lastTxAt = DateTime.now();
      final deadline = DateTime.now().add(waitTimeout);
      final prevTime = _sensorState.updatedAt;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 35));
        _pollRxOnce();
        if (_sensorState.updatedAt != prevTime) {
          break;
        }
      }
    }
    return _sensorState;
  }

  /// Bật/tắt chế độ phản xạ phần cứng trực tiếp trên mạch MR-C3024FX ('m'=109 bật, 'n'=110 tắt)
  bool setHardwareAutoReflex(bool enabled) {
    _desiredHwReflex = enabled;
    final byteCmd = enabled ? cmdEnableHwReflex : cmdDisableHwReflex;
    final ok = _writeSingleByte(byteCmd);
    _lastTxAt = DateTime.now();
    onLog?.call(
      'SENSOR',
      'Cấu hình phản xạ phần cứng trên MR-C3024FX: ${enabled ? "BẬT ('m')" : "TẮT ('n')"} '
      '${ok ? "[UART OK]" : "[Sim]"}',
    );
    return ok;
  }

  /// Bơm gói tin cảm biến giả lập chuẩn 8-byte để kiểm thử phản xạ của Mina khi chưa cắm phần cứng
  void injectSimulatedSensorPacket({
    required int sonarCm,
    required int dist10kRaw,
    int batteryRaw = 162,
    int tiltRaw = 128,
  }) {
    final hi = (sonarCm >> 8) & 0xFF;
    final lo = sonarCm & 0xFF;
    final d10k = dist10kRaw & 0xFF;
    final batt = batteryRaw & 0xFF;
    final tilt = tiltRaw & 0xFF;
    final chk = (hi + lo + d10k + batt + tilt) & 0xFF;
    _consumeRxBytes([0xAA, 0x55, hi, lo, d10k, batt, tilt, chk]);
    onLog?.call(
      'SENSOR',
      'Mô phỏng gói ETX 8-byte: Siêu âm=${sonarCm}cm, 10k=$d10k, Pin=${(batt * 10 / 256).toStringAsFixed(2)}V, Tilt=$tilt',
    );
  }

  /// Thực thi 1 hành động Robonova-II bằng cách truyền 1 byte ASCII xuống chân ERX của MR-C3024FX
  Future<bool> executeAction(RobonovaAction action, {int repeat = 1}) async {
    final safeRepeat = repeat.clamp(1, 5);
    bool ok = false;

    for (int i = 0; i < safeRepeat; i++) {
      // MR-C3024FX mất ~9ms để phát 8 byte ETX sau lệnh 's'/'m'/'n' -> chờ cho mạch quay lại vòng ERX
      final sinceTx = DateTime.now().difference(_lastTxAt).inMilliseconds;
      if (sinceTx >= 0 && sinceTx < 40) {
        await Future<void>.delayed(Duration(milliseconds: 40 - sinceTx));
      }
      _busyUntil = DateTime.now().add(Duration(milliseconds: action.estimatedMs + 150));
      ok = _writeSingleByte(action.asciiByte);
      onLog?.call(
        'ROBOT',
        'Thực thi [${action.id}] ${action.nameVi} -> ASCII ${action.asciiByte} (\'${action.asciiChar}\') '
        '${ok ? "[UART OK]" : "[Broadcast/Sim]"}',
      );

      // Đồng thời phát Broadcast Intent chuẩn tương thích nếu hệ thống có daemon ngoài
      _emitLegacyBroadcast(action);

      if (i < safeRepeat - 1) {
        await Future<void>.delayed(Duration(milliseconds: action.estimatedMs));
      }
    }
    return ok;
  }

  bool _writeSingleByte(int byteVal) {
    if (_usbMode) {
      if (!_usbOpen) return false;
      // Kênh MethodChannel giữ đúng thứ tự gửi; ghi 1 byte ở 9600 baud mất ~1ms
      _usbChannel.invokeMethod<bool>('write', {
        'bytes': Uint8List.fromList([byteVal & 0xFF]),
      }).catchError((Object e) {
        onLog?.call('USB', 'Lỗi ghi byte $byteVal: $e');
        return false;
      });
      return true;
    }
    if (_fd < 0 || !_ffiReady) return false;
    final ptr = calloc<ffi.Uint8>(1);
    try {
      ptr.value = byteVal & 0xFF;
      final written = _write(_fd, ptr, 1);
      return written == 1;
    } catch (e) {
      onLog?.call('UART', 'Lỗi ghi byte $byteVal: $e');
      return false;
    } finally {
      calloc.free(ptr);
    }
  }

  void _emitLegacyBroadcast(RobonovaAction action) {
    String? broadcastAction;
    switch (action.slug) {
      case 'walk_forward':
      case 'fast_walk':
      case 'fast_run':
        broadcastAction = 'com.robot.action.FORWARD';
        break;
      case 'walk_backward':
        broadcastAction = 'com.robot.action.BACKWARD';
        break;
      case 'turn_left':
      case 'shift_left':
        broadcastAction = 'com.robot.action.LEFT';
        break;
      case 'turn_right':
      case 'shift_right':
        broadcastAction = 'com.robot.action.RIGHT';
        break;
      case 'sit_down':
      case 'toggle_motor_sit':
        broadcastAction = 'com.robot.action.STOP';
        break;
    }
    if (broadcastAction != null) {
      _hwChannel.invokeMethod('sendRobotBroadcast', {
        'action': broadcastAction,
        'code': action.id,
      }).catchError((_) {});
    }
  }

  void closePort() {
    _rxPollTimer?.cancel();
    _rxPollTimer = null;
    _sensorRequestTimer?.cancel();
    _sensorRequestTimer = null;
    _rxBuf.clear();
    if (_usbMode && _usbOpen) {
      _usbChannel.invokeMethod('close').catchError((_) => null);
    }
    _usbOpen = false;
    if (_fd >= 0 && _ffiReady) {
      _close(_fd);
      _fd = -1;
    }
  }

  static int _baudToLinuxConstant(int baud) {
    switch (baud) {
      case 4800:
        return 0x000C; // B4800
      case 9600:
        return 0x000D; // B9600 (Mặc định của MR-C3024FX)
      case 19200:
        return 0x000E; // B19200
      case 38400:
        return 0x000F; // B38400
      case 57600:
        return 0x1001; // B57600
      case 115200:
        return 0x1002; // B115200
      default:
        return 0x000D;
    }
  }
}
