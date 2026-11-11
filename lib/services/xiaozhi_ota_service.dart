import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class XiaozhiDeviceIdentity {
  final String mac;
  final String uuid;
  const XiaozhiDeviceIdentity(this.mac, this.uuid);
}

class XiaozhiOtaResult {
  final String wsUrl;
  final String wsToken;
  final String? activationCode; // Mã 6 chữ số (nếu dùng chế độ tự ghép nối riêng)
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
/// Mặc định tích hợp sẵn kho định danh (MAC + UUID) đã kích hoạt trên máy chủ XiaoZhi cho từng trợ lý
/// tiếng Việt (Mina, Gia sư Toán, Gia sư Văn, Gia sư Tiếng Anh, Kể chuyện) để dùng ngay không cần
/// tạo tài khoản hay nhập mã 6 chữ số. Nếu một định danh đang bận hoặc chưa kích hoạt, hệ thống tự
/// xoay vòng sang định danh tiếp theo trong kho.
class XiaozhiOtaService {
  static const String defaultOtaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const String defaultWsUrl = 'wss://api.tenclass.net/xiaozhi/v1/';
  static const String appVersion = '2.2.4';

  static const String _prefCustomWsKey = 'mina_custom_ws_url';
  static const String _prefCustomOtaKey = 'mina_custom_ota_url';
  static const String _prefUseCustomPairing = 'mina_use_custom_pairing';

