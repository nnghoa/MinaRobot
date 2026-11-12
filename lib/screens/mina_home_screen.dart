import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/mina_state.dart';
import '../services/mina_platform.dart';
import '../services/xiaozhi_session_service.dart';
import '../widgets/mina_animated_face.dart';
import 'launcher_menu_screen.dart';

/// Màn hình chính (Launcher) của Mina Visbot: khuôn mặt toàn màn hình, chạm để nói chuyện.
/// Thiết kế cho màn hình nhỏ 308x240 px của Visbot (~410x320 dp).
class MinaHomeScreen extends StatefulWidget {
  const MinaHomeScreen({super.key});

  @override
  State<MinaHomeScreen> createState() => _MinaHomeScreenState();
}

class _MinaHomeScreenState extends State<MinaHomeScreen> {
  late final MinaBrainController _brain;
  Timer? _mediaPoll;
  Map<String, dynamic> _media = const {};

  @override
  void initState() {
    super.initState();
    _brain = MinaBrainController();
    MinaPlatform.setFrontButtonHandler((source, isBackKey) async {
      if (!mounted) return;
      if (isBackKey && Navigator.of(context).canPop()) {
        await Navigator.of(context).maybePop();
        return;
      }
      await _brain.onFrontButtonPressed(source: source);
    });
    _bootMina();
    _mediaPoll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshMedia());
  }

  Future<void> _bootMina() async {
    try {
      await [Permission.microphone, Permission.camera].request();
    } catch (_) {}
    await _brain.initializeAll();
  }

  Future<void> _refreshMedia() async {
    try {
      final m = await MinaPlatform.mediaState();
      if (mounted && (m['playing'] != _media['playing'] || m['title'] != _media['title'])) {
        setState(() => _media = m);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _mediaPoll?.cancel();
    _brain.dispose();
    super.dispose();
  }

  void _openMenu() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LauncherMenuScreen(brain: _brain)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Là Launcher: nút Back ở màn hình chính không được thoát ứng dụng
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _brain,
          builder: (context, _) {
            final a = _brain.activeAssistant;
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _brain.onFaceTapped,
                    onLongPress: _openMenu,
                    child: MinaAnimatedFace(
                      emotion: _brain.emotion,
                      status: _brain.status,
                    ),
                  ),
                ),

                // Thanh trên: trợ lý đang dùng + trạng thái + nút menu
                Positioned(
                  top: 4,
                  left: 6,
                  right: 4,
                  child: Row(
                    children: [
                      _chip(
                        icon: a.icon,
                        color: a.color,
                        label: a.name,
                        dot: _statusColor(),
                        onTap: _openMenu,
                      ),
                      const SizedBox(width: 6),
                      if (_media['playing'] == true)
                        Flexible(
                          child: _chip(
                            icon: Icons.radio_rounded,
                            color: const Color(0xFF00F5A0),
                            label: (_media['title'] ?? '').toString().isEmpty
                                ? 'Đang phát'
                                : _media['title'].toString(),
                            onTap: () async {
                              await MinaPlatform.mediaStop();
                              _refreshMedia();
                            },
                            trailing: Icons.stop_rounded,
                          ),
                        ),
                      const Spacer(),
                      if (_brain.isInConversation) ...[
                        _chip(
                          icon: Icons.autorenew_rounded,
                          color: const Color(0xFF38BDF8),
                          label: 'Chủ đề mới',
                          onTap: () => _brain.resetTopicAndListen(reason: 'Nút Chủ đề mới trên màn hình'),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.apps_rounded, color: Colors.white70, size: 26),
                        onPressed: _openMenu,
                      ),
                    ],
                  ),
                ),

                if (_brain.pairingCode != null)
                  Positioned(
                    top: 46,
                    left: 16,
                    right: 16,
                    child: Center(child: _pairingCard(_brain.pairingCode!, a.name)),
                  ),

                // Phụ đề
                Positioned(
                  bottom: 6,
                  left: 10,
                  right: 10,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _brain.subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _statusColor() {
    switch (_brain.status) {
      case MinaVoiceStatus.standbyWakeWord:
        return const Color(0xFF00F5A0);
      case MinaVoiceStatus.listeningUser:
        return const Color(0xFF00D9FF);
      case MinaVoiceStatus.aiSpeaking:
        return const Color(0xFFF472B6);
      case MinaVoiceStatus.connectingCloud:
        return const Color(0xFFFACC15);
      case MinaVoiceStatus.pairingRequired:
        return const Color(0xFFFF9F1C);
      case MinaVoiceStatus.error:
        return Colors.redAccent;
      case MinaVoiceStatus.initializing:
        return Colors.grey;
    }
  }

  Widget _chip({
    required IconData icon,
    required Color color,
    required String label,
    Color? dot,
    VoidCallback? onTap,
    IconData? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing, color: Colors.white70, size: 15),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pairingCard(String code, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5FF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mã ghép nối "$name" trên xiaozhi.me',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Text(
            code,
            style: const TextStyle(
              color: Color(0xFF00F5A0),
              fontSize: 24,
              letterSpacing: 5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
