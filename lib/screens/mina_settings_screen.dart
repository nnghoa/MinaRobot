import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assistant_profile.dart';
import '../services/mina_platform.dart';
import '../services/xiaozhi_session_service.dart';

/// Cài đặt: ghép nối từng trợ lý với xiaozhi.me, đặt Mina làm Launcher, server riêng, nhật ký.
class MinaSettingsScreen extends StatefulWidget {
  final MinaBrainController brain;

  const MinaSettingsScreen({super.key, required this.brain});

  @override
  State<MinaSettingsScreen> createState() => _MinaSettingsScreenState();
}

class _MinaSettingsScreenState extends State<MinaSettingsScreen> {
  bool _checking = false;
  bool _isLauncher = false;
  bool _useCustomPairing = false;
  final _wsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _wsCtrl.text = await widget.brain.otaService.getCustomWsUrl();
    final l = await MinaPlatform.isDefaultLauncher();
    final customPair = await widget.brain.otaService.getUseCustomPairing();
    if (mounted) {
      setState(() {
        _isLauncher = l;
        _useCustomPairing = customPair;
      });
    }
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    await widget.brain.refreshAllPairing();
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _wsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: Colors.white70, fontSize: 11);
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.brain,
          builder: (context, _) {
            final pairing = widget.brain.pairingByAssistant;
            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text('Cài đặt Mina', style: TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    TextButton.icon(
                      onPressed: _checking ? null : _checkAll,
                      icon: _checking
                          ? const SizedBox(
                              width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Kiểm tra ghép nối', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  value: !_useCustomPairing,
                  title: const Text('Dùng tài khoản tích hợp sẵn (Không cần đăng ký)',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  subtitle: const Text(
                    'Tự động kết nối cho đầy đủ 18 trợ lý & gia sư AI mà không cần tạo tài khoản xiaozhi.me',
                    style: label,
                  ),
                  onChanged: (useBuiltin) async {
                    final custom = !useBuiltin;
                    await widget.brain.otaService.setUseCustomPairing(custom);
                    if (mounted) setState(() => _useCustomPairing = custom);
                    await _checkAll();
                  },
                ),
                for (final a in AssistantCatalog.all)
                  _assistantCard(a, pairing.containsKey(a.id), pairing[a.id]),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  dense: true,
                  value: _isLauncher,
                  title: const Text('Mina là màn hình chính',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  subtitle: const Text('Mở màn hình chọn Launcher của Android', style: label),
                  onChanged: (_) async {
                    await MinaPlatform.openHomeSettings();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _wsCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Server WebSocket riêng (để trống = xiaozhi.me)',
                      labelStyle: label,
                    ),
                    onSubmitted: (v) => widget.brain.otaService.setCustomWsUrl(v),
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Nhật ký', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                for (final e in widget.brain.logs.take(60))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Text(
                      '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:'
                      '${e.time.second.toString().padLeft(2, '0')} [${e.tag}] ${e.message}',
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _assistantCard(AssistantProfile a, bool checked, String? code) {
    final String status;
    final Color statusColor;
    if (!checked) {
      status = 'Chưa kiểm tra';
      statusColor = Colors.white38;
    } else if (code != null) {
      status = 'Mã ghép nối: $code';
      statusColor = const Color(0xFFFF9F1C);
    } else {
      status = 'Đã ghép nối';
      statusColor = const Color(0xFF00F5A0);
    }
    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(a.icon, color: a.color, size: 22),
        title: Text(a.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
        subtitle: Text(status, style: TextStyle(color: statusColor, fontSize: 11)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Giọng: ${a.voiceHint}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Vai trò (dán vào agent):', style: TextStyle(color: Colors.white70, fontSize: 11)),
          SelectableText(a.rolePrompt, style: const TextStyle(color: Colors.white, fontSize: 11)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_useCustomPairing)
                TextButton.icon(
                  icon: const Icon(Icons.sync_rounded, size: 14),
                  label: const Text('Đổi kênh kết nối', style: TextStyle(fontSize: 11)),
                  onPressed: () => widget.brain.rotateAssistantDevice(a.id),
                ),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Sao chép', style: TextStyle(fontSize: 11)),
                onPressed: () => Clipboard.setData(ClipboardData(text: a.rolePrompt)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
