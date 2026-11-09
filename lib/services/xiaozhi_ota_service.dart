import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class XiaozhiOtaResult {
  final String wsUrl;
  final String wsToken;
  final String? activationCode; // Mã 6 chữ số để thêm thiết bị miễn phí trên xiaozhi.me
  final String? activationMessage;
  final String deviceMac;
  final String clientId;

  XiaozhiOtaResult({
    required this.wsUrl,
    required this.wsToken,
    required this.deviceMac,
    required this.clientId,
    this.activationCode,
    this.activationMessage,
  });
}

/// Quản lý định danh thiết bị độc lập & ghép nối trực tiếp với hệ thống XiaoZhi chuẩn mở
/// (Hoàn toàn KHÔNG phụ thuộc Supabase hay tài khoản VIP của bất kỳ bên thứ ba nào!)
class XiaozhiOtaService {
  static const String defaultOtaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const String defaultWsUrl = 'wss://api.tenclass.net/xiaozhi/v1/';

  static const String _prefMacKey = 'mina_device_mac_v1';
  static const String _prefUuidKey = 'mina_client_uuid_v1';
  static const String _prefCustomWsKey = 'mina_custom_ws_url';
  static const String _prefCustomOtaKey = 'mina_custom_ota_url';

  Future<String> getOrCreateDeviceMac() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefMacKey);
    if (existing != null && existing.isNotEmpty) return existing;

    // Sinh địa chỉ MAC Locally Administered duy nhất cố định cho robot Mina này
    final rng = Random.secure();
    final bytes = [
      0x02,
      rng.nextInt(256),
      rng.nextInt(256),
      rng.nextInt(256),
      rng.nextInt(256),
      rng.nextInt(256),
    ];
    final mac = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    await prefs.setString(_prefMacKey, mac);
    return mac;
  }

  Future<String> getOrCreateClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefUuidKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_prefUuidKey, id);
    return id;
  }

  Future<String> getCustomWsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCustomWsKey) ?? '';
  }

  Future<void> setCustomWsUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomWsKey, url.trim());
  }

  /// Kiểm tra OTA & lấy mã ghép nối 6 chữ số (nếu chưa liên kết trên xiaozhi.me)
  Future<XiaozhiOtaResult> checkOtaAndPairing() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = await getOrCreateDeviceMac();
    final clientId = await getOrCreateClientId();
    final customWs = (prefs.getString(_prefCustomWsKey) ?? '').trim();
    final otaUrl = (prefs.getString(_prefCustomOtaKey) ?? defaultOtaUrl).trim();

    if (customWs.isNotEmpty) {
      return XiaozhiOtaResult(
        wsUrl: customWs,
        wsToken: 'mina-local-token',
        deviceMac: mac,
        clientId: clientId,
      );
    }

    final payload = {
      'version': 2,
      'language': 'vi',
      'flash_size': 16777216,
      'minimum_free_heap_size': 8388608,
      'mac_address': mac,
      'uuid': clientId,
      'chip_model_name': 'Android-USB-OTG',
      'application': {
        'name': 'mina-robot',
        'version': '1.0.0',
        'compile_time': '2026-11-05T12:00:00Z',
        'idf_version': 'v5.3-android',
      },
      'board': {
        'type': 'mina-robonova-a33',
        'name': 'Mina Humanoid Robot',
        'ssid': 'RobotWiFi',
        'rssi': -45,
        'channel': 6,
        'ip': '192.168.1.100',
        'mac': mac,
      },
    };

    try {
      final resp = await http
          .post(
            Uri.parse(otaUrl),
            headers: {
              'Content-Type': 'application/json',
              'Device-Id': mac,
              'Client-Id': clientId,
              'User-Agent': 'mina-robonova-a33/1.0.0',
              'Accept-Language': 'vi-VN,vi;q=0.9',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final wsMap = (map['websocket'] as Map?)?.cast<String, dynamic>();
        final actMap = (map['activation'] as Map?)?.cast<String, dynamic>();

        return XiaozhiOtaResult(
          wsUrl: wsMap?['url']?.toString() ?? defaultWsUrl,
          wsToken: wsMap?['token']?.toString() ?? 'test-token',
          deviceMac: mac,
          clientId: clientId,
          activationCode: actMap?['code']?.toString(),
          activationMessage: actMap?['message']?.toString(),
        );
      }
    } catch (_) {}

    return XiaozhiOtaResult(
      wsUrl: defaultWsUrl,
      wsToken: 'test-token',
      deviceMac: mac,
      clientId: clientId,
    );
  }
}
