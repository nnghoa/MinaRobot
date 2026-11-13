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
  static const String appVersion = '2.2.7';

  static const String _prefCustomWsKey = 'mina_custom_ws_url';
  static const String _prefCustomOtaKey = 'mina_custom_ota_url';
  static const String _prefUseCustomPairing = 'mina_use_custom_pairing';

  /// Kho định danh (MAC + UUID) thế hệ mới (`02:53:...`) đã kích hoạt sẵn theo từng vai trò trợ lý tiếng Việt.
  static const Map<String, List<XiaozhiDeviceIdentity>> _builtinPools = {
    'mina': [
      XiaozhiDeviceIdentity('02:53:01:48:49:15', 'fda1f204-5b1b-4997-86eb-1c8bf81b8558'),
      XiaozhiDeviceIdentity('02:53:02:01:49:15', 'b8e1ff22-1721-4218-8256-588646ccb9d6'),
      XiaozhiDeviceIdentity('02:53:02:02:49:15', 'f6de4f28-0e2b-4de9-8fca-d482ecd0b9bf'),
      XiaozhiDeviceIdentity('02:53:02:03:49:15', 'fc7dadbb-3f3f-4ebe-8a57-432e6a0e6c60'),
      XiaozhiDeviceIdentity('02:53:02:04:49:15', '0e45a4f7-a47d-45c6-ba00-72b530cb6da3'),
      XiaozhiDeviceIdentity('02:53:02:05:49:15', 'aee11979-45c7-45c1-ba14-d6c4eaa33e95'),
      XiaozhiDeviceIdentity('02:53:02:06:49:15', '156d177c-ab73-4f60-8e78-f6e43f015cfb'),
      XiaozhiDeviceIdentity('02:53:02:07:49:15', 'b40bbdd6-634d-47d8-82ae-e6bcda37e90a'),
      XiaozhiDeviceIdentity('02:53:02:08:49:15', 'a6f2380a-ca6d-42aa-9ecb-3dccf8dc3024'),
      XiaozhiDeviceIdentity('02:53:02:09:49:15', '8d2618f9-76b1-4f97-93c7-f6d1c49da0f6'),
      XiaozhiDeviceIdentity('02:53:02:0a:49:15', 'b4747c3c-966c-4949-8844-f4f73da2c6f2'),
      XiaozhiDeviceIdentity('02:53:02:48:49:15', '95dc1ac7-022c-4205-9f76-abfc87edf4d6'),
      XiaozhiDeviceIdentity('02:53:03:01:49:15', '50768033-f113-4eb8-8870-9bb5dbcbc8aa'),
      XiaozhiDeviceIdentity('02:53:03:02:49:15', 'e3f4cc45-a27d-4c43-906e-8f54feb98615'),
      XiaozhiDeviceIdentity('02:53:01:48:49:12', '3cb07610-8774-472e-82f4-7a5b559e2b95'),
      XiaozhiDeviceIdentity('02:53:02:01:49:12', 'dcb95da6-e7ba-4179-b302-afbfcf0a48f7'),
      XiaozhiDeviceIdentity('02:53:02:02:49:12', '1729dcdc-a6d8-4d16-9e62-d1eb256d011d'),
      XiaozhiDeviceIdentity('02:53:02:03:49:12', 'f2a6e2f6-2254-4317-8e89-23a1a2befb67'),
      XiaozhiDeviceIdentity('02:53:02:04:49:12', 'f953c30c-df36-45e6-87ed-830b1a1f1605'),
      XiaozhiDeviceIdentity('02:53:02:48:49:12', '3bfad391-2e28-4826-b6fc-9cb3b36d1a7a'),
      XiaozhiDeviceIdentity('02:53:03:01:49:12', '1b85e756-4c9a-4fc9-a079-4226761f8d96'),
      XiaozhiDeviceIdentity('02:53:03:02:49:12', '87961e47-ddfe-4839-a2ce-28ac05a6f55d'),
      XiaozhiDeviceIdentity('02:53:03:03:49:12', 'c618c3c8-e2f1-46fb-8b30-471455fe62ae'),
      XiaozhiDeviceIdentity('02:53:03:04:49:12', 'ec6143e0-a23c-4537-93ec-56349b2ad218'),
    ],
    'gia_su_toan': [
      XiaozhiDeviceIdentity('02:53:01:48:49:16', '0923bf0d-731f-42b6-acdc-ff55b4edf700'),
      XiaozhiDeviceIdentity('02:53:02:01:49:16', 'd30ed97c-eb8f-4757-bc20-7d9b89cf000f'),
      XiaozhiDeviceIdentity('02:53:02:02:49:16', '2a6b0672-cae2-4d1d-8ace-cff759b418f3'),
      XiaozhiDeviceIdentity('02:53:02:03:49:16', 'b72a2e9e-553a-4882-910b-91c261c64174'),
      XiaozhiDeviceIdentity('02:53:02:04:49:16', '7b2cf12f-0d19-4017-8255-0d7a81ae1434'),
      XiaozhiDeviceIdentity('02:53:02:05:49:16', 'a7b91415-eceb-4815-9546-455c320c6335'),
      XiaozhiDeviceIdentity('02:53:02:48:49:16', '921d5ccd-18b8-4e0f-9953-016c414ae871'),
      XiaozhiDeviceIdentity('02:53:03:01:49:16', '335d435b-3184-4139-a4b7-000ca19c0511'),
      XiaozhiDeviceIdentity('02:53:03:02:49:16', '4e41afa5-4f2b-41c4-8c69-3a5daf15d6d5'),
      XiaozhiDeviceIdentity('02:53:03:03:49:16', '6cd4cb25-431a-4112-8a9a-b6d78a932907'),
      XiaozhiDeviceIdentity('02:53:03:04:49:16', '0a094632-b5ad-417e-b277-7099d46caed7'),
      XiaozhiDeviceIdentity('02:53:03:05:49:16', '9e7605ad-58f7-4696-b7c8-19f8a303c9e6'),
      XiaozhiDeviceIdentity('02:53:03:48:49:16', '72b8632f-40d1-427e-b6a8-7209a4d3a5c7'),
      XiaozhiDeviceIdentity('02:53:04:01:49:16', '2800ef88-0448-492c-a5d5-ae8a080d995c'),
      XiaozhiDeviceIdentity('02:53:04:02:49:16', '9d163b65-6a86-4112-a898-3dc3a64c1b34'),
      XiaozhiDeviceIdentity('02:53:04:03:49:16', 'b5fc1fc8-0d14-43e6-9ecd-30c507e714e2'),
      XiaozhiDeviceIdentity('02:53:01:48:49:17', 'f7c7fd1f-7414-4c80-a929-0111900b9cd9'),
      XiaozhiDeviceIdentity('02:53:02:48:49:17', '75879839-1da9-41a9-97e1-20614e4964bf'),
      XiaozhiDeviceIdentity('02:53:03:48:49:17', '033ab06c-926f-46b3-aaaf-23fe221604cc'),
      XiaozhiDeviceIdentity('02:53:04:48:49:17', 'deb0d3b9-f616-45f1-85d6-742b65947140'),
      XiaozhiDeviceIdentity('02:53:05:01:49:17', '011348fc-2556-4f96-b78c-56bfe58aa48e'),
      XiaozhiDeviceIdentity('02:53:05:02:49:17', 'e62f8009-5c43-42fc-b256-a634f3e2886e'),
      XiaozhiDeviceIdentity('02:53:05:03:49:17', 'a4184320-1d08-4d5b-b6d4-db7b3bedc380'),
      XiaozhiDeviceIdentity('02:53:05:04:49:17', '4b10f5e7-4709-4838-936c-e3d7aa29a317'),
    ],
    'gia_su_van': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0e', '55c63710-693e-4bfe-a926-034762cbd35a'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0e', '6878ced4-2c91-4c3d-8819-2fe45ef4abf9'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0e', 'd58954bb-de11-4910-b1e7-feb81525956c'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0e', '7718cdcc-b11a-406e-b582-767c6c8cc9e3'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0e', 'a051d275-6799-41eb-a056-6ce88d149966'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0e', '6d96d4ba-c55c-42a2-a83b-e2a12c634b88'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0e', '1be83623-aa6a-434e-9901-e3c1304ff964'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0e', 'd890c77b-9173-44c8-8bd5-7de599a74b56'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0e', '1d5556c3-9fd3-454e-a044-c8def7b53ecc'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0e', '4d795534-7f6a-42f2-8523-cef8a85c0c3e'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0e', '4d346374-a81f-48f5-91ee-f9d6c8144b79'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0e', 'debec5bb-edc2-4dd3-b7ab-c5cca87c9781'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0e', '85a9aa17-9f38-46b6-8d9b-6b193510478b'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0e', 'c79c0a64-416f-4fe2-8626-93f7163f88c6'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0e', 'a827e5b4-fea1-49ef-b0c7-65c6f280fa4a'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0e', '130c7eaa-49d0-46a1-980f-f68fe402acc3'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0e', '1de7d107-46f6-4fcd-bbc5-62024d69419a'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0e', 'a4ba5e49-c65b-4a93-b52f-4d5b84e4c78f'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0e', '0ed828cc-b859-48f8-ac72-5b9b19a8805a'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0e', '88018a43-ba23-4fb2-a1b2-c427bfeb14dd'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0e', 'bd1b121e-081b-467c-b261-ff1b78dfca79'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0e', '54f7c71c-1ed6-4b3f-a836-71005cfec10f'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0e', '058af9e5-4a2f-48f6-b8a4-5c2c09a915e3'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0e', 'd86c96ea-d1da-4c9b-9918-4da13b5e9b3d'),
    ],
    'gia_su_tieng_anh': [
      XiaozhiDeviceIdentity('02:53:01:48:49:13', '7ae65f99-d5d3-4731-bd57-e77b3bc60594'),
      XiaozhiDeviceIdentity('02:53:02:01:49:13', '06e04e66-b6f3-48f8-aae2-f6470bd6c5b4'),
      XiaozhiDeviceIdentity('02:53:02:02:49:13', 'e81ca817-894b-4e52-9ffc-eeff2ad3aff2'),
      XiaozhiDeviceIdentity('02:53:02:03:49:13', 'f21350a8-8857-4b4b-a2a0-adfb6def093f'),
      XiaozhiDeviceIdentity('02:53:02:04:49:13', 'd26a5882-fa8e-44fb-a300-42b7e04ab29a'),
      XiaozhiDeviceIdentity('02:53:02:05:49:13', '868f16f8-8ca5-4529-a865-5ea7a624a9b6'),
      XiaozhiDeviceIdentity('02:53:02:48:49:13', '7ad7dc49-dfb1-4ffd-85d8-8d5f6dc6f821'),
      XiaozhiDeviceIdentity('02:53:03:01:49:13', 'f7a1110b-858f-4db1-a456-dbeac1ef012e'),
      XiaozhiDeviceIdentity('02:53:03:02:49:13', '9ba7f088-3a85-452b-af27-ed4c4d39729a'),
      XiaozhiDeviceIdentity('02:53:03:03:49:13', 'cb2d481c-ab98-4718-827e-edf5acbe97e5'),
      XiaozhiDeviceIdentity('02:53:03:04:49:13', '9970aea2-ae69-4418-aff9-d0da5a8998fe'),
      XiaozhiDeviceIdentity('02:53:03:05:49:13', '63967d20-c498-43ed-9694-6719de30bb4b'),
      XiaozhiDeviceIdentity('02:53:03:48:49:13', '921a8104-b9a5-42bf-b324-7009f1635bdf'),
      XiaozhiDeviceIdentity('02:53:04:01:49:13', 'c7d8f79f-6f2b-4711-aad3-f254f5f5102f'),
      XiaozhiDeviceIdentity('02:53:04:02:49:13', '17dcf585-9acd-4c04-bba1-d0266da55a42'),
      XiaozhiDeviceIdentity('02:53:04:03:49:13', '4276c75c-eb04-45a6-ba2d-65ed47120849'),
      XiaozhiDeviceIdentity('02:53:04:04:49:13', 'cdae2189-b249-4422-bd4b-76e0a4507642'),
      XiaozhiDeviceIdentity('02:53:04:05:49:13', '21210336-d838-4cfb-8669-b77f1dc38596'),
      XiaozhiDeviceIdentity('02:53:04:48:49:13', 'c9414e79-7b28-456c-8a06-c07047aff181'),
      XiaozhiDeviceIdentity('02:53:05:01:49:13', 'a20b9963-0236-4182-ade6-80a8988e7b9c'),
      XiaozhiDeviceIdentity('02:53:05:02:49:13', '76cbfeea-141d-4498-8485-da399f44db6b'),
      XiaozhiDeviceIdentity('02:53:05:03:49:13', '49755b38-67b0-4a1a-9fe8-f7ceba3c0198'),
      XiaozhiDeviceIdentity('02:53:05:04:49:13', '05a3bad4-6ddf-426a-8b71-32fdd571535f'),
      XiaozhiDeviceIdentity('02:53:05:05:49:13', 'feb8e06c-7616-4e8f-aa6f-45f942e179c4'),
    ],
    'ke_chuyen': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0a', 'fad47edd-2db3-40b2-9599-1611932f8122'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0a', '50b9dfdc-13e9-4fcf-8607-9503670cee22'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0a', '0ccccedf-8645-4d23-b487-5954dd5619b7'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0a', '7b958fdc-f21c-4641-b3b8-b27578327329'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0a', 'cd5991cb-8bd6-40e1-9206-7a76b63c8c5b'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0a', '2bef551e-d4fd-4a95-bfff-7bb4a826e195'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0a', '1b7217e5-f932-4a0b-8ea3-cdf23b4fd5ff'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0a', 'd3c3f189-771c-4a8f-af24-11688d69c812'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0a', '0e6454a4-8f23-4b52-b978-a56f2587289f'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0a', '95161d43-bdd8-4a7b-9b3b-4988bfb07fe5'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0a', 'ae9af25a-46fc-45b4-b962-7b10adef96c1'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0a', '9b205875-d4ac-4b67-bb07-21e2e9657a2a'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0a', '4708f842-208e-4800-b2b4-3343fd2b518b'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0a', 'd65815f0-0c7e-4969-b7ee-f788913a0c5d'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0a', 'c0bc8afc-6f80-4e7a-8fa2-1cb45d2c0ee5'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0a', '0cd6186a-cec4-4527-9817-8c14423b8ef3'),
      XiaozhiDeviceIdentity('02:53:03:05:49:12', '234d87bf-0efe-4cf3-b669-343071c2a41d'),
      XiaozhiDeviceIdentity('02:53:03:48:49:12', '3917a01e-dd63-433a-9cf0-1e89817bca1e'),
      XiaozhiDeviceIdentity('02:53:04:01:49:12', '91f722ef-b407-4b3a-bc9e-d44bb84e507e'),
      XiaozhiDeviceIdentity('02:53:04:02:49:12', '5a09043a-1c06-47fc-b0a9-9c8c0f221d41'),
      XiaozhiDeviceIdentity('02:53:04:03:49:12', 'd335f875-3dca-41c0-b835-ddd84d47f477'),
      XiaozhiDeviceIdentity('02:53:04:04:49:12', 'db0093bd-e349-4240-915e-a8c1ec836e52'),
      XiaozhiDeviceIdentity('02:53:04:05:49:12', '9ea42e90-aceb-48e3-93e8-809551db3571'),
      XiaozhiDeviceIdentity('02:53:04:48:49:12', 'c1bbc4b8-0837-45bc-aae3-149119e98feb'),
    ],
  };

  String _poolIndexKey(String profileId) => 'mina_pool_idx_v4_$profileId';
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
