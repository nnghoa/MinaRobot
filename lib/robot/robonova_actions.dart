enum ActionCategory {
  greeting,
  walking,
  martialArts,
  danceAcrobatics,
  postureRecovery,
  soundEffect,
}

class RobonovaAction {
  final String id;        // Mã K1..K68
  final String slug;      // Định danh tiếng Anh cho AI MCP
  final String nameVi;    // Tên tiếng Việt chuẩn theo Danh sach action robonova 2.xlsx
  final int asciiByte;    // Giá trị DEC (40..108) gửi qua cổng ERX 9600 của MR-C3024FX
  final ActionCategory category;
  final int estimatedMs;  // Thời gian ước tính hoàn thành động tác (ms)

  const RobonovaAction({
    required this.id,
    required this.slug,
    required this.nameVi,
    required this.asciiByte,
    required this.category,
    this.estimatedMs = 2500,
  });

  String get asciiChar => String.fromCharCode(asciiByte);
}

/// Toàn bộ 63 hành động thực tế của mạch MR-C3024FX (Robonova-II / Metal Fighter)
/// Đối chiếu chính xác 100% từ `code tong hop cho robonova 2.txt` và `Danh sach action robonova 2.xlsx`
class RobonovaActionCatalog {
  static const List<RobonovaAction> all = [
    // === NHÓM MAIN2: K1..K35 (DEC 40..74) ===
    RobonovaAction(id: 'K1', slug: 'bow', nameVi: 'Cúi chào', asciiByte: 40, category: ActionCategory.greeting),
    RobonovaAction(id: 'K2', slug: 'hands_up', nameVi: 'Giơ hai tay', asciiByte: 41, category: ActionCategory.greeting),
    RobonovaAction(id: 'K3', slug: 'sit_down', nameVi: 'Ngồi xuống', asciiByte: 42, category: ActionCategory.postureRecovery),
    RobonovaAction(id: 'K4', slug: 'sit_hands_up', nameVi: 'Ngồi giơ tay', asciiByte: 43, category: ActionCategory.greeting),
    RobonovaAction(id: 'K5', slug: 'foot_up', nameVi: 'Nhấc một chân', asciiByte: 44, category: ActionCategory.danceAcrobatics),
    RobonovaAction(id: 'K6', slug: 'body_shake', nameVi: 'Lắc thân', asciiByte: 45, category: ActionCategory.danceAcrobatics),
    RobonovaAction(id: 'K7', slug: 'wave_arms', nameVi: 'Vẫy cánh tay', asciiByte: 46, category: ActionCategory.greeting),
    RobonovaAction(id: 'K8', slug: 'shoot_left_right', nameVi: 'Sút bóng trái & phải', asciiByte: 47, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K9', slug: 'handstand', nameVi: 'Trồng chuối (Chống tay)', asciiByte: 48, category: ActionCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K10', slug: 'fast_walk', nameVi: 'Đi nhanh', asciiByte: 49, category: ActionCategory.walking),
    RobonovaAction(id: 'K11', slug: 'walk_forward', nameVi: 'Đi tới', asciiByte: 50, category: ActionCategory.walking),
    RobonovaAction(id: 'K12', slug: 'walk_backward', nameVi: 'Đi lùi', asciiByte: 51, category: ActionCategory.walking),
    RobonovaAction(id: 'K13', slug: 'shift_right', nameVi: 'Bước ngang sang phải', asciiByte: 52, category: ActionCategory.walking),
    RobonovaAction(id: 'K14', slug: 'shift_left', nameVi: 'Bước ngang sang trái', asciiByte: 53, category: ActionCategory.walking),
    RobonovaAction(id: 'K15', slug: 'left_attack', nameVi: 'Đấm tay trái', asciiByte: 54, category: ActionCategory.martialArts),
    RobonovaAction(id: 'K16', slug: 'toggle_motor_sit', nameVi: 'Bật/Tắt chế độ ngồi nghỉ (Motor Off/On)', asciiByte: 55, category: ActionCategory.postureRecovery),
    RobonovaAction(id: 'K17', slug: 'step_forward_left', nameVi: 'Bước chéo trái', asciiByte: 56, category: ActionCategory.walking),
    RobonovaAction(id: 'K18', slug: 'beep_c', nameVi: 'Phát tiếng bíp nốt Đô (C)', asciiByte: 57, category: ActionCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K19', slug: 'stand_up_from_back', nameVi: 'Tự đứng dậy khi nằm ngửa', asciiByte: 58, category: ActionCategory.postureRecovery, estimatedMs: 3500),
    RobonovaAction(id: 'K20', slug: 'right_attack', nameVi: 'Đấm tay phải', asciiByte: 59, category: ActionCategory.martialArts),
    RobonovaAction(id: 'K21', slug: 'forward_tumbling', nameVi: 'Lộn nhào về phía trước', asciiByte: 60, category: ActionCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K22', slug: 'turn_left', nameVi: 'Quay trái', asciiByte: 61, category: ActionCategory.walking),
    RobonovaAction(id: 'K23', slug: 'beep_d', nameVi: 'Phát tiếng bíp nốt Rê (D)', asciiByte: 62, category: ActionCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K24', slug: 'turn_right', nameVi: 'Quay phải', asciiByte: 63, category: ActionCategory.walking),
    RobonovaAction(id: 'K25', slug: 'stand_up_from_front', nameVi: 'Tự đứng dậy khi nằm sấp', asciiByte: 64, category: ActionCategory.postureRecovery, estimatedMs: 3500),
    RobonovaAction(id: 'K26', slug: 'toggle_sit_pose_2', nameVi: 'Bật/Tắt tư thế ngồi 2', asciiByte: 65, category: ActionCategory.postureRecovery),
    RobonovaAction(id: 'K27', slug: 'step_forward_right', nameVi: 'Tiến chéo phải', asciiByte: 66, category: ActionCategory.walking),
    RobonovaAction(id: 'K28', slug: 'left_tumbling', nameVi: 'Nhào lộn sang trái', asciiByte: 67, category: ActionCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K29', slug: 'forward_punch', nameVi: 'Đấm thẳng về trước', asciiByte: 68, category: ActionCategory.martialArts),
    RobonovaAction(id: 'K30', slug: 'right_tumbling', nameVi: 'Nhào lộn sang phải', asciiByte: 69, category: ActionCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K31', slug: 'back_tumbling', nameVi: 'Lộn ngửa về sau', asciiByte: 70, category: ActionCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K32', slug: 'beep_e', nameVi: 'Phát tiếng bíp nốt Mi (E)', asciiByte: 71, category: ActionCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K33', slug: 'very_fast_walk', nameVi: 'Đi rất nhanh', asciiByte: 72, category: ActionCategory.walking),
    RobonovaAction(id: 'K34', slug: 'fast_turn_left_1', nameVi: 'Quay trái nhanh', asciiByte: 73, category: ActionCategory.walking),
    RobonovaAction(id: 'K35', slug: 'fast_turn_right_1', nameVi: 'Quay phải nhanh', asciiByte: 74, category: ActionCategory.walking),

    // === NHÓM MAIN3: K40..K48 (DEC 80..88) - VÕ THUẬT & THỂ LỰC ===
    RobonovaAction(id: 'K40', slug: 'pushup_music', nameVi: 'Chống đẩy có nhạc', asciiByte: 80, category: ActionCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K41', slug: 'honor_bow', nameVi: 'Chào danh dự + Cúi chào', asciiByte: 81, category: ActionCategory.greeting, estimatedMs: 4000),
    RobonovaAction(id: 'K42', slug: 'big_toss', nameVi: 'Tuyệt chiêu ném mạnh (Big Toss)', asciiByte: 82, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K43', slug: 'big_reach', nameVi: 'Vươn vai cao (Big Reach)', asciiByte: 83, category: ActionCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K44', slug: 'martial_arts_2', nameVi: 'Thế võ số 2', asciiByte: 84, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K45', slug: 'martial_arts_3', nameVi: 'Thế võ số 3', asciiByte: 85, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K46', slug: 'martial_arts_4', nameVi: 'Thế võ số 4', asciiByte: 86, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K47', slug: 'martial_arts_5', nameVi: 'Thế võ số 5', asciiByte: 87, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K48', slug: 'martial_arts_1', nameVi: 'Thế võ số 1 (Khai quyền)', asciiByte: 88, category: ActionCategory.martialArts, estimatedMs: 3500),

    // === NHÓM MAIN4: K50..K68 (DEC 90..108) - NHẢY MÚA, GIAO TIẾP & NÂNG CAO ===
    RobonovaAction(id: 'K50', slug: 'fast_run', nameVi: 'Chạy nhanh', asciiByte: 90, category: ActionCategory.walking),
    RobonovaAction(id: 'K51', slug: 'fast_turn_right_2', nameVi: 'Xoay phải nhanh', asciiByte: 91, category: ActionCategory.walking),
    RobonovaAction(id: 'K52', slug: 'fast_turn_left_2', nameVi: 'Xoay trái nhanh', asciiByte: 92, category: ActionCategory.walking),
    RobonovaAction(id: 'K53', slug: 'avoid_matrix', nameVi: 'Né đòn kiểu Ma Trận (Matrix)', asciiByte: 93, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K54', slug: 'goalkeeper', nameVi: 'Thủ môn bắt bóng', asciiByte: 94, category: ActionCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K55', slug: 'cheer_up', nameVi: 'Cổ vũ ăn mừng', asciiByte: 95, category: ActionCategory.greeting, estimatedMs: 3500),
    RobonovaAction(id: 'K56', slug: 'single_foot_stand', nameVi: 'Đứng thăng bằng một chân', asciiByte: 96, category: ActionCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K57', slug: 'hand_clap', nameVi: 'Vỗ tay', asciiByte: 97, category: ActionCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K58', slug: 'hand_shake', nameVi: 'Bắt tay', asciiByte: 98, category: ActionCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K59', slug: 'break_dance', nameVi: 'Nhảy Break Dance', asciiByte: 99, category: ActionCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K60', slug: 'sit_walk_forward', nameVi: 'Đi tới tư thế ngồi xổm', asciiByte: 100, category: ActionCategory.walking),
    RobonovaAction(id: 'K61', slug: 'sit_walk_backward', nameVi: 'Đi lùi tư thế ngồi xổm', asciiByte: 101, category: ActionCategory.walking),
    RobonovaAction(id: 'K62', slug: 'sit_walk_left', nameVi: 'Đi sang trái tư thế ngồi xổm', asciiByte: 102, category: ActionCategory.walking),
    RobonovaAction(id: 'K63', slug: 'sit_walk_right', nameVi: 'Đi sang phải tư thế ngồi xổm', asciiByte: 103, category: ActionCategory.walking),
    RobonovaAction(id: 'K64', slug: 'dance_1', nameVi: 'Bài nhảy Dance 1', asciiByte: 104, category: ActionCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K65', slug: 'dance_2', nameVi: 'Bài nhảy Dance 2', asciiByte: 105, category: ActionCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K66', slug: 'climb_upstair', nameVi: 'Leo cầu thang', asciiByte: 106, category: ActionCategory.walking, estimatedMs: 4000),
    RobonovaAction(id: 'K67', slug: 'push_up', nameVi: 'Hít đất (Push Up)', asciiByte: 107, category: ActionCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K68', slug: 'dance_3', nameVi: 'Bài nhảy Dance 3', asciiByte: 108, category: ActionCategory.danceAcrobatics, estimatedMs: 6000),
  ];

  static RobonovaAction? findBySlugOrId(String query) {
    final normalized = query.trim().toLowerCase();
    for (final act in all) {
      if (act.slug.toLowerCase() == normalized || act.id.toLowerCase() == normalized) {
        return act;
      }
    }
    return null;
  }

  static List<RobonovaAction> byCategory(ActionCategory cat) {
    return all.where((a) => a.category == cat).toList();
  }
}
