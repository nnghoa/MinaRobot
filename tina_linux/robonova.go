package main

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/tarm/serial"
)

type RobonovaAction struct {
	ID          string `json:"id"`
	Slug        string `json:"slug"`
	NameVi      string `json:"name_vi"`
	AsciiByte   byte   `json:"ascii_byte"`
	Category    string `json:"category"`
	EstimatedMs int    `json:"estimated_ms"`
}

var (
	serialMutex sync.Mutex
	serialPort  *serial.Port
)

// Toàn bộ 63 hành động thực tế của mạch MR-C3024FX (Robonova-II / Metal Fighter)
// Đối chiếu chính xác 100% từ mã nguồn gốc: code tong hop cho robonova 2.txt
var ActionCatalog = []RobonovaAction{
	// === NHÓM MAIN2: K1..K35 (DEC 40..74) ===
	{"K1", "bow", "Cúi chào", 40, "greeting", 2500},
	{"K2", "hands_up", "Giơ hai tay", 41, "greeting", 2500},
	{"K3", "sit_down", "Ngồi xuống", 42, "posture", 2500},
	{"K4", "sit_hands_up", "Ngồi giơ tay", 43, "greeting", 2500},
	{"K5", "foot_up", "Nhấc một chân", 44, "dance", 2500},
	{"K6", "body_shake", "Lắc thân", 45, "dance", 2500},
	{"K7", "wave_arms", "Vẫy cánh tay", 46, "greeting", 2500},
	{"K8", "shoot_left_right", "Sút bóng trái & phải", 47, "martial", 3500},
	{"K9", "handstand", "Trồng chuối (Chống tay)", 48, "dance", 4500},
	{"K10", "fast_walk", "Đi nhanh", 49, "walking", 2500},
	{"K11", "walk_forward", "Đi tới", 50, "walking", 2500},
	{"K12", "walk_backward", "Đi lùi", 51, "walking", 2500},
	{"K13", "shift_right", "Bước ngang sang phải", 52, "walking", 2500},
	{"K14", "shift_left", "Bước ngang sang trái", 53, "walking", 2500},
	{"K15", "left_attack", "Đấm tay trái", 54, "martial", 2500},
	{"K16", "toggle_motor_sit", "Bật/Tắt chế độ ngồi nghỉ", 55, "posture", 2500},
	{"K17", "step_forward_left", "Bước chéo trái", 56, "walking", 2500},
	{"K18", "beep_c", "Phát tiếng bíp nốt Đô", 57, "sound", 800},
	{"K19", "stand_up_from_back", "Tự đứng dậy khi nằm ngửa", 58, "posture", 3500},
	{"K20", "right_attack", "Đấm tay phải", 59, "martial", 2500},
	{"K21", "forward_tumbling", "Lộn nhào về phía trước", 60, "dance", 4000},
	{"K22", "turn_left", "Quay trái", 61, "walking", 2500},
	{"K23", "beep_d", "Phát tiếng bíp nốt Rê", 62, "sound", 800},
	{"K24", "turn_right", "Quay phải", 63, "walking", 2500},
	{"K25", "stand_up_from_front", "Tự đứng dậy khi nằm sấp", 64, "posture", 3500},
	{"K26", "toggle_sit_pose_2", "Bật/Tắt tư thế ngồi 2", 65, "posture", 2500},
	{"K27", "step_forward_right", "Bước chéo phải", 66, "walking", 2500},
	{"K28", "beep_e", "Phát tiếng bíp nốt Mi", 67, "sound", 800},
	{"K29", "backward_tumbling", "Lộn nhào về phía sau", 68, "dance", 4000},
	{"K30", "side_tumbling_left", "Lộn nhào nghiêng sang trái", 69, "dance", 4000},
	{"K31", "beep_f", "Phát tiếng bíp nốt Fa", 70, "sound", 800},
	{"K32", "side_tumbling_right", "Lộn nhào nghiêng sang phải", 71, "dance", 4000},
	{"K33", "side_walk_left", "Đi dạt sang trái", 72, "walking", 2500},
	{"K34", "side_walk_right", "Đi dạt sang phải", 73, "walking", 2500},
	{"K35", "jump_walk", "Bước nhảy tới", 74, "walking", 2500},

	// === NHÓM MAIN3: K40..K48 (DEC 80..88) - VÕ THUẬT & THỂ LỰC ===
	{"K40", "pushup_music", "Chống đẩy có nhạc", 80, "dance", 4500},
	{"K41", "honor_bow", "Chào danh dự", 81, "greeting", 4000},
	{"K42", "big_toss", "Tuyệt chiêu ném mạnh", 82, "martial", 3500},
	{"K43", "big_reach", "Vươn vai cao", 83, "greeting", 3000},
	{"K44", "martial_arts_2", "Thế võ số 2", 84, "martial", 3500},
	{"K45", "martial_arts_3", "Thế võ số 3", 85, "martial", 3500},
	{"K46", "martial_arts_4", "Thế võ số 4", 86, "martial", 3500},
	{"K47", "martial_arts_5", "Thế võ số 5", 87, "martial", 3500},
	{"K48", "martial_arts_1", "Thế võ số 1 (Khai quyền)", 88, "martial", 3500},

	// === NHÓM MAIN4: K50..K68 (DEC 90..108) - NHẢY MÚA & NÂNG CAO ===
	{"K50", "fast_run", "Chạy nhanh", 90, "walking", 2500},
	{"K51", "fast_turn_right_2", "Xoay phải nhanh", 91, "walking", 2500},
	{"K52", "fast_turn_left_2", "Xoay trái nhanh", 92, "walking", 2500},
	{"K53", "avoid_matrix", "Né đòn kiểu Ma Trận", 93, "martial", 3500},
	{"K54", "goalkeeper", "Thủ môn bắt bóng", 94, "martial", 3500},
	{"K55", "cheer_up", "Cổ vũ ăn mừng", 95, "greeting", 3500},
	{"K56", "single_foot_stand", "Đứng thăng bằng một chân", 96, "dance", 4000},
	{"K57", "hand_clap", "Vỗ tay", 97, "greeting", 3000},
	{"K58", "hand_shake", "Bắt tay", 98, "greeting", 3000},
	{"K59", "break_dance", "Nhảy Break Dance", 99, "dance", 6000},
	{"K60", "sit_walk_forward", "Đi tới tư thế ngồi xổm", 100, "walking", 2500},
	{"K61", "sit_walk_backward", "Đi lùi tư thế ngồi xổm", 101, "walking", 2500},
	{"K62", "sit_walk_left", "Đi sang trái tư thế ngồi xổm", 102, "walking", 2500},
	{"K63", "sit_walk_right", "Đi sang phải tư thế ngồi xổm", 103, "walking", 2500},
	{"K64", "dance_1", "Bài nhảy Dance 1", 104, "dance", 6000},
	{"K65", "dance_2", "Bài nhảy Dance 2", 105, "dance", 6000},
	{"K66", "climb_upstair", "Leo cầu thang", 106, "walking", 4000},
	{"K67", "push_up", "Hít đất", 107, "dance", 4500},
	{"K68", "dance_3", "Bài nhảy Dance 3", 108, "dance", 6000},
}

