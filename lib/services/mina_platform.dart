import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Một kênh radio phát trực tiếp (HLS). Các link đã kiểm tra hoạt động ngày 09/11/2026.
class RadioStation {
  final String id;
  final String name;
  final String url;

  const RadioStation(this.id, this.name, this.url);
}

class RadioCatalog {
  static const List<RadioStation> all = [
    RadioStation('vov1', 'VOV1 - Thời sự',
        'https://str.vov.gov.vn/vovlive/vov1vov5Vietnamese.sdp_aac/playlist.m3u8'),
    RadioStation('vov2', 'VOV2 - Văn hóa, Xã hội',
        'https://str.vov.gov.vn/vovlive/vov2.sdp_aac/playlist.m3u8'),
    RadioStation('vov3', 'VOV3 - Âm nhạc',
        'https://str.vov.gov.vn/vovlive/vov3.sdp_aac/playlist.m3u8'),
    RadioStation('vovgt_hn', 'VOV Giao thông Hà Nội',
        'https://play.vovgiaothong.vn/live/gthn/playlist.m3u8'),
    RadioStation('vovgt_hcm', 'VOV Giao thông TP.HCM',
        'https://play.vovgiaothong.vn/live/gthcm/playlist.m3u8'),
  ];

  static RadioStation? byId(String? id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Cầu nối tới phần Android gốc (MainActivity.kt): phát media, trình duyệt chặn quảng cáo,
/// chụp ảnh camera, mở cài đặt hệ thống.
class MinaPlatform {
  static const MethodChannel _ch = MethodChannel('com.mtc.mina_robot/platform');

  // ---------- Media (radio / nhạc qua URL) ----------
  static Future<bool> mediaPlay(String url, {String title = ''}) async =>
      await _ch.invokeMethod<bool>('mediaPlay', {'url': url, 'title': title}) ?? false;

  static Future<void> mediaPause() => _ch.invokeMethod('mediaPause');

  static Future<void> mediaResume() => _ch.invokeMethod('mediaResume');

  static Future<void> mediaStop() => _ch.invokeMethod('mediaStop');

  /// Giảm / khôi phục âm lượng media khi Mina đang nói chuyện (0.0 - 1.0)
  static Future<void> mediaSetDuck(double volume) =>
      _ch.invokeMethod('mediaSetVolume', {'volume': volume});

  /// Trả về {playing: bool, title: String, url: String}
  static Future<Map<String, dynamic>> mediaState() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('mediaState');
    return (m ?? const {}).cast<String, dynamic>();
  }

  // ---------- Trình duyệt chặn quảng cáo ----------
  static Future<void> openBrowser(String url) => _ch.invokeMethod('openBrowser', {'url': url});

  static Future<void> closeBrowser() => _ch.invokeMethod('closeBrowser');

  // ---------- Camera ----------
  /// Chụp một ảnh JPEG từ camera trước. Trả về null nếu không chụp được.
  static Future<Uint8List?> takePhoto() async {
    try {
      return await _ch.invokeMethod<Uint8List>('takePhoto');
    } on PlatformException {
      return null;
    }
  }

  // ---------- Hệ thống ----------
  static Future<void> openWifiSettings() => _ch.invokeMethod('openWifiSettings');

  static Future<void> openSystemSettings() => _ch.invokeMethod('openSystemSettings');

  /// Mở màn hình chọn ứng dụng Launcher mặc định của Android
  static Future<void> openHomeSettings() => _ch.invokeMethod('openHomeSettings');

  static Future<bool> isDefaultLauncher() async =>
      await _ch.invokeMethod<bool>('isDefaultLauncher') ?? false;

  // ---------- Điều khiển động cơ bánh xe & servo cổ UBTECH Visbot ----------
  static Future<Map<String, dynamic>> robotStatus() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('robotStatus');
    return (m ?? const {}).cast<String, dynamic>();
  }

  static Future<String> robotMove(
    String direction, {
    int durationMs = 1500,
    double? speed,
  }) async {
    return await _ch.invokeMethod<String>('robotMove', {
          'direction': direction,
          'durationMs': durationMs,
          if (speed != null) 'speed': speed,
        }) ??
        '';
  }

  static Future<String> robotHead(
    String action, {
    double? angle,
    double? speed,
  }) async {
    return await _ch.invokeMethod<String>('robotHead', {
          'action': action,
          if (angle != null) 'angle': angle,
          if (speed != null) 'speed': speed,
        }) ??
        '';
  }

  static Future<String> robotStop() async =>
      await _ch.invokeMethod<String>('robotStop') ?? '';

  static Future<String> robotDance() async =>
      await _ch.invokeMethod<String>('robotDance') ?? '';
}
