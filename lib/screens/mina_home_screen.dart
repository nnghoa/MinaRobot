import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/mina_state.dart';
import '../services/xiaozhi_session_service.dart';
import '../widgets/mina_animated_face.dart';
import 'mina_control_drawer.dart';

class MinaHomeScreen extends StatefulWidget {
  const MinaHomeScreen({super.key});

  @override
  State<MinaHomeScreen> createState() => _MinaHomeScreenState();
}

class _MinaHomeScreenState extends State<MinaHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final MinaBrainController _brain;

  @override
  void initState() {
    super.initState();
    _brain = MinaBrainController();
    _bootMina();
  }

  Future<void> _bootMina() async {
    try {
      await Permission.microphone.request();
    } catch (_) {}
    await _brain.initializeAll();
  }

  @override
  void dispose() {
    _brain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      endDrawer: MinaControlDrawer(controller: _brain),
      body: AnimatedBuilder(
        animation: _brain,
        builder: (context, _) {
          return Stack(
            children: [
              // 1. Khuôn mặt biểu cảm toàn màn hình của Mina (chạm để trò chuyện / ngắt lời)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _brain.onFaceTapped,
                  child: MinaAnimatedFace(
                    emotion: _brain.emotion,
                    status: _brain.status,
                  ),
                ),
              ),

              // 2. Thanh trạng thái nhỏ gọn phía trên
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    _buildStatusBadge(),
                    const SizedBox(width: 8),
                    _buildUartBadge(),
                    const SizedBox(width: 8),
                    Flexible(child: _buildSensorBadge()),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Bảng điều khiển 63 động tác, Cảm biến & UART',
                      icon: const Icon(Icons.tune_rounded, color: Colors.white54),
                      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                  ],
                ),
              ),

              // 3. Thẻ hiển thị mã ghép nối 6 số lần đầu trên xiaozhi.me (nếu chưa liên kết)
              if (_brain.pairingCode != null && _brain.pairingCode!.isNotEmpty)
                Positioned(
                  top: 60,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF00E5FF)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Mã ghép nối Mina miễn phí trên xiaozhi.me',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _brain.pairingCode!,
                            style: const TextStyle(
                              color: Color(0xFF00F5A0),
                              fontSize: 28,
                              letterSpacing: 6,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 4. Phụ đề lời nói của Mina / người dùng ở cạnh dưới màn hình
              Positioned(
                bottom: 18,
                left: 24,
                right: 24,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _brain.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge() {
    String label;
    Color dotColor;
    switch (_brain.status) {
      case MinaVoiceStatus.standbyWakeWord:
        label = 'MINA • Chờ gọi "Mina"';
        dotColor = const Color(0xFF00F5A0);
        break;
      case MinaVoiceStatus.listeningUser:
        label = 'Đang nghe anh nói...';
        dotColor = const Color(0xFF00D9FF);
        break;
      case MinaVoiceStatus.aiSpeaking:
        label = 'Mina đang trả lời';
        dotColor = const Color(0xFFF472B6);
        break;
      case MinaVoiceStatus.connectingCloud:
        label = 'Đang kết nối AI...';
        dotColor = const Color(0xFFFACC15);
        break;
      case MinaVoiceStatus.pairingRequired:
        label = 'Chờ nhập mã xiaozhi.me';
        dotColor = const Color(0xFFFF9F1C);
        break;
      case MinaVoiceStatus.error:
        label = 'Lỗi mạng';
        dotColor = Colors.redAccent;
        break;
      case MinaVoiceStatus.initializing:
        label = 'Đang khởi động...';
        dotColor = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildUartBadge() {
    final ok = _brain.robotDriver.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ok
            ? (_brain.robotDriver.isUsbMode
                ? 'USB OTG @${_brain.robotDriver.baudrate}'
                : 'UART ${_brain.robotDriver.portPath}@${_brain.robotDriver.baudrate}')
            : 'UART Mô phỏng',
        style: TextStyle(
          color: ok ? const Color(0xFF00E5FF) : Colors.white38,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildSensorBadge() {
    final s = _brain.sensorState;
    if (!s.hasData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Cảm biến: Chờ ETX 9600',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }

    final sonarText = s.sonarCm != null ? '${s.sonarCm}cm' : '--';
    final warn = s.hasObstacle || s.isBatteryLow || s.isFallenBack || s.isFallenFront;
    final accent = s.hasObstacle
        ? const Color(0xFFFF6B6B)
        : (s.isBatteryLow ? const Color(0xFFFACC15) : const Color(0xFF00F5A0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warn ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: warn ? Border.all(color: accent.withOpacity(0.7)) : null,
      ),
      child: Text(
        'Mắt: $sonarText • 10k: ${s.dist10kRaw} • Pin: ${s.batteryVolts.toStringAsFixed(1)}V',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: warn ? accent : Colors.white70,
          fontSize: 11,
          fontWeight: warn ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
