import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mina_state.dart';

/// Khuôn mặt Robot Mina vẽ bằng Vector Canvas 60FPS siêu nhẹ (chạy cực mượt trên GPU Mali-400 của Allwinner A33)
class MinaAnimatedFace extends StatefulWidget {
  final MinaEmotion emotion;
  final MinaVoiceStatus status;

  const MinaAnimatedFace({
    super.key,
    required this.emotion,
    required this.status,
  });

  @override
  State<MinaAnimatedFace> createState() => _MinaAnimatedFaceState();
}

class _MinaAnimatedFaceState extends State<MinaAnimatedFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _MinaFacePainter(
            progress: _ctrl.value,
            emotion: widget.emotion,
            status: widget.status,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MinaFacePainter extends CustomPainter {
  final double progress;
  final MinaEmotion emotion;
  final MinaVoiceStatus status;

  _MinaFacePainter({
    required this.progress,
    required this.emotion,
    required this.status,
  });

  Color get _primaryColor {
    switch (emotion) {
      case MinaEmotion.love:
        return const Color(0xFFFF4D8D);
      case MinaEmotion.happy:
        return const Color(0xFF00F5A0);
      case MinaEmotion.martial:
        return const Color(0xFFFF9F1C);
      case MinaEmotion.listening:
        return const Color(0xFF00D9FF);
      case MinaEmotion.thinking:
        return const Color(0xFFA855F7);
      case MinaEmotion.sleepy:
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF00E5FF);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.44;
    final eyeGap = math.min(size.width * 0.22, 170.0);
    final eyeW = math.min(size.width * 0.19, 145.0);
    final eyeH = math.min(size.height * 0.34, 155.0);

    // Chớp mắt tự nhiên mỗi 4 giây
    double blinkScale = 1.0;
    if (progress > 0.93) {
      final t = (progress - 0.93) / 0.07;
      blinkScale = (t - 0.5).abs() * 2.0;
    }
    if (emotion == MinaEmotion.sleepy) {
      blinkScale = 0.22;
    }

    // Chuyển động đảo mắt nhẹ nhàng
    final gazeX = math.sin(progress * math.pi * 2) * (eyeW * 0.06);
    final gazeY = math.cos(progress * math.pi * 4) * (eyeH * 0.03);

    final glowPaint = Paint()
      ..color = _primaryColor.withOpacity(0.16)
      ..style = PaintingStyle.fill;

    final eyePaint = Paint()
      ..color = _primaryColor
      ..style = PaintingStyle.fill;

    // Vẽ 2 mắt trái & phải
    _drawSingleEye(
      canvas: canvas,
      center: Offset(cx - eyeGap + gazeX, cy + gazeY),
      width: eyeW,
      height: eyeH * blinkScale.clamp(0.08, 1.0),
      isLeft: true,
      glowPaint: glowPaint,
      eyePaint: eyePaint,
    );

    _drawSingleEye(
      canvas: canvas,
      center: Offset(cx + eyeGap + gazeX, cy + gazeY),
      width: eyeW,
      height: eyeH * blinkScale.clamp(0.08, 1.0),
      isLeft: false,
      glowPaint: glowPaint,
      eyePaint: eyePaint,
    );

    // Vẽ miệng / sóng âm phía dưới hai mắt
    _drawMouthOrWaveform(canvas, Offset(cx, cy + eyeH * 0.85), eyeW * 1.3);
  }

  void _drawSingleEye({
    required Canvas canvas,
    required Offset center,
    required double width,
    required double height,
    required bool isLeft,
    required Paint glowPaint,
    required Paint eyePaint,
  }) {
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(width * 0.36));
    final glowRRect = RRect.fromRectAndRadius(rect.inflate(7.0), Radius.circular(width * 0.42));

    canvas.drawRRect(glowRRect, glowPaint);

    if (emotion == MinaEmotion.happy) {
      // Mắt cười cong hình vòm ^ ^
      final arcPaint = Paint()
        ..color = _primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.16
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(center: center.translate(0, height * 0.18), width: width * 0.85, height: height * 0.8),
        math.pi * 1.12,
        math.pi * 0.76,
        false,
        arcPaint,
      );
      return;
    }

    if (emotion == MinaEmotion.love) {
      _drawHeart(canvas, center, width * 0.9, eyePaint);
      return;
    }

    canvas.drawRRect(rrect, eyePaint);

    // Điểm sáng long lanh trong mắt
    if (height > width * 0.3) {
      final highlightPaint = Paint()..color = Colors.white.withOpacity(0.85);
      canvas.drawCircle(
        center.translate(-width * 0.22, -height * 0.22),
        width * 0.11,
        highlightPaint,
      );
    }

    // Chân mày võ thuật mạnh mẽ khi Mina múa võ
    if (emotion == MinaEmotion.martial) {
      final browPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      final path = Path();
      if (isLeft) {
        path.moveTo(rect.left - 4, rect.top - 4);
        path.lineTo(rect.right + 4, rect.top - 4);
        path.lineTo(rect.right + 4, rect.top + height * 0.34);
        path.close();
      } else {
        path.moveTo(rect.left - 4, rect.top - 4);
        path.lineTo(rect.right + 4, rect.top - 4);
        path.lineTo(rect.left - 4, rect.top + height * 0.34);
        path.close();
      }
      canvas.drawPath(path, browPaint);
    }
  }

  void _drawMouthOrWaveform(Canvas canvas, Offset center, double totalWidth) {
    if (status == MinaVoiceStatus.aiSpeaking || status == MinaVoiceStatus.listeningUser) {
      // Thanh sóng âm nhấp nháy theo thời gian thực khi Mina đang nghe hoặc đang nói
      const bars = 9;
      final spacing = totalWidth / bars;
      final barPaint = Paint()
        ..color = _primaryColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7.0;

      for (int i = 0; i < bars; i++) {
        final phase = (progress * math.pi * 12) + (i * 0.75);
        final amp = (math.sin(phase).abs() * 24.0) + 6.0;
        final x = center.dx - (totalWidth / 2) + (i * spacing) + (spacing / 2);
        canvas.drawLine(Offset(x, center.dy - amp), Offset(x, center.dy + amp), barPaint);
      }
      return;
    }

    // Nụ cười mỉm dễ thương của Mina khi ở trạng thái bình thường
    final smilePaint = Paint()
      ..color = _primaryColor.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(center: center.translate(0, -10), width: totalWidth * 0.42, height: 34),
      math.pi * 0.15,
      math.pi * 0.70,
      false,
      smilePaint,
    );
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final topCurveHeight = size * 0.3;
    path.moveTo(center.dx, center.dy + size * 0.35);
    path.cubicTo(
      center.dx - size * 0.6,
      center.dy + size * 0.05,
      center.dx - size * 0.55,
      center.dy - topCurveHeight,
      center.dx,
      center.dy - topCurveHeight * 0.35,
    );
    path.cubicTo(
      center.dx + size * 0.55,
      center.dy - topCurveHeight,
      center.dx + size * 0.6,
      center.dy + size * 0.05,
      center.dx,
      center.dy + size * 0.35,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MinaFacePainter oldDelegate) {
    if (oldDelegate.emotion != emotion || oldDelegate.status != status) return true;
    final activeVoice =
        status == MinaVoiceStatus.aiSpeaking || status == MinaVoiceStatus.listeningUser;
    final isBlinking = progress > 0.92 || oldDelegate.progress > 0.92;
    // Khi đang nói/nghe hoặc đang chớp mắt: ~25 FPS (100 bước / 4s). Khi nghỉ: ~10 FPS (40 bước / 4s)
    final steps = (activeVoice || isBlinking) ? 100 : 40;
    return (progress * steps).floor() != (oldDelegate.progress * steps).floor();
  }
}
