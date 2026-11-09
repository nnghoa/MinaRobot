import 'package:flutter/material.dart';

import '../robot/robonova_actions.dart';
import '../robot/robonova_serial_driver.dart';
import '../services/xiaozhi_session_service.dart';

/// Ngăn kéo cấu hình phần cứng UART, ghép nối XiaoZhi & bàn phím test trực tiếp 63 động tác MR-C3024FX
class MinaControlDrawer extends StatefulWidget {
  final MinaBrainController controller;

  const MinaControlDrawer({
    super.key,
    required this.controller,
  });

  @override
  State<MinaControlDrawer> createState() => _MinaControlDrawerState();
}

class _MinaControlDrawerState extends State<MinaControlDrawer>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<String> _ports = const ['/dev/ttyS1', '/dev/ttyS0', '/dev/ttyS2', '/dev/ttyUSB0'];
  late String _selectedPort;
  late int _selectedBaud;
  final TextEditingController _wsUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _selectedPort = widget.controller.robotDriver.portPath;
    _selectedBaud = widget.controller.robotDriver.baudrate;
    _loadHardwareInfo();
  }

  Future<void> _loadHardwareInfo() async {
    final ports = await widget.controller.robotDriver.listAvailablePorts();
    final ws = await widget.controller.otaService.getCustomWsUrl();
    if (!mounted) return;
    setState(() {
      _ports = ports.contains(_selectedPort) ? ports : [_selectedPort, ...ports];
      _wsUrlCtrl.text = ws;
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _wsUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_rounded, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Trung Tâm Điều Khiển Robot MINA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              indicatorColor: const Color(0xFF00E5FF),
              labelColor: const Color(0xFF00E5FF),
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: '63 Động Tác (K1-K68)'),
                Tab(text: 'Cảm Biến & Phản Xạ'),
                Tab(text: 'Cổng UART & AI Server'),
                Tab(text: 'Nhật Ký Hệ Thống'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildActionsGrid(),
                  _buildSensorsTab(),
                  _buildSettingsTab(),
                  _buildLogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsGrid() {
    const actions = RobonovaActionCatalog.all;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 195,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.35,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final act = actions[index];
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: _categoryColor(act.category).withOpacity(0.55)),
            ),
          ),
          onPressed: () {
            widget.controller.robotDriver.executeAction(act);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${act.id} • DEC ${act.asciiByte} (\'${act.asciiChar}\')',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _categoryColor(act.category),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                act.nameVi,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSensorsTab() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final s = widget.controller.sensorState;
        final sonarText = s.sonarCm != null
            ? '${s.sonarCm} cm'
            : (s.hasData ? 'Ngoài tầm (0)' : 'Chưa nhận ETX');
        final d10kText = s.hasData
            ? 'ADC ${s.dist10kRaw}/255${s.dist10kApproxCm != null ? " (~${s.dist10kApproxCm!.toStringAsFixed(0)} cm)" : ""}'
            : 'Chưa nhận ETX';
        final battText = s.hasData
            ? '${s.batteryVolts.toStringAsFixed(2)} V (~${s.batteryPercent}%)'
            : 'Chưa nhận ETX';

        return ListBuilderSection(
          children: [
            _sectionTitle('1. Thông số cảm biến trực tiếp từ mạch MR-C3024FX (ETX 9600)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _sensorMetricCard(
                  icon: Icons.visibility_rounded,
                  title: 'Mắt Siêu Âm SONAR(5) (#10/#11)',
                  value: sonarText,
                  alert: s.hasSonarObstacle,
                  accent: const Color(0xFF00E5FF),
                ),
                _sensorMetricCard(
                  icon: Icons.straighten_rounded,
                  title: 'Khoảng Cách 10k AD(0)',
                  value: d10kText,
                  alert: s.hasDist10kObstacle,
                  accent: const Color(0xFF00F5A0),
                ),
                _sensorMetricCard(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Điện Áp Pin AD(6)',
                  value: battText,
                  alert: s.isBatteryLow,
                  accent: const Color(0xFFFACC15),
                ),
                _sensorMetricCard(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Tư Thế Nghiêng AD(5)',
                  value: s.hasData ? '${s.postureLabel} (${s.tiltRaw})' : 'Chưa nhận ETX',
                  alert: s.isFallenBack || s.isFallenFront,
                  accent: const Color(0xFFA78BFA),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await widget.controller.robotDriver.requestSensorSnapshot();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Đọc cảm biến ngay ('s')"),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent),
                  onPressed: () {
                    widget.controller.robotDriver.injectSimulatedSensorPacket(
                      sonarCm: 14,
                      dist10kRaw: 120,
                    );
                  },
                  child: const Text('Mô phỏng Vật cản 14cm'),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF00F5A0)),
                  onPressed: () {
                    widget.controller.robotDriver.injectSimulatedSensorPacket(
                      sonarCm: 42,
                      dist10kRaw: 35,
                    );
                  },
                  child: const Text('Mô phỏng Người đứng 42cm'),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  onPressed: () {
                    widget.controller.robotDriver.injectSimulatedSensorPacket(
                      sonarCm: 150,
                      dist10kRaw: 12,
                    );
                  },
                  child: const Text('Mô phỏng Thông thoáng'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('2. Phản xạ tự hành thông minh của Mina'),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF00E5FF),
              title: const Text(
                "Phản xạ phần cứng trên mạch MR-C3024FX ('m' / 'n')",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Tự động lùi khi vướng vật cản trước mặt & tự đứng dậy ngay trên chip Robonova-II',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: widget.controller.hardwareReflexEnabled,
              onChanged: (v) => widget.controller.updateSafetyConfig(hardwareReflex: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF00F5A0),
              title: const Text(
                'Chặn bước tiến AI MCP khi phát hiện vật cản gần',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                'Ngưỡng: Siêu âm < ${widget.controller.sonarThresholdCm} cm hoặc Cảm biến 10k ADC > ${widget.controller.dist10kThreshold}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: widget.controller.obstacleSafeWalk,
              onChanged: (v) => widget.controller.updateSafetyConfig(obstacleSafeWalk: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFFF472B6),
              title: const Text(
                'Tự động vẫy tay chào & mở hội thoại khi mắt siêu âm thấy người (15–65 cm)',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Kích hoạt khi có người đứng trước mặt Mina 2 nhịp liên tiếp (chu kỳ nghỉ 45 giây)',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: widget.controller.autoGreetOnSonar,
              onChanged: (v) => widget.controller.updateSafetyConfig(autoGreet: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFFA78BFA),
              title: const Text(
                'Tự động đứng dậy khi bị ngã ngửa (K19) hoặc ngã sấp (K25)',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Chỉ bật khi đã cắm cảm biến nghiêng vào AD5 (chân hở sẽ cho giá trị nhiễu)',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: widget.controller.autoStandupOnFall,
              onChanged: (v) => widget.controller.updateSafetyConfig(autoStandup: v),
            ),
          ],
        );
      },
    );
  }

  Widget _sensorMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required bool alert,
    required Color accent,
  }) {
    final borderColor = alert ? Colors.redAccent : accent.withOpacity(0.45);
    return Container(
      width: 235,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert ? Colors.redAccent.withOpacity(0.14) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: alert ? Colors.redAccent : accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: alert ? Colors.redAccent : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListBuilderSection(
      children: [
        _sectionTitle('1. Cấu hình UART 2 chiều nối mạch MR-C3024FX (ERX / ETX 9600)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedPort,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('Cổng Serial'),
                items: _ports
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p == RobonovaSerialDriver.usbPortName
                              ? 'USB OTG (CP2102/CH340)'
                              : p),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedPort = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedBaud,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('Tốc độ Baudrate'),
                items: const [9600, 19200, 38400, 57600, 115200]
                    .map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(b == 9600 ? '9600 (Chuẩn MR-C3024FX)' : '$b'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedBaud = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onPressed: () async {
                final ok = await widget.controller.robotDriver
                    .openPort(_selectedPort, _selectedBaud);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Đã mở cổng $_selectedPort @ $_selectedBaud baud thành công!'
                        : (_selectedPort == RobonovaSerialDriver.usbPortName
                            ? 'Chưa mở được USB OTG: ${widget.controller.robotDriver.usbStatus}'
                            : 'Không mở được $_selectedPort (Kiểm tra dây UART / quyền root).')),
                  ),
                );
                setState(() {});
              },
              icon: const Icon(Icons.usb_rounded),
              label: const Text('Kết nối UART'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('2. Định danh XiaoZhi Miễn Phí (Không giới hạn VIP)'),
        const SizedBox(height: 6),
        SelectableText(
          '• Địa chỉ MAC của Mina: ${widget.controller.deviceMac}\n'
          '• Từ khóa đánh thức Offline: "Mina", "Chào Mina", "Hey Mina", "Mina ơi"\n'
          '• Mã ghép nối 6 số (xiaozhi.me): ${widget.controller.pairingCode ?? "Đã kích hoạt / Sẵn sàng"}',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _wsUrlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco(
                  'Custom XiaoZhi WebSocket URL (Để trống để dùng xiaozhi.me chính thức)',
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onPressed: () async {
                await widget.controller.otaService.setCustomWsUrl(_wsUrlCtrl.text);
                await widget.controller.refreshOtaStatus();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã lưu cấu hình máy chủ XiaoZhi!')),
                );
              },
              child: const Text('Lưu & Kiểm tra OTA'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogsTab() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final logs = widget.controller.logs;
        if (logs.isEmpty) {
          return const Center(
            child: Text('Chưa có nhật ký.', style: TextStyle(color: Colors.white54)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: logs.length,
          itemBuilder: (context, i) {
            final item = logs[i];
            final t = '${item.time.hour.toString().padLeft(2, '0')}:'
                '${item.time.minute.toString().padLeft(2, '0')}:'
                '${item.time.second.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '[$t] [${item.tag}] ${item.message}',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _categoryColor(ActionCategory cat) {
    switch (cat) {
      case ActionCategory.greeting:
        return const Color(0xFF00F5A0);
      case ActionCategory.walking:
        return const Color(0xFF00D9FF);
      case ActionCategory.martialArts:
        return const Color(0xFFFF9F1C);
      case ActionCategory.danceAcrobatics:
        return const Color(0xFFF472B6);
      case ActionCategory.postureRecovery:
        return const Color(0xFFA78BFA);
      case ActionCategory.soundEffect:
        return const Color(0xFFFACC15);
    }
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF00E5FF),
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class ListBuilderSection extends StatelessWidget {
  final List<Widget> children;
  const ListBuilderSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