func InitSerial(portName string, baudRate int) error {
	serialMutex.Lock()
	defer serialMutex.Unlock()

	c := &serial.Config{
		Name:        portName,
		Baud:        baudRate,
		ReadTimeout: time.Millisecond * 100,
	}
	p, err := serial.OpenPort(c)
	if err != nil {
		return fmt.Errorf("không thể mở cổng %s (%d baud): %w", portName, baudRate, err)
	}
	serialPort = p
	log.Printf("[SERIAL] Đã mở thành công cổng UART %s ở tốc độ %d baud", portName, baudRate)
	return nil
}

func CloseSerial() {
	serialMutex.Lock()
	defer serialMutex.Unlock()
	if serialPort != nil {
		_ = serialPort.Close()
		serialPort = nil
	}
}

func ExecuteAction(query string) (string, error) {
	norm := strings.TrimSpace(strings.ToLower(query))
	var target *RobonovaAction
	for _, act := range ActionCatalog {
		if strings.ToLower(act.Slug) == norm || strings.ToLower(act.ID) == norm {
			target = &act
			break
		}
	}
	if target == nil {
		return "", fmt.Errorf("không tìm thấy hành động '%s'", query)
	}

	serialMutex.Lock()
	defer serialMutex.Unlock()

	if serialPort == nil {
		return fmt.Sprintf("Mô phỏng (chưa mở UART): Đã thực hiện %s (%s, byte %d)", target.NameVi, target.ID, target.AsciiByte), nil
	}

	buf := []byte{target.AsciiByte}
	_, err := serialPort.Write(buf)
	if err != nil {
		return "", fmt.Errorf("lỗi ghi UART: %w", err)
	}

	log.Printf("[ROBONOVA] Đã gửi lệnh %s (%s, DEC %d / ASCII '%c') xuống MR-C3024FX", target.NameVi, target.ID, target.AsciiByte, rune(target.AsciiByte))
	return fmt.Sprintf("Đã thực hiện động tác %s (%s)", target.NameVi, target.ID), nil
}