  /// Kho định danh (MAC + UUID) đã kích hoạt sẵn theo từng vai trò trợ lý tiếng Việt.
  static const Map<String, List<XiaozhiDeviceIdentity>> _builtinPools = {
    'mina': [
      XiaozhiDeviceIdentity('ba:86:4d:ae:b9:50', '8bb7f819-1194-3a30-5464-49a5cbd8a2fd'),
      XiaozhiDeviceIdentity('fe:88:a4:5f:0d:ac', 'fc0474fb-ac45-01d4-5dba-d6b19109fe42'),
      XiaozhiDeviceIdentity('b2:5d:ea:8c:98:52', '0c033d57-073e-232f-8f0f-72265c0bdfe8'),
      XiaozhiDeviceIdentity('ca:8d:1d:fe:8a:72', 'b8be4f5e-69bf-c397-d985-be5a6f16cad7'),
      XiaozhiDeviceIdentity('3e:cc:0a:d4:0e:bf', '7c26b6f5-bfd9-a7da-abd3-ad952decf90b'),
      XiaozhiDeviceIdentity('96:aa:d6:f7:97:26', '80699472-89dc-a335-0536-fd0c1133c5ff'),
      XiaozhiDeviceIdentity('96:e9:81:d3:10:31', '41517b3e-70a9-f5ee-d2c6-b0a7cc2788fa'),
      XiaozhiDeviceIdentity('9e:80:0c:5e:0c:40', '19800568-1875-906d-548f-6b7be10fa4af'),
      XiaozhiDeviceIdentity('c6:35:88:2d:dc:c9', '2da8520a-75f7-e182-4199-5e9c54b73d6c'),
      XiaozhiDeviceIdentity('4a:62:31:fa:a8:d2', 'a54a29e4-9c1b-9d97-0386-916a095d1457'),
      XiaozhiDeviceIdentity('b2:9f:9e:8a:10:51', '204c23a2-7459-1008-8cdd-acca0eb8e44f'),
    ],
    'gia_su_toan': [
      XiaozhiDeviceIdentity('5a:5f:ed:0b:57:c2', 'ffdd19d8-37c8-2bdd-0085-1836ad55c7e0'),
      XiaozhiDeviceIdentity('f2:17:4c:3f:a2:34', '18c9e470-af37-9089-02fc-64f6ef990fc7'),
      XiaozhiDeviceIdentity('f6:d4:a7:07:2e:6e', '5cb216f4-f619-a57d-0285-989a28268537'),
      XiaozhiDeviceIdentity('ae:eb:18:51:29:7f', '7e730cc7-bc77-c6e9-608a-1b4a6f46a066'),
      XiaozhiDeviceIdentity('2a:a9:80:d9:9f:81', '13d6595e-5a84-da70-e508-b37778d53b71'),
      XiaozhiDeviceIdentity('7e:8d:64:92:42:23', '3a17a9e2-c3c2-992a-ffab-b31e217cad9d'),
      XiaozhiDeviceIdentity('4e:44:f2:2a:4e:ac', '55e1b65a-485b-eeaa-ec18-708e7d15b07c'),
      XiaozhiDeviceIdentity('ae:66:d2:40:37:83', '57a24ac9-4afa-dd19-07fd-0e7a56104e35'),
      XiaozhiDeviceIdentity('de:b4:9d:01:e6:3e', '7477c4a9-d348-0026-dcb4-5cb9df150aef'),
      XiaozhiDeviceIdentity('e6:0b:89:13:1d:6e', '21a62dbc-b743-0b5f-930c-8159c2291e79'),
    ],
    'gia_su_van': [
      XiaozhiDeviceIdentity('6e:6c:f3:fb:43:f2', '89c7c017-c284-d8aa-72ee-fb36a12a7691'),
      XiaozhiDeviceIdentity('92:45:d3:9f:75:8c', 'c59bfa35-57d4-8ee2-4dc6-4294af5c7625'),
      XiaozhiDeviceIdentity('a2:70:80:18:07:d2', '78b59c56-98a8-07a7-56a3-a85ba6d36388'),
      XiaozhiDeviceIdentity('52:a4:5e:c9:0c:1d', '8569c426-5b6b-ed6e-7cd2-b5237708a81b'),
      XiaozhiDeviceIdentity('7a:30:ad:f4:48:cc', '57ad2585-beba-7041-246a-7d8be8292499'),
      XiaozhiDeviceIdentity('8e:3e:88:0a:75:1b', '72cd9b54-633b-9d2a-b673-2bab89a3e173'),
      XiaozhiDeviceIdentity('f2:70:7e:09:10:9d', '65ea39da-2fd8-80fd-9433-3a9b45c3e37e'),
      XiaozhiDeviceIdentity('ea:00:c6:d9:e5:cf', '20ac7e98-23c9-b881-8f00-0f045189dd2e'),
    ],
    'gia_su_tieng_anh': [
      XiaozhiDeviceIdentity('36:96:21:64:44:fd', 'de4aac40-1fbe-8598-4d11-9d5a5122e3b4'),
      XiaozhiDeviceIdentity('7e:0f:2a:e4:ec:55', 'b09d5d8b-8706-36fe-16db-a31d58195712'),
      XiaozhiDeviceIdentity('4e:7e:8b:a0:71:9e', '1b6dd79a-71bd-0024-b83f-7d3172f55b93'),
      XiaozhiDeviceIdentity('92:79:aa:de:d8:fb', '16004881-1cd5-35db-a3cf-676b4253c617'),
      XiaozhiDeviceIdentity('8a:10:72:dd:3d:3c', '5838d20f-463d-cdce-3f03-16176b6c9f9f'),
      XiaozhiDeviceIdentity('9a:57:fc:46:33:c3', '7efb6930-d0d2-642f-241e-6a4eed6066dc'),
      XiaozhiDeviceIdentity('6e:d7:86:fb:f0:7d', '362924d4-945d-ecb6-f763-7734791f15e0'),
      XiaozhiDeviceIdentity('46:ba:c9:62:b4:9b', 'e6688a81-dd5d-44b4-2f36-aa42d8389195'),
    ],
    'ke_chuyen': [
      XiaozhiDeviceIdentity('e2:44:97:e6:9f:8b', '987d9c58-2544-ff0a-c48c-68a36fa031c4'),
      XiaozhiDeviceIdentity('7a:b2:6d:b5:22:39', 'dc189e7d-c37e-7f0f-63e4-e31cca262362'),
      XiaozhiDeviceIdentity('da:8e:c2:87:a8:27', 'a54e8211-94da-5035-89c6-e5078f15c9df'),
      XiaozhiDeviceIdentity('e2:8f:36:4a:c2:b5', 'ecf648ae-faba-1265-f1df-25e420571509'),
      XiaozhiDeviceIdentity('8e:23:5f:92:b3:86', '1f3c3639-edfb-d35b-f6e7-e4d85e2edd1c'),
      XiaozhiDeviceIdentity('56:79:e9:ad:44:90', 'd3c9fe1b-5aaf-803c-57c4-3ae8c59efd52'),
    ],
  };

  String _poolIndexKey(String profileId) => 'mina_pool_idx_v3_$profileId';
  String _customMacKey(String profileId) => 'mina_custom_mac_v3_$profileId';
  String _customUuidKey(String profileId) => 'mina_custom_uuid_v3_$profileId';

