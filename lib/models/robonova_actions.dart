enum RobonovaCategory {
  greeting,
  martialArts,
  danceAcrobatics,
  walking,
  postureRecovery,
  soundEffect,
}

class RobonovaAction {
  final String id; // Mã K1..K68
  final String slug; // Định danh cho AI MCP
  final String nameVi; // Tên tiếng Việt chuẩn
  final int asciiByte; // Giá trị DEC (40..108) gửi qua Bluetooth HC-06 -> ERX 9600
  final RobonovaCategory category;
  final int estimatedMs; // Thời gian ước tính hoàn thành động tác (ms)

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

class RobonovaCombo {
  final String slug;
  final String nameVi;
  final List<RobonovaAction> steps;

  const RobonovaCombo({
    required this.slug,
    required this.nameVi,
    required this.steps,
  });

  List<int> get bytes => steps.map((s) => s.asciiByte).toList();
  List<int> get delaysMs => steps.map((s) => s.estimatedMs + 300).toList();
}

/// Toàn bộ 63 hành động thực tế + các bài biểu diễn liên hoàn của Robot hình người Robonova-II (MR-C3024FX)
class RobonovaActionCatalog {
  static const List<RobonovaAction> all = [
    // === NHÓM MAIN2: K1..K35 (DEC 40..74) ===
    RobonovaAction(id: 'K1', slug: 'bow', nameVi: 'Cúi chào', asciiByte: 40, category: RobonovaCategory.greeting),
    RobonovaAction(id: 'K2', slug: 'hands_up', nameVi: 'Giơ hai tay', asciiByte: 41, category: RobonovaCategory.greeting),
    RobonovaAction(id: 'K3', slug: 'sit_down', nameVi: 'Ngồi xuống', asciiByte: 42, category: RobonovaCategory.postureRecovery),
    RobonovaAction(id: 'K4', slug: 'sit_hands_up', nameVi: 'Ngồi giơ tay', asciiByte: 43, category: RobonovaCategory.greeting),
    RobonovaAction(id: 'K5', slug: 'foot_up', nameVi: 'Nhấc một chân', asciiByte: 44, category: RobonovaCategory.danceAcrobatics),
    RobonovaAction(id: 'K6', slug: 'body_shake', nameVi: 'Lắc thân', asciiByte: 45, category: RobonovaCategory.danceAcrobatics),
    RobonovaAction(id: 'K7', slug: 'wave_arms', nameVi: 'Vẫy cánh tay', asciiByte: 46, category: RobonovaCategory.greeting),
    RobonovaAction(id: 'K8', slug: 'shoot_left_right', nameVi: 'Sút bóng trái & phải', asciiByte: 47, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K9', slug: 'handstand', nameVi: 'Trồng chuối (Chống tay)', asciiByte: 48, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K10', slug: 'fast_walk', nameVi: 'Đi nhanh', asciiByte: 49, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K11', slug: 'walk_forward', nameVi: 'Đi tới', asciiByte: 50, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K12', slug: 'walk_backward', nameVi: 'Đi lùi', asciiByte: 51, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K13', slug: 'shift_right', nameVi: 'Bước ngang sang phải', asciiByte: 52, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K14', slug: 'shift_left', nameVi: 'Bước ngang sang trái', asciiByte: 53, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K15', slug: 'left_attack', nameVi: 'Đấm tay trái', asciiByte: 54, category: RobonovaCategory.martialArts),
    RobonovaAction(id: 'K16', slug: 'toggle_motor_sit', nameVi: 'Bật/Tắt chế độ ngồi nghỉ', asciiByte: 55, category: RobonovaCategory.postureRecovery),
    RobonovaAction(id: 'K17', slug: 'step_forward_left', nameVi: 'Bước chéo trái', asciiByte: 56, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K18', slug: 'beep_c', nameVi: 'Phát tiếng bíp nốt Đô', asciiByte: 57, category: RobonovaCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K19', slug: 'stand_up_from_back', nameVi: 'Tự đứng dậy khi nằm ngửa', asciiByte: 58, category: RobonovaCategory.postureRecovery, estimatedMs: 3500),
    RobonovaAction(id: 'K20', slug: 'right_attack', nameVi: 'Đấm tay phải', asciiByte: 59, category: RobonovaCategory.martialArts),
    RobonovaAction(id: 'K21', slug: 'forward_tumbling', nameVi: 'Lộn nhào về phía trước', asciiByte: 60, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K22', slug: 'turn_left', nameVi: 'Quay trái', asciiByte: 61, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K23', slug: 'beep_d', nameVi: 'Phát tiếng bíp nốt Rê', asciiByte: 62, category: RobonovaCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K24', slug: 'turn_right', nameVi: 'Quay phải', asciiByte: 63, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K25', slug: 'stand_up_from_front', nameVi: 'Tự đứng dậy khi nằm sấp', asciiByte: 64, category: RobonovaCategory.postureRecovery, estimatedMs: 3500),
    RobonovaAction(id: 'K26', slug: 'toggle_sit_pose_2', nameVi: 'Bật/Tắt tư thế ngồi 2', asciiByte: 65, category: RobonovaCategory.postureRecovery),
    RobonovaAction(id: 'K27', slug: 'step_forward_right', nameVi: 'Bước chéo phải', asciiByte: 66, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K28', slug: 'beep_e', nameVi: 'Phát tiếng bíp nốt Mi', asciiByte: 67, category: RobonovaCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K29', slug: 'backward_tumbling', nameVi: 'Lộn nhào về phía sau', asciiByte: 68, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K30', slug: 'side_tumbling_left', nameVi: 'Lộn nhào nghiêng sang trái', asciiByte: 69, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K31', slug: 'beep_f', nameVi: 'Phát tiếng bíp nốt Fa', asciiByte: 70, category: RobonovaCategory.soundEffect, estimatedMs: 800),
    RobonovaAction(id: 'K32', slug: 'side_tumbling_right', nameVi: 'Lộn nhào nghiêng sang phải', asciiByte: 71, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K33', slug: 'side_walk_left', nameVi: 'Đi dạt sang trái', asciiByte: 72, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K34', slug: 'side_walk_right', nameVi: 'Đi dạt sang phải', asciiByte: 73, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K35', slug: 'jump_walk', nameVi: 'Bước nhảy tới', asciiByte: 74, category: RobonovaCategory.walking),

    // === NHÓM MAIN3: K40..K48 (DEC 80..88) - VÕ THUẬT & THỂ LỰC ===
    RobonovaAction(id: 'K40', slug: 'pushup_music', nameVi: 'Chống đẩy có nhạc', asciiByte: 80, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K41', slug: 'honor_bow', nameVi: 'Chào danh dự + Cúi chào', asciiByte: 81, category: RobonovaCategory.greeting, estimatedMs: 4000),
    RobonovaAction(id: 'K42', slug: 'big_toss', nameVi: 'Tuyệt chiêu ném mạnh (Big Toss)', asciiByte: 82, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K43', slug: 'big_reach', nameVi: 'Vươn vai cao', asciiByte: 83, category: RobonovaCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K44', slug: 'martial_arts_2', nameVi: 'Thế võ số 2', asciiByte: 84, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K45', slug: 'martial_arts_3', nameVi: 'Thế võ số 3', asciiByte: 85, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K46', slug: 'martial_arts_4', nameVi: 'Thế võ số 4', asciiByte: 86, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K47', slug: 'martial_arts_5', nameVi: 'Thế võ số 5', asciiByte: 87, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K48', slug: 'martial_arts_1', nameVi: 'Thế võ số 1 (Khai quyền)', asciiByte: 88, category: RobonovaCategory.martialArts, estimatedMs: 3500),

    // === NHÓM MAIN4: K50..K68 (DEC 90..108) - NHẢY MÚA, GIAO TIẾP & NÂNG CAO ===
    RobonovaAction(id: 'K50', slug: 'fast_run', nameVi: 'Chạy nhanh', asciiByte: 90, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K51', slug: 'fast_turn_right_2', nameVi: 'Xoay phải nhanh', asciiByte: 91, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K52', slug: 'fast_turn_left_2', nameVi: 'Xoay trái nhanh', asciiByte: 92, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K53', slug: 'avoid_matrix', nameVi: 'Né đòn kiểu Ma Trận (Matrix)', asciiByte: 93, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K54', slug: 'goalkeeper', nameVi: 'Thủ môn bắt bóng', asciiByte: 94, category: RobonovaCategory.martialArts, estimatedMs: 3500),
    RobonovaAction(id: 'K55', slug: 'cheer_up', nameVi: 'Cổ vũ ăn mừng', asciiByte: 95, category: RobonovaCategory.greeting, estimatedMs: 3500),
    RobonovaAction(id: 'K56', slug: 'single_foot_stand', nameVi: 'Đứng thăng bằng một chân', asciiByte: 96, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4000),
    RobonovaAction(id: 'K57', slug: 'hand_clap', nameVi: 'Vỗ tay', asciiByte: 97, category: RobonovaCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K58', slug: 'hand_shake', nameVi: 'Bắt tay', asciiByte: 98, category: RobonovaCategory.greeting, estimatedMs: 3000),
    RobonovaAction(id: 'K59', slug: 'break_dance', nameVi: 'Nhảy Break Dance', asciiByte: 99, category: RobonovaCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K60', slug: 'sit_walk_forward', nameVi: 'Đi tới tư thế ngồi xổm', asciiByte: 100, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K61', slug: 'sit_walk_backward', nameVi: 'Đi lùi tư thế ngồi xổm', asciiByte: 101, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K62', slug: 'sit_walk_left', nameVi: 'Đi sang trái tư thế ngồi xổm', asciiByte: 102, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K63', slug: 'sit_walk_right', nameVi: 'Đi sang phải tư thế ngồi xổm', asciiByte: 103, category: RobonovaCategory.walking),
    RobonovaAction(id: 'K64', slug: 'dance_1', nameVi: 'Bài nhảy Dance 1', asciiByte: 104, category: RobonovaCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K65', slug: 'dance_2', nameVi: 'Bài nhảy Dance 2', asciiByte: 105, category: RobonovaCategory.danceAcrobatics, estimatedMs: 6000),
    RobonovaAction(id: 'K66', slug: 'climb_upstair', nameVi: 'Leo cầu thang', asciiByte: 106, category: RobonovaCategory.walking, estimatedMs: 4000),
    RobonovaAction(id: 'K67', slug: 'push_up', nameVi: 'Hít đất (Push Up)', asciiByte: 107, category: RobonovaCategory.danceAcrobatics, estimatedMs: 4500),
    RobonovaAction(id: 'K68', slug: 'dance_3', nameVi: 'Bài nhảy Dance 3', asciiByte: 108, category: RobonovaCategory.danceAcrobatics, estimatedMs: 6000),
  ];

  static final List<RobonovaCombo> combos = [
    RobonovaCombo(
      slug: 'kungfu_show',
      nameVi: 'Biểu diễn Liên hoàn Quyền thuật',
      steps: [
        findBySlug('honor_bow')!,
        findBySlug('martial_arts_1')!,
        findBySlug('martial_arts_2')!,
        findBySlug('martial_arts_3')!,
        findBySlug('avoid_matrix')!,
        findBySlug('bow')!,
      ],
    ),
    RobonovaCombo(
      slug: 'dance_show',
      nameVi: 'Biểu diễn Liên hoàn Vũ đạo & Break Dance',
      steps: [
        findBySlug('dance_1')!,
        findBySlug('break_dance')!,
        findBySlug('dance_2')!,
        findBySlug('cheer_up')!,
      ],
    ),
    RobonovaCombo(
      slug: 'acrobatics_show',
      nameVi: 'Biểu diễn Nhào lộn & Trồng chuối',
      steps: [
        findBySlug('handstand')!,
        findBySlug('forward_tumbling')!,
        findBySlug('backward_tumbling')!,
        findBySlug('single_foot_stand')!,
      ],
    ),
    RobonovaCombo(
      slug: 'fitness_show',
      nameVi: 'Biểu diễn Thể lực & Chống đẩy có nhạc',
      steps: [
        findBySlug('big_reach')!,
        findBySlug('pushup_music')!,
        findBySlug('push_up')!,
        findBySlug('hand_clap')!,
      ],
    ),
  ];

  static RobonovaAction? findBySlug(String query) {
    final q = query.trim().toLowerCase();
    for (final act in all) {
      if (act.slug.toLowerCase() == q || act.id.toLowerCase() == q) {
        return act;
      }
    }
    return null;
  }

  static RobonovaCombo? findCombo(String query) {
    final q = query.trim().toLowerCase();
    for (final c in combos) {
      if (c.slug.toLowerCase() == q) return c;
    }
    if (q.contains('kungfu_show') || q.contains('liên hoàn quyền') || q.contains('biểu diễn võ')) {
      return combos[0];
    }
    if (q.contains('dance_show') || q.contains('liên hoàn nhảy') || q.contains('liên hoàn vũ đạo')) {
      return combos[1];
    }
    if (q.contains('acrobatics_show') || q.contains('biểu diễn nhào lộn')) {
      return combos[2];
    }
    if (q.contains('fitness_show') || q.contains('biểu diễn thể lực')) {
      return combos[3];
    }
    return null;
  }

  /// Tìm hành động đơn lẻ theo tên tiếng Anh, mã K1..K68, hoặc từ khóa tiếng Việt tự nhiên
  static RobonovaAction? resolveSingleAction(String query) {
    final exact = findBySlug(query);
    if (exact != null) return exact;

    final q = query.trim().toLowerCase();
    for (final act in all) {
      if (act.nameVi.toLowerCase() == q) return act;
    }

    if (q.contains('break') || q.contains('breakdance')) return findBySlug('break_dance');
    if (q.contains('dance 3') || q.contains('nhảy 3')) return findBySlug('dance_3');
    if (q.contains('dance 2') || q.contains('nhảy 2')) return findBySlug('dance_2');
    if (q.contains('dance') || q.contains('nhảy') || q.contains('múa')) return findBySlug('dance_1');
    if (q.contains('võ 2')) return findBySlug('martial_arts_2');
    if (q.contains('võ 3')) return findBySlug('martial_arts_3');
    if (q.contains('võ 4')) return findBySlug('martial_arts_4');
    if (q.contains('võ 5')) return findBySlug('martial_arts_5');
    if (q.contains('quyền') || q.contains('võ') || q.contains('kungfu')) return findBySlug('martial_arts_1');
    if (q.contains('ma trận') || q.contains('matrix') || q.contains('né')) return findBySlug('avoid_matrix');
    if (q.contains('trồng chuối')) return findBySlug('handstand');
    if (q.contains('lộn sau')) return findBySlug('backward_tumbling');
    if (q.contains('lộn')) return findBySlug('forward_tumbling');
    if (q.contains('chống đẩy')) return findBySlug('pushup_music');
    if (q.contains('hít đất')) return findBySlug('push_up');
    if (q.contains('sút') || q.contains('đá bóng')) return findBySlug('shoot_left_right');
    if (q.contains('thủ môn') || q.contains('bắt bóng')) return findBySlug('goalkeeper');
    if (q.contains('vỗ tay')) return findBySlug('hand_clap');
    if (q.contains('bắt tay')) return findBySlug('hand_shake');
    if (q.contains('cổ vũ') || q.contains('ăn mừng')) return findBySlug('cheer_up');
    if (q.contains('danh dự')) return findBySlug('honor_bow');
    if (q.contains('chào')) return findBySlug('bow');
    if (q.contains('vẫy tay')) return findBySlug('wave_arms');
    if (q.contains('giơ tay')) return findBySlug('hands_up');
    if (q.contains('đấm trái')) return findBySlug('left_attack');
    if (q.contains('đấm phải') || q.contains('đấm')) return findBySlug('right_attack');
    if (q.contains('chạy')) return findBySlug('fast_run');
    if (q.contains('đi tới') || q.contains('tiến')) return findBySlug('walk_forward');
    if (q.contains('đi lùi') || q.contains('lùi')) return findBySlug('walk_backward');
    if (q.contains('quay trái')) return findBySlug('turn_left');
    if (q.contains('quay phải')) return findBySlug('turn_right');
    if (q.contains('ngồi')) return findBySlug('sit_down');
    if (q.contains('đứng dậy')) return findBySlug('stand_up_from_front');
    if (q.contains('một chân') || q.contains('1 chân')) return findBySlug('single_foot_stand');
    if (q.contains('cầu thang')) return findBySlug('climb_upstair');

    return null;
  }

  static List<RobonovaAction> byCategory(RobonovaCategory cat) =>
      all.where((a) => a.category == cat).toList();
}
