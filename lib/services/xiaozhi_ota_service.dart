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
  static const String appVersion = '2.2.8';

  static const String _prefCustomWsKey = 'mina_custom_ws_url';
  static const String _prefCustomOtaKey = 'mina_custom_ota_url';
  static const String _prefUseCustomPairing = 'mina_use_custom_pairing';

  /// Kho định danh (MAC + UUID) thế hệ mới (`02:53:...`) đã kích hoạt sẵn theo từng vai trò trợ lý tiếng Việt.
  static const Map<String, List<XiaozhiDeviceIdentity>> _builtinPools = {
    'mina': [
      XiaozhiDeviceIdentity('02:53:01:48:49:15', 'c51f7560-4316-425e-b85a-f1d99d6c32cf'),
      XiaozhiDeviceIdentity('02:53:02:01:49:15', '4df9f7fc-d696-4678-8a7a-c6b1fce9fc52'),
      XiaozhiDeviceIdentity('02:53:02:02:49:15', 'dcb4a5e9-bb30-4f18-84bd-3be1552dfe5e'),
      XiaozhiDeviceIdentity('02:53:02:03:49:15', 'd29d4b45-8c2f-4a45-9452-32709bb8f126'),
      XiaozhiDeviceIdentity('02:53:02:04:49:15', 'b04a7b28-62dd-4149-aec3-7846547dce77'),
      XiaozhiDeviceIdentity('02:53:02:05:49:15', '2a3044b4-f793-4258-afa3-2f4eef72c02d'),
      XiaozhiDeviceIdentity('02:53:02:06:49:15', '4e830d80-f3b9-4eaa-b3a2-4dba85fa4188'),
      XiaozhiDeviceIdentity('02:53:02:07:49:15', '59bb6352-d566-45cb-8f24-2d550a016569'),
      XiaozhiDeviceIdentity('02:53:02:08:49:15', '011e1dbd-640f-444c-a252-0e5d8f47670b'),
      XiaozhiDeviceIdentity('02:53:02:09:49:15', 'c8dcabbe-bc18-4848-8e79-e7abcc5471bf'),
      XiaozhiDeviceIdentity('02:53:02:0a:49:15', 'd0918c4f-5fc9-4ac8-a5da-48fea4c5f04d'),
      XiaozhiDeviceIdentity('02:53:02:48:49:15', '309a9ee9-12cf-4d31-962a-033416b5327c'),
      XiaozhiDeviceIdentity('02:53:03:01:49:15', 'd32eede6-4805-48b1-b187-e2af2f70dc85'),
      XiaozhiDeviceIdentity('02:53:03:02:49:15', 'f928a558-4158-47a0-9520-73f2b95daee3'),
      XiaozhiDeviceIdentity('02:53:03:03:49:15', 'a02c1773-afb6-463a-92e2-760d9ccbadde'),
      XiaozhiDeviceIdentity('02:53:03:04:49:15', 'cd16f042-60a8-4cfe-b72c-32d32746f276'),
      XiaozhiDeviceIdentity('02:53:03:05:49:15', 'ca7df0ca-5250-4ef0-a710-2f70fbd7f172'),
      XiaozhiDeviceIdentity('02:53:03:06:49:15', '4eece7a2-072d-4a2d-8a2a-643188a51da2'),
      XiaozhiDeviceIdentity('02:53:03:07:49:15', 'f53dc88b-2ec7-4be4-9294-c0ba9cd4bc7a'),
      XiaozhiDeviceIdentity('02:53:03:08:49:15', 'd3e32dd4-75bd-4931-8382-ffbc8e600c8d'),
      XiaozhiDeviceIdentity('02:53:03:09:49:15', '36b1e7a9-8929-4dea-be78-1702e8ffddc0'),
      XiaozhiDeviceIdentity('02:53:03:0a:49:15', '563b1069-263d-45a6-be5b-62db1be20170'),
      XiaozhiDeviceIdentity('02:53:03:48:49:15', '7607e4ce-88ab-4cf4-833e-45f492041278'),
      XiaozhiDeviceIdentity('02:53:04:01:49:15', '9a32ef4a-8cef-4c92-b6ca-903d8990e136'),
    ],
    'gia_su_toan': [
      XiaozhiDeviceIdentity('02:53:01:48:49:16', 'b6b71f98-2fbd-4cc1-b248-40e3c3a03fc8'),
      XiaozhiDeviceIdentity('02:53:02:01:49:16', '3ef426a1-d302-469c-8b35-2f30bb4a022e'),
      XiaozhiDeviceIdentity('02:53:02:02:49:16', '112b2fb5-0acd-4a9d-9d36-b13180093d97'),
      XiaozhiDeviceIdentity('02:53:02:03:49:16', 'ddb83cf4-ec1a-4f78-9fe9-95ccaa6f7996'),
      XiaozhiDeviceIdentity('02:53:02:04:49:16', 'e8a8cb56-bb6e-4999-97f5-e0265befa0dc'),
      XiaozhiDeviceIdentity('02:53:02:05:49:16', 'b04cc244-dc1e-4c16-b92a-f9414db51731'),
      XiaozhiDeviceIdentity('02:53:02:48:49:16', 'c689a407-0cf2-47e0-a0f4-0dc492f48f4f'),
      XiaozhiDeviceIdentity('02:53:03:01:49:16', 'd14ee688-a4c9-42a5-a0df-2946c0981126'),
      XiaozhiDeviceIdentity('02:53:03:02:49:16', 'cd834402-5c54-4154-a47e-6bf90778b045'),
      XiaozhiDeviceIdentity('02:53:03:03:49:16', 'a0355e52-cb56-4c56-9492-4ed2b59f942a'),
      XiaozhiDeviceIdentity('02:53:03:04:49:16', '65d67a16-ef76-495c-adf1-2f4d93bae898'),
      XiaozhiDeviceIdentity('02:53:03:05:49:16', 'fc281f68-f68f-474a-8ba9-3e9b4d4a34d5'),
      XiaozhiDeviceIdentity('02:53:03:48:49:16', 'e188898d-f948-4848-92a1-4260da0a2c24'),
      XiaozhiDeviceIdentity('02:53:04:01:49:16', '62e1c6b9-33c7-4338-ade3-58e03adc64c3'),
      XiaozhiDeviceIdentity('02:53:04:02:49:16', '1b372423-fa49-4b78-aaa7-84b1bfaef409'),
      XiaozhiDeviceIdentity('02:53:04:03:49:16', '5c602936-7634-456c-9d05-d23c7b965fa4'),
      XiaozhiDeviceIdentity('02:53:04:04:49:16', '7be1f49b-24e6-4aef-b789-7f9c1409c7a2'),
      XiaozhiDeviceIdentity('02:53:04:05:49:16', 'dbbf1391-78cf-4796-a912-5073d7aab5bd'),
      XiaozhiDeviceIdentity('02:53:04:48:49:16', '0cdc559a-663a-4f04-b0c0-cffe28677dfb'),
      XiaozhiDeviceIdentity('02:53:05:01:49:16', 'e3df47b3-2a3b-4801-be3d-9e9db18dde4e'),
      XiaozhiDeviceIdentity('02:53:05:02:49:16', 'a3c02906-f38e-4a66-86ee-893e6346ddf5'),
      XiaozhiDeviceIdentity('02:53:05:03:49:16', '61016491-a59f-4a0c-9698-198391150ba0'),
      XiaozhiDeviceIdentity('02:53:05:04:49:16', '1bc87e8c-bc7f-4bb1-a252-0b0fe81e76bc'),
      XiaozhiDeviceIdentity('02:53:05:05:49:16', '278172f1-2d1e-4ffc-9c37-8dd8ad85fbaa'),
    ],
    'gia_su_hinh_hoc': [
      XiaozhiDeviceIdentity('02:53:01:48:49:17', '886ae40e-dfd3-4cdd-b997-17e4439d0b32'),
      XiaozhiDeviceIdentity('02:53:02:48:49:17', '265c3ae8-aec7-4aa0-abc9-8b3b61951c42'),
      XiaozhiDeviceIdentity('02:53:03:48:49:17', '5586ba0b-c43f-405f-92fc-76272bc9c93d'),
      XiaozhiDeviceIdentity('02:53:04:48:49:17', '0ccbe5aa-835e-4459-a664-c9f46339e9d5'),
      XiaozhiDeviceIdentity('02:53:05:01:49:17', 'a43fc9a3-ad84-4206-8cc6-6d21d67dd691'),
      XiaozhiDeviceIdentity('02:53:05:02:49:17', '33367907-599c-4f7c-95d5-f1cfcbefea92'),
      XiaozhiDeviceIdentity('02:53:05:03:49:17', 'f2044e72-a4f5-42e6-b746-8b25134a9cc1'),
      XiaozhiDeviceIdentity('02:53:05:04:49:17', '26327bef-8856-48a5-b241-e18fca94ca31'),
      XiaozhiDeviceIdentity('02:53:05:05:49:17', '59671b60-f893-4b39-bd90-501f4841bbfa'),
      XiaozhiDeviceIdentity('02:53:05:48:49:17', '37ed82ad-e2fe-4fb3-a9a5-6ae57b43ae4d'),
      XiaozhiDeviceIdentity('02:53:06:48:49:17', '8fa15715-c05b-4420-93ad-858bd80bf8da'),
      XiaozhiDeviceIdentity('02:53:07:48:49:17', '99b53bcd-02d4-44a4-9ff7-b47ab0445b4d'),
      XiaozhiDeviceIdentity('02:53:08:48:49:17', '51988d02-0f5f-477a-94b2-e96bff54ddca'),
      XiaozhiDeviceIdentity('02:53:50:48:49:17', '283929dc-4da3-4650-b7c6-49ce96d69a3d'),
      XiaozhiDeviceIdentity('02:53:80:01:49:17', 'febae7c9-f76c-4b18-b60a-8fadad814b0e'),
      XiaozhiDeviceIdentity('02:53:88:48:49:17', '2f658000-b65b-41cb-a948-1d273806bb8b'),
    ],
    'gia_su_van': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0e', '8d4c3894-c5de-4c5e-8213-61e1c84e7c31'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0e', '68a4b2d9-4d7e-408c-8d76-2a2da4e010c9'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0e', 'f713fb22-eef2-41c9-a77f-a5767b078945'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0e', 'd4862e27-88a7-437f-bc24-3cddc22bb3c0'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0e', '1af4049a-c15c-4dbe-afb9-7fb80dedaeeb'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0e', '64866aa1-8b9c-4a2e-aaf4-707a2dd38b14'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0e', '9470991a-3baf-40a3-a353-3e3136e268aa'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0e', '2b7249ae-7855-46ac-a622-f37c696d030c'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0e', 'bbc2e09d-c904-4dd6-8933-e5e209970cf5'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0e', '1d16d2f8-2caf-42f2-aa4f-3c26aea40568'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0e', 'fedd46a2-c194-4ac7-bfd8-01d7cd0ae5f1'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0e', 'f53c6fab-8c0a-4fe2-89ca-cb879f6e3adc'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0e', '3e10273c-19c2-4004-b3c1-686bb83c2334'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0e', 'c2835b0b-04fa-4c6d-bae5-5ebea426ab88'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0e', 'eed1236f-f9ee-49f4-a9e1-df565fde1c8d'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0e', 'e3121a68-f54e-4f73-bf3f-83932b7d89d5'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0e', '3d776e86-dfe0-4155-879d-1d17feda1d8c'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0e', '659774fe-545b-43b6-b9e2-6f1b551e838d'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0e', 'e53c3b20-3cf3-40fa-be43-68d2f889938a'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0e', 'ad304d72-8ee3-494e-91c0-9957aceb70e0'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0e', '1823fe44-cfaa-47f8-910c-863749b0ebd1'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0e', '0fe729c1-cbad-473d-9420-3edb1c0049fc'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0e', '7b738e92-3e52-498f-9801-f73b87d53793'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0e', 'eb711da7-900a-4d1a-9d40-8c5ee033c148'),
    ],
    'gia_su_tieng_anh': [
      XiaozhiDeviceIdentity('02:53:01:48:49:13', '82ee5e0a-55b9-473f-9448-5c52de9e17b1'),
      XiaozhiDeviceIdentity('02:53:02:01:49:13', 'd54967c8-a26a-4237-a769-58d64e8dd24a'),
      XiaozhiDeviceIdentity('02:53:02:02:49:13', '4e1247b8-7b99-446b-b37a-c998a0e0f84b'),
      XiaozhiDeviceIdentity('02:53:02:03:49:13', '9fe7a3ef-d89a-4768-837f-10dc235acdf9'),
      XiaozhiDeviceIdentity('02:53:02:04:49:13', '624ece49-fbab-44ca-b262-67756aab5517'),
      XiaozhiDeviceIdentity('02:53:02:05:49:13', '4a4c9125-6dba-49e9-8b14-1741416c7462'),
      XiaozhiDeviceIdentity('02:53:02:48:49:13', '50d0c58e-a934-4459-a22d-1c9494b077f4'),
      XiaozhiDeviceIdentity('02:53:03:01:49:13', '36d0b270-d5a5-4356-b0c4-d0bcaad46551'),
      XiaozhiDeviceIdentity('02:53:03:02:49:13', '82660625-ba46-453a-8f9f-8357309676e2'),
      XiaozhiDeviceIdentity('02:53:03:03:49:13', '8b60d251-be38-47da-8ecc-74b8e43aca59'),
      XiaozhiDeviceIdentity('02:53:03:04:49:13', 'b9ecf1ac-f250-4ad6-b9a2-8e88492de934'),
      XiaozhiDeviceIdentity('02:53:03:05:49:13', '8db2a3df-1d69-4fe7-9b39-9ae75deb6a6e'),
      XiaozhiDeviceIdentity('02:53:03:48:49:13', 'a62303c7-6827-49c1-8038-8d57c7969c5a'),
      XiaozhiDeviceIdentity('02:53:04:01:49:13', 'da86fe5c-6214-469d-a447-891cb61edb39'),
      XiaozhiDeviceIdentity('02:53:04:02:49:13', '66df7f32-a3fb-4ce5-8872-94f225f329bb'),
      XiaozhiDeviceIdentity('02:53:04:03:49:13', 'a132355f-8444-499c-8f98-92a78662411f'),
      XiaozhiDeviceIdentity('02:53:04:04:49:13', 'd81f96af-719a-40cf-a936-033c4b6949d2'),
      XiaozhiDeviceIdentity('02:53:04:05:49:13', '19330d24-5742-40fc-b7e9-ef22267851e5'),
      XiaozhiDeviceIdentity('02:53:04:48:49:13', 'ce7085db-3298-4bc5-86e6-0b10885f1a36'),
      XiaozhiDeviceIdentity('02:53:05:01:49:13', '2a2be260-5406-4b09-bcd5-af1108b93315'),
      XiaozhiDeviceIdentity('02:53:05:02:49:13', 'ce0fca3b-8bed-43b8-b091-0055361592bc'),
      XiaozhiDeviceIdentity('02:53:05:03:49:13', '7f20ee92-6742-4b1e-9305-e27910bb8137'),
      XiaozhiDeviceIdentity('02:53:05:04:49:13', '6a310f98-20f7-4386-a183-90c63dcc1421'),
      XiaozhiDeviceIdentity('02:53:05:05:49:13', '467b6648-eaca-4bee-bba3-f7548dfb2000'),
    ],
    'gia_su_vat_ly': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0f', 'cd2e94ed-b1e0-4d38-bf06-a06b024456ee'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0f', '1dffde5d-43e0-419e-80b6-3ffcd6f1c0d0'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0f', '67cfd0e8-e161-48f1-a5b0-c9a9d45350a6'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0f', '27d46629-469b-4e3f-8fe4-873cc4639a97'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0f', '57c00302-db71-4ed3-a18c-648c0559da45'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0f', '6072d5ef-3088-4b98-b5f4-ca5706416e1e'),
      XiaozhiDeviceIdentity('02:53:02:48:49:0f', 'aa0a41c0-3dd0-4904-90ad-300bac0f0863'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0f', 'a26d1504-d5ce-4f92-a110-c1a13a31f3ae'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0f', '9394cd92-45b9-44aa-98bb-9e4720742f8f'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0f', '2f64e55e-5de4-4f87-a356-154ab90e5a37'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0f', '1f61e898-ff07-459d-bd89-7d9d8c2fa571'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0f', '1ff56977-c22c-4c9b-927c-14efd128d990'),
      XiaozhiDeviceIdentity('02:53:03:48:49:0f', '8067c4c8-3818-495d-8894-aecdc6021b94'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0f', 'f55e8a46-732e-460c-a8cc-5afaca87fe9e'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0f', 'f7e0dc7f-a489-42d9-8125-62c4aa8896c0'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0f', 'ed4d15d8-8b19-455b-af34-dbd4c2b7a1be'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0f', 'db086061-5362-4796-b674-f1c18a2b0d48'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0f', '5c2e35a4-1a59-4b29-8939-dcd9751c0373'),
      XiaozhiDeviceIdentity('02:53:04:48:49:0f', '9c6d8e27-ed4f-41f5-a6a1-05755976b733'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0f', 'db50e44d-cfae-45a8-92f9-3846dbfbd6f4'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0f', 'ee57f6b0-7054-4766-9225-25fb64029e4f'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0f', '0a8241ee-d22b-43f8-b615-6c545fbecc80'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0f', 'de31c32b-bf83-4aad-8e47-6379ce19abff'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0f', '8e103d81-1963-4ce7-b5ad-963c2d4ed539'),
    ],
    'gia_su_hoa_hoc': [
      XiaozhiDeviceIdentity('02:53:01:48:49:18', '0df3cbbf-7e6f-4731-bb67-7cadad903439'),
      XiaozhiDeviceIdentity('02:53:02:48:49:18', '811ae0da-f5ea-4e32-9064-3da93b7261a6'),
      XiaozhiDeviceIdentity('02:53:03:48:49:18', '00209cf8-850f-469c-a40e-e08ca9d09959'),
      XiaozhiDeviceIdentity('02:53:04:48:49:18', '8da03d60-a085-4590-ac98-5d54853b589b'),
      XiaozhiDeviceIdentity('02:53:05:01:49:18', '7e2b3a97-65e1-4030-939a-e6013d92ef16'),
      XiaozhiDeviceIdentity('02:53:05:02:49:18', '8f282561-989e-4a57-9839-e91aefc1a286'),
      XiaozhiDeviceIdentity('02:53:05:03:49:18', '54f7c557-0a22-4e4c-b9f1-8212fc04e584'),
      XiaozhiDeviceIdentity('02:53:05:04:49:18', 'e7fc37e5-c18b-4b79-900d-f2621e55d892'),
      XiaozhiDeviceIdentity('02:53:05:05:49:18', 'b4746281-fcf4-4679-964d-ce69f453d22c'),
      XiaozhiDeviceIdentity('02:53:05:48:49:18', '157bcdf8-3877-47a9-bcdd-77fc08db9fae'),
      XiaozhiDeviceIdentity('02:53:06:48:49:18', '5bf15fb9-2e79-4b4c-9fa8-4e570df85914'),
      XiaozhiDeviceIdentity('02:53:07:48:49:18', 'a8746b6e-cb3b-46ea-abbe-d75552415d20'),
      XiaozhiDeviceIdentity('02:53:08:48:49:18', 'c5054b6c-5eb4-44ff-9bf6-67152fa0568d'),
      XiaozhiDeviceIdentity('02:53:50:48:49:18', '55b8e1f1-ed6d-4b17-9dd0-777fb5a96ce8'),
      XiaozhiDeviceIdentity('02:53:80:01:49:18', 'c30ec237-74af-4e6f-9863-4153a53c8a0a'),
      XiaozhiDeviceIdentity('02:53:88:48:49:18', '945414d9-12c0-49d0-9cb5-b07f2300b225'),
    ],
    'gia_su_sinh_hoc': [
      XiaozhiDeviceIdentity('02:53:01:48:49:19', 'd9fee051-ec2c-4b7d-99c2-26e37006c2e9'),
      XiaozhiDeviceIdentity('02:53:02:01:49:19', '2cd31b82-ffbb-4538-872b-a4177315e3c5'),
      XiaozhiDeviceIdentity('02:53:02:02:49:19', 'fbb44819-eed5-4d3b-85f6-226fc3aa0517'),
      XiaozhiDeviceIdentity('02:53:02:03:49:19', '496124b2-f589-483f-9d3b-ab3f1812acd8'),
      XiaozhiDeviceIdentity('02:53:02:04:49:19', '50ef9a39-5ebd-4d64-892b-2913765c704b'),
      XiaozhiDeviceIdentity('02:53:02:05:49:19', '67cdb0b3-8ef0-4130-baf7-44dc25e6bffc'),
      XiaozhiDeviceIdentity('02:53:03:01:49:19', '703437df-ae07-443f-a4b8-193eb6ce8a9d'),
      XiaozhiDeviceIdentity('02:53:03:02:49:19', '6bbe6546-c401-4eaa-b189-0231fbbe5426'),
      XiaozhiDeviceIdentity('02:53:03:03:49:19', '3fb660f0-92cc-4604-805b-7f25d25612b2'),
      XiaozhiDeviceIdentity('02:53:03:04:49:19', '43b4d07b-f49a-4fae-b76e-f4bb880e6db1'),
      XiaozhiDeviceIdentity('02:53:03:05:49:19', '176fce96-7571-486a-86d3-e859b229e328'),
      XiaozhiDeviceIdentity('02:53:04:01:49:19', 'd544ae33-a9a9-4b3a-ba4b-326249b1e06d'),
      XiaozhiDeviceIdentity('02:53:04:02:49:19', '8363ab26-8c8c-49b9-883e-0851bf0918eb'),
      XiaozhiDeviceIdentity('02:53:04:03:49:19', 'd0eeb311-c592-4028-b9f6-0bb876a501e8'),
      XiaozhiDeviceIdentity('02:53:04:04:49:19', 'c7a6aeb2-21d4-4236-ad0c-d9e68d00470d'),
      XiaozhiDeviceIdentity('02:53:04:05:49:19', '41b59a07-1085-46a6-b640-d89f788a3c44'),
      XiaozhiDeviceIdentity('02:53:05:01:49:19', '9e0af2d7-4ee2-4d59-9ac2-d2a09821a227'),
      XiaozhiDeviceIdentity('02:53:05:02:49:19', '5965feda-b966-459c-8297-9000de8bf835'),
      XiaozhiDeviceIdentity('02:53:05:03:49:19', 'fd42171d-0c54-4d65-944a-0494348ffc99'),
      XiaozhiDeviceIdentity('02:53:05:04:49:19', '1e000702-f8e9-47f0-99fc-23f9b9792d97'),
      XiaozhiDeviceIdentity('02:53:05:05:49:19', '574c1472-e8a9-45a0-89d9-78779974c3c1'),
      XiaozhiDeviceIdentity('02:53:06:01:49:19', 'e51359dc-65fe-4d21-a152-128b645eeda1'),
      XiaozhiDeviceIdentity('02:53:06:02:49:19', '8e1199fe-9ef2-4459-bdb7-2212b3f769b0'),
      XiaozhiDeviceIdentity('02:53:06:03:49:19', '6e3a44e5-1ea6-40d2-a409-7a9a28834081'),
    ],
    'gia_su_su_dia': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0a', '0f1476c8-234b-4ace-873a-eae58ec57628'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0a', '2ad92885-aef4-40bd-8ab8-4845383af845'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0a', 'ce63675a-cadb-4755-8f9d-395844a1729c'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0a', 'aae028f1-cd12-4976-a384-f293007ca03a'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0a', 'ac6f912c-1642-4ea0-992b-3dc65287ad83'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0a', 'a8c25834-96ba-4b9e-94f8-e432f7b26ee9'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0a', 'b87d01a7-5ffd-4e93-992d-9a2c07d8be9c'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0a', '911910e5-70e6-4a14-9655-90cf8aacc4c8'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0a', '8c69f1bb-12aa-4437-9619-3dadacb8215d'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0a', 'f0faac3a-8966-4923-86ed-7ba038080a1b'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0a', '7cd6ad61-632d-4055-874f-f0ad6a79c093'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0a', 'a420be7e-7d9c-41f1-86f6-812cf923f3c4'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0a', '320aec36-b994-47de-acb6-375ac9999e5b'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0a', '5c5945d8-9bce-4db9-8319-0a0ad8a3d45f'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0a', '495266e3-eaa8-4574-b499-105164b485ea'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0a', 'a99d1fb6-3c35-493d-b846-4c253daf9125'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0a', 'd386b902-4905-4a9b-b144-b4533a30be14'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0a', 'f3b14b92-3152-45db-bae5-6b5d4c920442'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0a', '3ff47988-d50d-438b-a898-2c7b8d30e547'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0a', 'c138f597-48e1-4e37-be3a-a5f612f64731'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0a', 'ed5f65e9-55a8-4e0e-89d3-5ab32794bc3a'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0a', '15b4ab31-99a8-4f78-9f95-dfcec141ad49'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0a', 'ee9c6fa3-bdc3-4c65-8377-b7afd346168e'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0a', '8a5c875f-3b39-4261-be51-0bbb6a22141e'),
    ],
    'gia_su_tin_hoc': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0d', '947cef6d-a5a2-47be-9744-ada83bbbc74d'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0d', '72b83e63-1009-477e-88c3-2449cc5209cb'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0d', '2923aac0-07e7-44a2-a0ae-67f6c2d815ec'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0d', 'bfe50617-f358-4657-baeb-580584d66825'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0d', '4ce6b439-3470-4c99-a5c7-f5a50c4c30bf'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0d', '59180d9b-7245-42a0-a845-2f7e8b60ae28'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0d', '43adc864-aed4-4f45-92e5-f7fa4be75441'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0d', '584bb900-8918-44b1-8e64-165bed3d49a3'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0d', '398c182e-f8cc-4bb3-882b-2d4b149c982a'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0d', 'fecb2bdb-bbf5-417e-8f65-af4c88dad4d3'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0d', '1c27a687-3b3a-411e-be89-b402399d4654'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0d', 'ebed3ac8-a22a-4282-aa65-bfb6fd9df5b5'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0d', '83fed05a-ffa0-47f4-bb5e-ee154e559141'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0d', '2d097782-913b-4cca-b11f-0bfcecf3b9e6'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0d', '05db7c63-1ea1-4675-872a-1200744c8fd9'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0d', '1b69bf3d-4dbb-4c13-ba63-8c5eb09874d6'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0d', '2933d702-abb5-49cb-b43f-e434bd93a67f'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0d', '91bac3dd-f40e-41d3-a8d8-b97a86bd2dd7'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0d', '0865c76c-e868-432e-b28a-a86fe3c63a80'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0d', '11a21c03-8d83-4f02-bb07-cf9b13e99079'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0d', '7bf5e133-6271-4a22-96aa-5c64d4b85c1e'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0d', '7ac3fc2c-e7ef-407d-a7b8-3f28dc7d6612'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0d', '41e85d97-598e-46a9-8f0b-73340996b0ca'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0d', 'a93749a2-9e16-49ab-bdde-4dbd812bbacc'),
    ],
    'gia_su_tieng_trung': [
      XiaozhiDeviceIdentity('02:53:04:02:49:15', '0b8a96cc-52d2-4026-b9d6-616a0f389445'),
      XiaozhiDeviceIdentity('02:53:04:03:49:15', '25b84c7f-ec4a-4494-9dbc-1f9bbcf3bd01'),
      XiaozhiDeviceIdentity('02:53:04:04:49:15', 'ee7c61db-9d89-4fd4-9d34-0dcfd5a27f86'),
      XiaozhiDeviceIdentity('02:53:04:05:49:15', '0b50f96e-5ac4-44ac-a47c-4b9619f25776'),
      XiaozhiDeviceIdentity('02:53:04:06:49:15', '688f13f0-72c9-44f3-bd38-2c69de3be58a'),
      XiaozhiDeviceIdentity('02:53:04:07:49:15', 'c062652e-3ad4-42ac-b6ed-ef87b2098e6d'),
      XiaozhiDeviceIdentity('02:53:04:08:49:15', 'e19ca42b-14be-4719-9a0e-bf654bb43bbb'),
      XiaozhiDeviceIdentity('02:53:04:09:49:15', '6bb5fbd7-f7b0-4690-a6b6-10927fe8c998'),
      XiaozhiDeviceIdentity('02:53:04:0a:49:15', '9c6ff788-9d84-469f-afd4-9199e854dddd'),
      XiaozhiDeviceIdentity('02:53:04:48:49:15', '76122225-b9e7-427a-b45e-9cd4486c7b21'),
      XiaozhiDeviceIdentity('02:53:05:01:49:15', '6bf51904-abf6-4e00-9ed5-449e1f5977ac'),
      XiaozhiDeviceIdentity('02:53:05:02:49:15', 'ed93964e-d2f5-4ee2-a7c7-8f770f7e1417'),
      XiaozhiDeviceIdentity('02:53:05:03:49:15', '11a4577f-7bb8-451f-91e1-9c3dcd7c6c58'),
      XiaozhiDeviceIdentity('02:53:05:04:49:15', 'aeb33952-9e3b-41f2-be6a-57e784ba34e9'),
      XiaozhiDeviceIdentity('02:53:05:05:49:15', 'f5d5868d-023c-4175-b40b-1087431b3720'),
      XiaozhiDeviceIdentity('02:53:05:48:49:15', '01d3150d-bdfd-48d0-8851-2ac2f63866a6'),
      XiaozhiDeviceIdentity('02:53:06:01:49:15', '8bd2d0c6-a0b7-46a7-89f2-eb9dec336e75'),
      XiaozhiDeviceIdentity('02:53:06:02:49:15', '621b1b53-3f47-4971-9316-ba854b587603'),
      XiaozhiDeviceIdentity('02:53:06:03:49:15', '3bce36a9-b2eb-42d0-b9bd-2d3fa68ea339'),
      XiaozhiDeviceIdentity('02:53:06:04:49:15', 'd128590e-03b6-4b14-8b87-146f947aec3a'),
    ],
    'gia_su_tieng_nhat': [
      XiaozhiDeviceIdentity('02:53:06:05:49:15', 'b63f8ee2-bc2c-4157-8360-329e6d23e3e5'),
      XiaozhiDeviceIdentity('02:53:06:06:49:15', '2760aa01-023e-4897-9993-c665f7fe47c0'),
      XiaozhiDeviceIdentity('02:53:06:07:49:15', 'b4a24d20-7b67-40dd-b819-9358ef7f294c'),
      XiaozhiDeviceIdentity('02:53:06:08:49:15', 'ba7e16f5-69c0-49a4-a1d8-399609bcd316'),
      XiaozhiDeviceIdentity('02:53:06:09:49:15', 'f4e88ab6-11b2-4478-8746-5ab20ddfaecd'),
      XiaozhiDeviceIdentity('02:53:06:0a:49:15', '0870e7ff-c2eb-472e-9bef-c14b29195a53'),
      XiaozhiDeviceIdentity('02:53:06:48:49:15', '326ce654-166b-4103-86c4-3b0cf9956035'),
      XiaozhiDeviceIdentity('02:53:07:01:49:15', 'fe859565-f397-4838-b1a6-158efe62abdb'),
      XiaozhiDeviceIdentity('02:53:07:02:49:15', '9285b2ce-1b54-4d91-9cef-4850e65becb1'),
      XiaozhiDeviceIdentity('02:53:07:03:49:15', '7eb1359a-6292-4b0e-bfce-5407b1f82fc5'),
      XiaozhiDeviceIdentity('02:53:07:04:49:15', 'd820e1b0-8314-4e08-ae5e-a40b9a2da80e'),
      XiaozhiDeviceIdentity('02:53:07:05:49:15', '45c21760-5720-4401-ae9b-596f1fd1ca04'),
      XiaozhiDeviceIdentity('02:53:07:06:49:15', '08125a66-82bb-4a5a-b048-f0f7d693d83a'),
      XiaozhiDeviceIdentity('02:53:07:07:49:15', '1309cd41-53ff-4b99-ae38-64187d24b7ad'),
      XiaozhiDeviceIdentity('02:53:07:08:49:15', 'b000d8e8-f71b-4a06-9450-3e888d46f7da'),
      XiaozhiDeviceIdentity('02:53:07:09:49:15', '0ab37b50-4443-4190-96a7-75b5a6913e7d'),
      XiaozhiDeviceIdentity('02:53:07:0a:49:15', '4169e89c-e0b4-4f08-8008-6712e5965eb8'),
      XiaozhiDeviceIdentity('02:53:07:48:49:15', '38918352-efa6-490b-a50b-316f43aafedc'),
      XiaozhiDeviceIdentity('02:53:08:01:49:15', '83816620-f576-49c5-ae48-a3346c636021'),
      XiaozhiDeviceIdentity('02:53:08:02:49:15', '249b494c-e42f-4df8-bff7-2dc23bbc6328'),
    ],
    'gia_su_tieng_han': [
      XiaozhiDeviceIdentity('02:53:08:03:49:15', '47b1a563-bf06-4550-9f97-4c641134ee69'),
      XiaozhiDeviceIdentity('02:53:08:04:49:15', '906adacd-35bb-4b56-8358-5009ae90eef4'),
      XiaozhiDeviceIdentity('02:53:08:05:49:15', 'b0d11759-8fc4-4b82-8cbc-81a5ce1c7bda'),
      XiaozhiDeviceIdentity('02:53:08:06:49:15', 'e0d8dd80-5f0d-4a83-8c1c-a50c64765eac'),
      XiaozhiDeviceIdentity('02:53:08:07:49:15', 'e75319d2-54d9-4137-b6a6-414f85c8310a'),
      XiaozhiDeviceIdentity('02:53:08:08:49:15', '7a6223a2-0c42-4ae5-8b74-3c8fa47a4520'),
      XiaozhiDeviceIdentity('02:53:08:09:49:15', '6ce272f1-539d-4ea7-98e0-1730ed156e9f'),
      XiaozhiDeviceIdentity('02:53:08:0a:49:15', '67cb79b0-6088-4021-a9e5-4edf890d7ce5'),
      XiaozhiDeviceIdentity('02:53:08:48:49:15', 'f26ca5da-6be9-496d-ae0f-9eea3a977e0a'),
      XiaozhiDeviceIdentity('02:53:09:01:49:15', 'a53587c4-77ef-40af-b46d-a3ff18fec0a9'),
      XiaozhiDeviceIdentity('02:53:09:02:49:15', 'c67a3a9e-a372-4a27-8334-843358b8267a'),
      XiaozhiDeviceIdentity('02:53:09:03:49:15', 'dd8cff59-cfb7-45d9-9327-4bb2f859dc80'),
      XiaozhiDeviceIdentity('02:53:09:04:49:15', '44e4554d-e0b7-4a8b-8f99-40eb1be0b74a'),
      XiaozhiDeviceIdentity('02:53:09:05:49:15', '3adee460-75c8-462c-9da3-650a3fe1e7cf'),
      XiaozhiDeviceIdentity('02:53:09:06:49:15', '563c505f-26ca-46a7-9fc6-7a0fdf4e04ea'),
      XiaozhiDeviceIdentity('02:53:09:07:49:15', '4cf1f0ae-4128-4ab5-837d-f923b9cbba72'),
      XiaozhiDeviceIdentity('02:53:09:08:49:15', '51a2bc31-426b-4399-b0e9-5b958958944b'),
      XiaozhiDeviceIdentity('02:53:09:09:49:15', '3dafaa24-48b5-4ae6-8c52-632015d1cab1'),
      XiaozhiDeviceIdentity('02:53:09:0a:49:15', 'adb23cf1-3ea8-4e45-9e03-d5183565b387'),
      XiaozhiDeviceIdentity('02:53:50:48:49:15', 'a55bd257-742a-4209-a9d0-4b3597b44bfb'),
    ],
    'ke_chuyen': [
      XiaozhiDeviceIdentity('02:53:01:48:49:12', 'bc054436-c886-461f-b135-cd510e49da38'),
      XiaozhiDeviceIdentity('02:53:02:01:49:12', '5e950c4c-1671-4f9d-97e1-b6ae2f9e5586'),
      XiaozhiDeviceIdentity('02:53:02:02:49:12', 'a2da35c0-aba6-4fc1-adee-bd076f75797c'),
      XiaozhiDeviceIdentity('02:53:02:03:49:12', '8e7e23c8-bcd2-4ca0-9736-996c8febf9a1'),
      XiaozhiDeviceIdentity('02:53:02:04:49:12', '30811fd3-2d6c-4e0f-8672-9f4f5bbeacf1'),
      XiaozhiDeviceIdentity('02:53:02:48:49:12', 'aff5b918-42bf-43aa-a1a9-11e06f24c51f'),
      XiaozhiDeviceIdentity('02:53:03:01:49:12', '6e7e7ddd-a317-4943-8b75-ec2be9346ab6'),
      XiaozhiDeviceIdentity('02:53:03:02:49:12', 'f993db31-33c2-4980-83a2-2a7f1fc90bc2'),
      XiaozhiDeviceIdentity('02:53:03:03:49:12', 'd5b140db-e6f7-43b7-b1a7-98acfb1261a7'),
      XiaozhiDeviceIdentity('02:53:03:04:49:12', 'dcdec8ff-11c2-4539-9d38-1d3423a52473'),
      XiaozhiDeviceIdentity('02:53:03:05:49:12', '052aff45-1661-4230-9adb-e58bdad42cef'),
      XiaozhiDeviceIdentity('02:53:03:48:49:12', '74192fe8-3b86-4775-b507-eec44bf5f3db'),
      XiaozhiDeviceIdentity('02:53:04:01:49:12', '3f68c36d-774b-4fc1-97dc-a40edf276f8e'),
      XiaozhiDeviceIdentity('02:53:04:02:49:12', 'dc7cc217-93d4-48f8-908f-8128e938cf83'),
      XiaozhiDeviceIdentity('02:53:04:03:49:12', '5cfbc123-6e63-43a8-ab15-4a4dc7767a31'),
      XiaozhiDeviceIdentity('02:53:04:04:49:12', 'eb26d9f7-1a91-4bec-a933-40cce3ffe63d'),
      XiaozhiDeviceIdentity('02:53:04:05:49:12', '5cb42ef1-30f4-4bce-880f-1bface0051a6'),
      XiaozhiDeviceIdentity('02:53:04:48:49:12', 'bfc3359e-39c6-4597-8185-c8843b7e43c6'),
      XiaozhiDeviceIdentity('02:53:05:01:49:12', '87897e1c-e2b3-438a-a8c4-7345bef47132'),
      XiaozhiDeviceIdentity('02:53:05:02:49:12', '14c86f3a-aa64-4852-9ab8-fd2a63d1d37e'),
      XiaozhiDeviceIdentity('02:53:05:03:49:12', 'a16e6eff-c1c8-4e5c-8fe8-adc73198daa4'),
      XiaozhiDeviceIdentity('02:53:05:04:49:12', 'af4aa330-8fc4-41c2-a9fd-58f6af941ca3'),
      XiaozhiDeviceIdentity('02:53:05:05:49:12', '59eb0e46-5036-4d0f-9471-bea832920572'),
      XiaozhiDeviceIdentity('02:53:05:48:49:12', '6757da95-cda9-49df-8107-e66864f06f23'),
    ],
    'bac_si_tuan': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0c', 'b79b0a58-695a-4abc-b564-5537fc51535e'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0c', 'c9ae5a47-2376-4943-802d-ed0c2123c956'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0c', 'eebf1b6c-e2f0-471c-8967-f6638f702ccf'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0c', '04e39f60-d039-47ac-b065-c65d95ae3c38'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0c', '3d6dbf02-4e52-4ac3-8fa3-afe7af86693a'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0c', '5e0062ea-32e7-4d83-b864-c2c67b82a3b8'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0c', '393a2209-cb85-4a99-bee7-d7f8b47873af'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0c', '952ac1e0-fa0b-40dd-a6b0-6ad0806c4ee4'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0c', '3f0e685d-3cbd-4ceb-abe1-d4d2bb2e67b5'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0c', '551ec619-ffd6-4b3c-92f9-714a07b2466f'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0c', 'f636877d-62e3-4266-b1c2-e0ef30929ab5'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0c', '1f897608-ada8-49a5-8a9e-745e11ab30bf'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0c', 'e0e9e760-6730-4222-a1cf-3c5aac86d8e9'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0c', '493c157b-8fb5-446b-a5ba-8f6857d88a62'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0c', 'f5606c77-29c1-4d06-9c53-b249915e4c21'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0c', '061815d8-28eb-4c15-992b-1f35b575cdf2'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0c', 'a0da7b54-2e24-46cc-a7d1-8f87b504e760'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0c', 'e70310c2-7d12-4574-97a1-100f74da0623'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0c', 'ac0d7d29-9d43-4c04-a485-a93bf3d8877f'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0c', '2cdc86dd-7b2a-462e-9715-da64a91aa6eb'),
    ],
    'chuyen_gia_tam_ly': [
      XiaozhiDeviceIdentity('02:53:05:05:49:0c', '88891b08-ba5e-4120-abc1-c5c2ca1b2341'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0c', 'b156e26a-00ab-4896-b9f1-ffc6a5ef1af6'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0c', 'd4b5e016-3bdd-4786-9c2c-03b6b50cfeed'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0c', '003926d4-0168-42f6-baa9-97417ba82611'),
      XiaozhiDeviceIdentity('02:53:06:04:49:0c', 'eece3f22-4ff7-4849-9459-e6266164a4bf'),
      XiaozhiDeviceIdentity('02:53:06:05:49:0c', 'c52b5eb3-f8ec-4021-a85a-b8e5dbadaa2f'),
      XiaozhiDeviceIdentity('02:53:07:01:49:0c', 'b84d7749-0e21-41a4-910c-2a54c8708a14'),
      XiaozhiDeviceIdentity('02:53:07:02:49:0c', '8f38f0a7-df82-41be-8c6c-d7ca15f19de5'),
      XiaozhiDeviceIdentity('02:53:07:03:49:0c', '3d166085-1259-43a0-8945-695dab696c4a'),
      XiaozhiDeviceIdentity('02:53:07:04:49:0c', '6a1000bf-346e-45d0-bb5f-db59c4494efc'),
      XiaozhiDeviceIdentity('02:53:07:05:49:0c', '79aa8b91-6d80-4205-b9db-64623b782801'),
      XiaozhiDeviceIdentity('02:53:08:01:49:0c', 'dd3905e1-feb2-49f7-ac1f-ae11420c4aaa'),
      XiaozhiDeviceIdentity('02:53:08:02:49:0c', '215f1423-1c25-4e1c-8139-bd257d535af6'),
      XiaozhiDeviceIdentity('02:53:08:03:49:0c', '0acf2265-3a0f-4148-b2f2-092182abec1f'),
      XiaozhiDeviceIdentity('02:53:08:04:49:0c', '042a6454-89b8-482a-bc06-b82f39f5e45f'),
      XiaozhiDeviceIdentity('02:53:08:05:49:0c', 'd193a6cf-ab14-4ea7-b866-fa39162a9b1c'),
      XiaozhiDeviceIdentity('02:53:50:48:49:0c', '0754d47d-713d-4d51-a745-e3bb6c9143e2'),
      XiaozhiDeviceIdentity('02:53:80:01:49:0c', '94b9dc56-0694-4afb-b885-1aa8f4ead1c1'),
      XiaozhiDeviceIdentity('02:53:88:48:49:0c', '0c183192-9198-4176-8638-f8a6d728b411'),
    ],
    'ban_dong_hanh': [
      XiaozhiDeviceIdentity('02:53:01:48:49:0b', 'ac67201f-c98c-4027-83fd-ddcdb91ead81'),
      XiaozhiDeviceIdentity('02:53:02:01:49:0b', 'a52f1f8d-e10b-4e38-89d3-73a2078a9d6c'),
      XiaozhiDeviceIdentity('02:53:02:02:49:0b', 'd256b6d4-4e94-45ba-8bf5-87ded12d6dd0'),
      XiaozhiDeviceIdentity('02:53:02:03:49:0b', '6e004047-602a-4cbb-9af0-05f0e8131e03'),
      XiaozhiDeviceIdentity('02:53:02:04:49:0b', 'ef0e6399-30ba-4d4f-b433-d534e9106a73'),
      XiaozhiDeviceIdentity('02:53:02:05:49:0b', '1e380b26-f42a-4a12-9f0b-6a3778a66ca6'),
      XiaozhiDeviceIdentity('02:53:03:01:49:0b', 'd57b8240-956b-4e40-9123-68938c180023'),
      XiaozhiDeviceIdentity('02:53:03:02:49:0b', '09566645-c0ef-44e2-a376-73aae0ecc845'),
      XiaozhiDeviceIdentity('02:53:03:03:49:0b', 'dbe4dcfe-011f-401e-90ed-0a85ff68f5bf'),
      XiaozhiDeviceIdentity('02:53:03:04:49:0b', 'e72543ce-204f-4c0a-be2e-69d2fe4d3104'),
      XiaozhiDeviceIdentity('02:53:03:05:49:0b', '8818fb44-e9c1-4f7f-87ae-813b9eccb5fc'),
      XiaozhiDeviceIdentity('02:53:04:01:49:0b', 'fd9526f6-477b-4107-96b9-c4b26da8add2'),
      XiaozhiDeviceIdentity('02:53:04:02:49:0b', 'a5a2a0e0-62b8-4def-a0c0-e05a3edab401'),
      XiaozhiDeviceIdentity('02:53:04:03:49:0b', '5506baff-dd3b-4e78-bca5-11a20389c5d6'),
      XiaozhiDeviceIdentity('02:53:04:04:49:0b', '49f41b9d-83c1-4120-8fba-e82cdbd97466'),
      XiaozhiDeviceIdentity('02:53:04:05:49:0b', '417a8ff9-16e5-4f77-ba22-fcb3be0810d5'),
      XiaozhiDeviceIdentity('02:53:05:01:49:0b', '834a87c4-a5a6-41d1-8335-7d1476b01539'),
      XiaozhiDeviceIdentity('02:53:05:02:49:0b', '5400d939-7162-40c1-8d88-6a0c597a16fc'),
      XiaozhiDeviceIdentity('02:53:05:03:49:0b', 'd06c41a6-49e5-4ad1-b4a4-acec5715c147'),
      XiaozhiDeviceIdentity('02:53:05:04:49:0b', 'b11566d8-6c38-47b6-b9ea-a5ee39bd6d31'),
      XiaozhiDeviceIdentity('02:53:05:05:49:0b', 'e6154f94-c889-4ba9-b537-564c40f14776'),
      XiaozhiDeviceIdentity('02:53:06:01:49:0b', '75d4dfcb-6317-4936-bcd9-16f04766b42e'),
      XiaozhiDeviceIdentity('02:53:06:02:49:0b', '49650dad-4ebc-41de-b4ff-6067e1119dce'),
      XiaozhiDeviceIdentity('02:53:06:03:49:0b', '12663b8d-f837-493b-8ffc-35e7adb6c54e'),
    ],
    'ban_tam_su': [
      XiaozhiDeviceIdentity('02:53:01:48:49:11', '4bba8732-8901-43f9-9d31-a8915aeed168'),
      XiaozhiDeviceIdentity('02:53:02:01:49:11', 'eaa770d1-f70d-4b38-a24c-822f9b75f78d'),
      XiaozhiDeviceIdentity('02:53:02:02:49:11', '68c6f027-bf59-4792-9abf-0f8e235b5228'),
      XiaozhiDeviceIdentity('02:53:02:03:49:11', '5a74dd5b-2d9c-4fdb-b800-cc039bf26f83'),
      XiaozhiDeviceIdentity('02:53:02:04:49:11', 'f08d6da3-dde8-4b25-9747-b3938fccb18a'),
      XiaozhiDeviceIdentity('02:53:02:05:49:11', '8b65c19f-a612-44f9-bf27-ac944b618927'),
      XiaozhiDeviceIdentity('02:53:02:48:49:11', 'e147aff6-49de-4ef5-9e6d-5eb051d623a2'),
      XiaozhiDeviceIdentity('02:53:03:01:49:11', '49cc97dc-41fc-4459-869b-434f6460dc06'),
      XiaozhiDeviceIdentity('02:53:03:02:49:11', 'eed40374-1eba-4f76-9d34-a6c78f6dddcd'),
      XiaozhiDeviceIdentity('02:53:03:03:49:11', '293ee0fd-96fa-48b3-8121-73a2680ff87c'),
      XiaozhiDeviceIdentity('02:53:03:04:49:11', 'd691995f-c68a-4f54-a628-1f767b510ab6'),
      XiaozhiDeviceIdentity('02:53:03:05:49:11', '71b98334-f6ad-4792-a6ac-b607a79df272'),
      XiaozhiDeviceIdentity('02:53:03:48:49:11', 'eee28153-479f-4879-9a85-3c3ed9dec700'),
      XiaozhiDeviceIdentity('02:53:04:01:49:11', '61ae6fbe-5a1c-4dda-af60-85c314740af8'),
      XiaozhiDeviceIdentity('02:53:04:02:49:11', '1fc99205-b81c-40af-96a4-77331afb30a9'),
      XiaozhiDeviceIdentity('02:53:04:03:49:11', '77eaa19a-6cc1-481b-8a97-4749180f299a'),
      XiaozhiDeviceIdentity('02:53:01:48:49:1b', '9f2eeb1e-e5cc-41b9-9c25-ec655044f412'),
      XiaozhiDeviceIdentity('02:53:02:01:49:1b', '325cfd1a-adde-439a-b63b-94260b535335'),
      XiaozhiDeviceIdentity('02:53:02:02:49:1b', '090c3158-a791-478e-b967-f59b6297a214'),
      XiaozhiDeviceIdentity('02:53:02:03:49:1b', 'a2afe48b-0139-4207-a4da-93497b0f3c88'),
      XiaozhiDeviceIdentity('02:53:02:04:49:1b', '27883b0c-614e-4f49-9154-d96f99cae197'),
      XiaozhiDeviceIdentity('02:53:02:05:49:1b', '55a27f93-e7fe-422c-88af-850a483a5e68'),
      XiaozhiDeviceIdentity('02:53:03:01:49:1b', '59affa41-bb16-472b-a3fc-d6b474028636'),
      XiaozhiDeviceIdentity('02:53:03:02:49:1b', 'b657a745-5742-41cd-9fd9-b9ac731af689'),
    ],
  };

  String _poolIndexKey(String profileId) => 'mina_pool_idx_v5_$profileId';
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
