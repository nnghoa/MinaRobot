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

/// Chuyển chuỗi cảm xúc mà XiaoZhi gửi về (trường `emotion` trong bản tin `llm`) sang biểu cảm của Mina.
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
