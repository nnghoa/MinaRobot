import 'package:flutter/material.dart';

import '../models/assistant_profile.dart';
import '../models/robonova_actions.dart';
import '../services/mina_platform.dart';
import '../services/xiaozhi_session_service.dart';
import 'mina_settings_screen.dart';

/// Màn hình ứng dụng của Launcher: chọn trợ lý, điều khiển Visbot, điều khiển Võ/Múa Bluetooth, radio, YouTube, trình duyệt, cài đặt.
class LauncherMenuScreen extends StatelessWidget {
  final MinaBrainController brain;

  const LauncherMenuScreen({super.key, required this.brain});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Tile>[
      for (final a in AssistantCatalog.all)
        _Tile(a.icon, a.name, a.color, () async {
          Navigator.of(context).pop();
          await brain.switchAssistant(a.id, startTalking: true);
        }, selected: a.id == brain.activeAssistant.id),
      _Tile(Icons.sports_martial_arts_rounded, 'Võ/Múa BT', const Color(0xFFFF6B35),
          () => _showHumanoidBluetoothControl(context)),
      _Tile(Icons.gamepad_rounded, 'Đ.Khiển Xe', const Color(0xFFF59E0B),
          () => _showRobotControl(context)),
      _Tile(Icons.radio_rounded, 'Radio', const Color(0xFF00F5A0), () => _showRadio(context)),
      _Tile(Icons.library_music_rounded, 'Zing MP3', const Color(0xFFA855F7), () async {
        await MinaPlatform.mediaStop();
        await MinaPlatform.openZingMp3();
      }),
      _Tile(Icons.smart_display_rounded, 'YouTube', const Color(0xFFFF4D4D), () async {
        await MinaPlatform.mediaStop();
        await MinaPlatform.openYoutube();
      }),
      _Tile(Icons.bedtime_rounded, 'Tắt màn hình', const Color(0xFF38BDF8), () {
        Navigator.of(context).pop();
        MinaPlatform.setScreenBlackout(true);
      }),
      _Tile(Icons.public_rounded, 'Trình duyệt', const Color(0xFF60A5FA),
          () => MinaPlatform.openBrowser('https://www.google.com')),
      _Tile(Icons.wifi_rounded, 'Wi-Fi', Colors.white70, MinaPlatform.openWifiSettings),
      _Tile(Icons.bluetooth_rounded, 'Bluetooth', const Color(0xFF38BDF8),
          MinaPlatform.openBluetoothSettings),
      _Tile(Icons.tune_rounded, 'Cài đặt Mina', Colors.white70, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => MinaSettingsScreen(brain: brain)),
        );
      }),
      _Tile(Icons.settings_rounded, 'Android', Colors.white38, MinaPlatform.openSystemSettings),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text('Mina Menu', style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.18,
                children: tiles.map((t) => _TileView(t)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRadio(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final s in RadioCatalog.all)
            ListTile(
              dense: true,
              leading: const Icon(Icons.radio_rounded, color: Color(0xFF00F5A0)),
              title: Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () {
                MinaPlatform.mediaPlay(s.url, title: s.name);
                Navigator.of(ctx).pop();
              },
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.stop_rounded, color: Colors.redAccent),
            title: const Text('Tắt radio', style: TextStyle(color: Colors.white70, fontSize: 13)),
            onTap: () {
              MinaPlatform.mediaStop();
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showRobotControl(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Điều khiển bánh xe & đầu Visbot',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _ctrlBtn('⬆ Tiến', const Color(0xFF10B981), () => MinaPlatform.robotMove('forward')),
                _ctrlBtn('⬇ Lùi', const Color(0xFF10B981), () => MinaPlatform.robotMove('backward')),
                _ctrlBtn('⬅ Trái', const Color(0xFF3B82F6),
                    () => MinaPlatform.robotMove('turn_left', durationMs: 900)),
                _ctrlBtn('➡ Phải', const Color(0xFF3B82F6),
                    () => MinaPlatform.robotMove('turn_right', durationMs: 900)),
                _ctrlBtn('⏹ Dừng', const Color(0xFFEF4444), () => MinaPlatform.robotStop()),
                _ctrlBtn('Ngẩng', const Color(0xFFF59E0B), () => MinaPlatform.robotHead('up')),
                _ctrlBtn('Thẳng', const Color(0xFFF59E0B), () => MinaPlatform.robotHead('center')),
                _ctrlBtn('Cúi', const Color(0xFFF59E0B), () => MinaPlatform.robotHead('down')),
                _ctrlBtn('Gật đầu', const Color(0xFFA855F7), () => MinaPlatform.robotHead('nod')),
                _ctrlBtn('Nhảy múa', const Color(0xFFEC4899), () => MinaPlatform.robotDance()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHumanoidBluetoothControl(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: _HumanoidBluetoothSheet(),
      ),
    );
  }

  static Widget _ctrlBtn(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.25),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          textStyle: const TextStyle(fontSize: 11),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}

class _HumanoidBluetoothSheet extends StatefulWidget {
  const _HumanoidBluetoothSheet();

  @override
  State<_HumanoidBluetoothSheet> createState() => _HumanoidBluetoothSheetState();
}

class _HumanoidBluetoothSheetState extends State<_HumanoidBluetoothSheet> {
  bool _connected = false;
  bool _busy = false;
  String _statusMsg = 'Đang kiểm tra Bluetooth...';
  List<Map<String, dynamic>> _devices = const [];

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final st = await MinaPlatform.btStatus();
    if (!mounted) return;
    setState(() {
      _connected = st['connected'] == true;
      _statusMsg = (st['message'] ?? '').toString();
      final rawList = st['devices'];
      if (rawList is List) {
        _devices = rawList
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    });
  }

  Future<void> _autoConnect({String? address}) async {
    setState(() {
      _busy = true;
      _statusMsg = 'Đang kết nối Bluetooth HC-06...';
    });
    final res = await MinaPlatform.btConnect(address: address);
    await _refreshStatus();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMsg = (res['message'] ?? _statusMsg).toString();
    });
  }

  Future<void> _scanBt() async {
    setState(() {
      _busy = true;
      _statusMsg = 'Đang quét tìm thiết bị HC-06 (4.5s)...';
    });
    await MinaPlatform.btScan(durationMs: 4500);
    await _refreshStatus();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _runQuery(String query) async {
    final msg = await MinaPlatform.performRobonova(query);
    if (!mounted) return;
    setState(() => _statusMsg = msg);
    _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh trạng thái Bluetooth + nút kết nối nhanh
          Row(
            children: [
              Icon(
                _connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_searching_rounded,
                color: _connected ? const Color(0xFF00F5A0) : const Color(0xFF38BDF8),
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _statusMsg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _connected ? const Color(0xFF00F5A0) : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              LauncherMenuScreen._ctrlBtn(
                _busy ? '...' : (_connected ? 'Kết nối lại' : 'Kết nối HC-06'),
                const Color(0xFF0EA5E9),
                _busy ? () {} : () => _autoConnect(),
              ),
              const SizedBox(width: 4),
              LauncherMenuScreen._ctrlBtn(
                'Quét',
                const Color(0xFF6366F1),
                _busy ? () {} : _scanBt,
              ),
              const SizedBox(width: 4),
              LauncherMenuScreen._ctrlBtn(
                'Cài đặt BT',
                const Color(0xFF64748B),
                MinaPlatform.openBluetoothSettings,
              ),
            ],
          ),
          if (_devices.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (_, idx) {
                  final d = _devices[idx];
                  final name = (d['name'] ?? 'BT').toString();
                  final addr = (d['address'] ?? '').toString();
                  final isConn = d['connected'] == true;
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    backgroundColor: isConn
                        ? const Color(0xFF00F5A0).withOpacity(0.25)
                        : Colors.white.withOpacity(0.08),
                    label: Text(
                      '$name ($addr)',
                      style: const TextStyle(color: Colors.white, fontSize: 9.5),
                    ),
                    onPressed: _busy ? null : () => _autoConnect(address: addr),
                  );
                },
              ),
            ),
          ],
          const Divider(color: Colors.white12, height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔥 BÀI BIỂU DIỄN LIÊN HOÀN (COMBO)',
                    style: TextStyle(color: Color(0xFFFF9F1C), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      LauncherMenuScreen._ctrlBtn('🥋 Liên hoàn Quyền', const Color(0xFFFF6B35),
                          () => _runQuery('kungfu_show')),
                      LauncherMenuScreen._ctrlBtn('💃 Liên hoàn Nhảy', const Color(0xFFEC4899),
                          () => _runQuery('dance_show')),
                      LauncherMenuScreen._ctrlBtn('🤸 Nhào lộn & Chuối', const Color(0xFFA855F7),
                          () => _runQuery('acrobatics_show')),
                      LauncherMenuScreen._ctrlBtn('💪 Thể lực Nhạc', const Color(0xFF10B981),
                          () => _runQuery('fitness_show')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '🥋 QUYỀN THUẬT & VÕ CÔNG (K42..K54)',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final a in RobonovaActionCatalog.byCategory(RobonovaCategory.martialArts))
                        LauncherMenuScreen._ctrlBtn(
                          '${a.id} ${a.nameVi}',
                          const Color(0xFFEF4444),
                          () => _runQuery(a.slug),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '💃 NHẢY MÚA, NHÀO LỘN & THỂ LỰC',
                    style: TextStyle(color: Color(0xFFEC4899), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final a in RobonovaActionCatalog.byCategory(RobonovaCategory.danceAcrobatics))
                        LauncherMenuScreen._ctrlBtn(
                          '${a.id} ${a.nameVi}',
                          const Color(0xFFEC4899),
                          () => _runQuery(a.slug),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '👋 CHÀO HỎI & GIAO TIẾP',
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final a in RobonovaActionCatalog.byCategory(RobonovaCategory.greeting))
                        LauncherMenuScreen._ctrlBtn(
                          '${a.id} ${a.nameVi}',
                          const Color(0xFF00E5FF),
                          () => _runQuery(a.slug),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '🚶 DI CHUYỂN & TƯ THẾ',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final a in [
                        ...RobonovaActionCatalog.byCategory(RobonovaCategory.walking),
                        ...RobonovaActionCatalog.byCategory(RobonovaCategory.postureRecovery),
                      ])
                        LauncherMenuScreen._ctrlBtn(
                          '${a.id} ${a.nameVi}',
                          const Color(0xFF10B981),
                          () => _runQuery(a.slug),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;

  _Tile(this.icon, this.label, this.color, this.onTap, {this.selected = false});
}

class _TileView extends StatelessWidget {
  final _Tile t;

  const _TileView(this.t);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.selected ? t.color.withOpacity(0.22) : Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: t.onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(t.icon, color: t.color, size: 26),
              const SizedBox(height: 3),
              Text(
                t.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10.5, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
