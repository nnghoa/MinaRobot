import 'package:flutter/material.dart';

import '../models/assistant_profile.dart';
import '../services/mina_platform.dart';
import '../services/xiaozhi_session_service.dart';
import 'mina_settings_screen.dart';

/// Màn hình ứng dụng của Launcher: chọn trợ lý, radio, YouTube, trình duyệt, Wi-Fi, cài đặt.
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
      _Tile(Icons.radio_rounded, 'Radio', const Color(0xFF00F5A0), () => _showRadio(context)),
      _Tile(Icons.smart_display_rounded, 'YouTube', const Color(0xFFFF4D4D),
          () => MinaPlatform.openBrowser('https://m.youtube.com')),
      _Tile(Icons.public_rounded, 'Trình duyệt', const Color(0xFF60A5FA),
          () => MinaPlatform.openBrowser('https://www.google.com')),
      _Tile(Icons.wifi_rounded, 'Wi-Fi', Colors.white70, MinaPlatform.openWifiSettings),
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
                  const Text('Mina', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.15,
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