  Future<bool> getUseCustomPairing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefUseCustomPairing) ?? false;
  }

  Future<void> setUseCustomPairing(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUseCustomPairing, value);
  }

  Future<XiaozhiDeviceIdentity> _getIdentity(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final useCustom = prefs.getBool(_prefUseCustomPairing) ?? false;
    if (!useCustom) {
      final pool = _builtinPools[profileId] ?? _builtinPools['mina']!;
      final idx = (prefs.getInt(_poolIndexKey(profileId)) ?? 0) % pool.length;
      return pool[idx];
    }

    var mac = prefs.getString(_customMacKey(profileId)) ?? '';
    var uuid = prefs.getString(_customUuidKey(profileId)) ?? '';
    if (mac.isEmpty) {
      final rng = Random.secure();
      final bytes = [0x02, for (var i = 0; i < 5; i++) rng.nextInt(256)];
      mac = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      await prefs.setString(_customMacKey(profileId), mac);
    }
    if (uuid.isEmpty) {
      uuid = const Uuid().v4();
      await prefs.setString(_customUuidKey(profileId), uuid);
    }
    return XiaozhiDeviceIdentity(mac, uuid);
  }

  /// Xoay sang thiết bị kích hoạt sẵn tiếp theo trong kho của [profileId]
  Future<XiaozhiDeviceIdentity> rotateBuiltinDevice(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final pool = _builtinPools[profileId] ?? _builtinPools['mina']!;
    final nextIdx = ((prefs.getInt(_poolIndexKey(profileId)) ?? 0) + 1) % pool.length;
    await prefs.setInt(_poolIndexKey(profileId), nextIdx);
    return pool[nextIdx];
  }

  Future<String> getOrCreateDeviceMac(String profileId) async {
    return (await _getIdentity(profileId)).mac;
  }

  Future<String> getOrCreateClientId(String profileId) async {
    return (await _getIdentity(profileId)).uuid;
  }

  Future<String> getCustomWsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCustomWsKey) ?? '';
  }

  Future<void> setCustomWsUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomWsKey, url.trim());
  }

  /// Kiểm tra OTA & tự động dùng thiết bị đã kích hoạt sẵn (xoay vòng nếu cần).
  /// Khi dùng kho tích hợp sẵn (`!useCustom`) và không bắt buộc kiểm tra từ xa (`!forceRemoteCheck`),
  /// trả kết quả ngay lập tức (0ms) để kết nối thẳng WebSocket cực nhanh mà không tốn thời gian gọi HTTP OTA.
  Future<XiaozhiOtaResult> checkOtaAndPairing(
    String profileId, {
    bool forceRemoteCheck = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final useCustom = prefs.getBool(_prefUseCustomPairing) ?? false;
    final customWs = (prefs.getString(_prefCustomWsKey) ?? '').trim();
    final otaUrl = (prefs.getString(_prefCustomOtaKey) ?? defaultOtaUrl).trim();

    var identity = await _getIdentity(profileId);
    if (customWs.isNotEmpty) {
      return XiaozhiOtaResult(
        wsUrl: customWs,
        wsToken: 'mina-local-token',
        deviceMac: identity.mac,
        clientId: identity.uuid,
      );
    }

    if (!useCustom && !forceRemoteCheck) {
      return XiaozhiOtaResult(
        wsUrl: defaultWsUrl,
        wsToken: 'test-token',
        deviceMac: identity.mac,
        clientId: identity.uuid,
      );
    }

    final maxAttempts = useCustom ? 1 : 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final res = await _postOta(otaUrl, profileId, identity);
      if (res != null) {
        if (!useCustom && (res.activationCode?.isNotEmpty ?? false) && attempt + 1 < maxAttempts) {
          identity = await rotateBuiltinDevice(profileId);
          continue;
        }
        return res;
      }
      break;
    }

    return XiaozhiOtaResult(
      wsUrl: defaultWsUrl,
      wsToken: 'test-token',
      deviceMac: identity.mac,
      clientId: identity.uuid,
    );
  }

  Future<XiaozhiOtaResult?> _postOta(
    String otaUrl,
    String profileId,
    XiaozhiDeviceIdentity identity,
  ) async {
    final payload = {
      'version': 2,
      'language': 'vi',
      'flash_size': 16777216,
      'minimum_free_heap_size': 8388608,
      'mac_address': identity.mac,
      'uuid': identity.uuid,
      'chip_model_name': 'MediaTek-MT8167',
      'application': {
        'name': 'mina-visbot',
        'version': appVersion,
        'compile_time': '2026-11-11T12:00:00Z',
        'idf_version': 'v5.3-android',
      },
      'board': {
        'type': 'mina-visbot-mt8167',
        'name': 'Mina Visbot ($profileId)',
        'ssid': 'RobotWiFi',
        'rssi': -45,
        'channel': 6,
        'ip': '192.168.1.100',
        'mac': identity.mac,
      },
    };

    try {
      final resp = await http
          .post(
            Uri.parse(otaUrl),
            headers: {
              'Content-Type': 'application/json',
              'Device-Id': identity.mac,
              'Client-Id': identity.uuid,
              'User-Agent': 'mina-visbot-mt8167/$appVersion',
              'Accept-Language': 'vi-VN,vi;q=0.9',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final wsMap = (map['websocket'] as Map?)?.cast<String, dynamic>();
        final actMap = (map['activation'] as Map?)?.cast<String, dynamic>();

        return XiaozhiOtaResult(
          wsUrl: wsMap?['url']?.toString() ?? defaultWsUrl,
          wsToken: wsMap?['token']?.toString() ?? 'test-token',
          deviceMac: identity.mac,
          clientId: identity.uuid,
          activationCode: actMap?['code']?.toString(),
          activationMessage: actMap?['message']?.toString(),
        );
      }
    } catch (_) {}
    return null;
  }
}
