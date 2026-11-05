enum MinaEmotion {
  idle,
  listening,
  thinking,
  speaking,
  happy,
  love,
  martial,
  surprised,
  sleepy,
}

enum MinaVoiceStatus {
  initializing,
  standbyWakeWord,
  connectingCloud,
  listeningUser,
  aiSpeaking,
  pairingRequired,
  error,
}

class MinaLogEntry {
  final DateTime time;
  final String tag;
  final String message;

  MinaLogEntry({
    required this.time,
    required this.tag,
    required this.message,
  });
}

/// Dữ liệu cảm biến thời gian thực truyền từ mạch Robonova-II (MR-C3024FX ETX 9600) lên Android A33
class RobonovaSensorState {
  /// Khoảng cách mắt siêu âm SONAR(5) (#10 Trigger / #11 Echo), đơn vị cm (0 = ngoài tầm / chưa có phản xạ)
  final int sonarRaw;

  /// Giá trị ADC 8-bit (0..255) từ cảm biến đo khoảng cách 10k trên chân AD(0) (càng lớn = vật càng gần)
  final int dist10kRaw;

  /// Giá trị ADC 8-bit (0..255) điện áp pin trên chân AD(6) (Volts = raw * 10 / 256)
  final int batteryRaw;

  /// Giá trị ADC 8-bit (0..255) cảm biến nghiêng trên chân AD(5) (<30: ngã ngửa, >200: ngã sấp)
  final int tiltRaw;

  /// Ngưỡng cảnh báo vật cản mắt siêu âm (cm)
  final int sonarObstacleThresholdCm;

  /// Ngưỡng cảnh báo vật cản cảm biến 10k (ADC 0..255)
  final int dist10kObstacleThreshold;

  /// Thời điểm cập nhật gói tin 8-byte gần nhất
  final DateTime? updatedAt;

  const RobonovaSensorState({
    this.sonarRaw = 0,
    this.dist10kRaw = 0,
    this.batteryRaw = 0,
    this.tiltRaw = 128,
    this.sonarObstacleThresholdCm = 25,
    this.dist10kObstacleThreshold = 85,
    this.updatedAt,
  });

  bool get hasData => updatedAt != null;

  /// Khoảng cách mắt siêu âm hợp lệ (cm), null nếu ngoài tầm đo (0) hoặc chưa có dữ liệu
  int? get sonarCm => (hasData && sonarRaw > 0 && sonarRaw <= 3000) ? sonarRaw : null;

  /// Ước lượng khoảng cách (cm) từ giá trị ADC của cảm biến hồng ngoại/analog 10k
  double? get dist10kApproxCm {
    if (!hasData || dist10kRaw <= 15) return null;
    final est = 2400.0 / (dist10kRaw - 6.0);
    return est.clamp(8.0, 80.0).toDouble();
  }

  /// Điện áp pin Robonova-II (chuẩn NiMH 6.0V: công thức gốc 10 * AD(6) / 256)
  double get batteryVolts => hasData ? (batteryRaw * 10.0 / 256.0) : 0.0;

  /// Phần trăm dung lượng pin ước tính cho pack NiMH 5-cell 6.0V (5.6V = 0%, 6.8V = 100%)
  int get batteryPercent {
    if (!hasData || batteryRaw == 0) return 0;
    return (((batteryVolts - 5.6) / 1.2) * 100.0).round().clamp(0, 100).toInt();
  }

  /// Pin yếu dưới 5.8V (AD(6) < 148 theo chuẩn Hitec MR-C3024FX)
  bool get isBatteryLow => hasData && batteryRaw > 10 && batteryRaw < 148;

  /// Ngã ngửa về phía sau (AD(5) < 30, loại trừ 0..2 khi chân AD5 để hở/chưa cắm)
  bool get isFallenBack => hasData && tiltRaw > 2 && tiltRaw < 30;

  /// Ngã sấp về phía trước (200 < AD(5) <= 250, loại trừ >250 khi chân AD5 kéo lên cao)
  bool get isFallenFront => hasData && tiltRaw > 200 && tiltRaw <= 250;

  String get postureLabel {
    if (!hasData) return 'Chưa có dữ liệu';
    if (isFallenBack) return 'Ngã ngửa (Cần K19)';
    if (isFallenFront) return 'Ngã sấp (Cần K25)';
    if (tiltRaw <= 2 || tiltRaw > 250) return 'Đứng thẳng (AD5 mở)';
    return 'Đứng thăng bằng';
  }

  bool get hasSonarObstacle => sonarCm != null && sonarCm! < sonarObstacleThresholdCm;

  bool get hasDist10kObstacle => hasData && dist10kRaw > dist10kObstacleThreshold;

  bool get hasObstacle => hasSonarObstacle || hasDist10kObstacle;

  RobonovaSensorState copyWith({
    int? sonarRaw,
    int? dist10kRaw,
    int? batteryRaw,
    int? tiltRaw,
    int? sonarObstacleThresholdCm,
    int? dist10kObstacleThreshold,
    DateTime? updatedAt,
  }) {
    return RobonovaSensorState(
      sonarRaw: sonarRaw ?? this.sonarRaw,
      dist10kRaw: dist10kRaw ?? this.dist10kRaw,
      batteryRaw: batteryRaw ?? this.batteryRaw,
      tiltRaw: tiltRaw ?? this.tiltRaw,
      sonarObstacleThresholdCm: sonarObstacleThresholdCm ?? this.sonarObstacleThresholdCm,
      dist10kObstacleThreshold: dist10kObstacleThreshold ?? this.dist10kObstacleThreshold,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

MinaEmotion parseEmotionFromXiaozhi(String raw) {
  final e = raw.trim().toLowerCase();
  if (e.contains('happy') || e.contains('laugh') || e.contains('funny') || e.contains('wink')) {
    return MinaEmotion.happy;
  }
  if (e.contains('love') || e.contains('kiss') || e.contains('heart')) {
    return MinaEmotion.love;
  }
  if (e.contains('angry') || e.contains('cool') || e.contains('confident')) {
    return MinaEmotion.martial;
  }
  if (e.contains('shock') || e.contains('surpris')) {
    return MinaEmotion.surprised;
  }
  if (e.contains('sleep') || e.contains('tired') || e.contains('sad')) {
    return MinaEmotion.sleepy;
  }
  if (e.contains('think')) {
    return MinaEmotion.thinking;
  }
  return MinaEmotion.speaking;
}
