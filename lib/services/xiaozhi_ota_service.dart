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

/// Quản lý định danh thiết bị XiaoZhi.
///
/// Mỗi trợ lý ([profileId]) có MAC + UUID riêng, nên trên xiaozhi.me mỗi trợ lý là một thiết bị
/// riêng, gắn với một agent riêng (giọng + vai trò riêng).
class XiaozhiOtaService {
  static const String defaultOtaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const String defaultWsUrl = 'wss://api.tenclass.net/xiaozhi/v1/';
  static const String appVersion = '2.1.1';

  static const String _prefCustomWsKey = 'mina_custom_ws_url';
  static const String _prefCustomOtaKey = 'mina_custom_ota_url';

  String _macKey(String profileId) => 'mina_device_mac_v2_$profileId';
  String _uuidKey(String profileId) => 'mina_client_uuid_v2_$profileId';

  Future<String> getOrCreateDeviceMac(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_macKey(profileId));
    if (existing != null && existing.isNotEmpty) return existing;

    // MAC "locally administered" (bit 0x02) ngẫu nhiên, cố định cho từng trợ lý
    final rng = Random.secure();
    final bytes = [0x02, for (var i = 0; i < 5; i++) rng.nextInt(256)];
    final mac = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    await prefs.setString(_macKey(profileId), mac);
    return mac;
  }

  Future<String> getOrCreateClientId(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_uuidKey(profileId));
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_uuidKey(profileId), id);
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

  /// Kiểm tra OTA & lấy mã ghép nối 6 chữ số (nếu trợ lý này chưa liên kết trên xiaozhi.me)
  Future<XiaozhiOtaResult> checkOtaAndPairing(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final mac = await getOrCreateDeviceMac(profileId);
    final clientId = await getOrCreateClientId(profileId);
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
      'chip_model_name': 'MediaTek-MT8167',
      'application': {
        'name': 'mina-visbot',
        'version': appVersion,
        'compile_time': '2026-11-09T12:00:00Z',
        'idf_version': 'v5.3-android',
      },
      'board': {
        'type': 'mina-visbot-mt8167',
        'name': 'Mina Visbot ($profileId)',
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
              'User-Agent': 'mina-visbot-mt8167/$appVersion',
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
