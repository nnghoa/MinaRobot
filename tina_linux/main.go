package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

const defaultConfigPath = "/etc/mina_config.json"

func loadOrCreateConfig(path string) (*Config, error) {
	cfg := &Config{
		DeviceMAC: GenerateMAC(),
		ClientID:  fmt.Sprintf("tina-%s", GenerateMAC()),
		OtaURL:    "https://api.tenclass.net/xiaozhi/ota/",
		UartPort:  "/dev/ttyS1",
		UartBaud:  9600,
	}

	data, err := os.ReadFile(path)
	if err == nil {
		if err := json.Unmarshal(data, cfg); err == nil {
			return cfg, nil
		}
	}

	// Tạo mới nếu chưa có
	_ = os.MkdirAll(filepath.Dir(path), 0755)
	saveConfig(path, cfg)
	return cfg, nil
}

func saveConfig(path string, cfg *Config) {
	data, _ := json.MarshalIndent(cfg, "", "  ")
	_ = os.WriteFile(path, data, 0644)
}

func main() {
	configPath := flag.String("config", defaultConfigPath, "Đường dẫn file cấu hình JSON")
	actionTest := flag.String("test-action", "", "Chạy thử một động tác UART và thoát (ví dụ: 'bow', 'dance_1')")
	flag.Parse()

	log.Println("==================================================")
	log.Println("  Mina AI Daemon cho Tina Linux (Robonova-II A33)")
	log.Println("==================================================")

	cfg, err := loadOrCreateConfig(*configPath)
	if err != nil {
		log.Fatalf("[FATAL] Lỗi cấu hình: %v", err)
	}

	// Mở cổng UART nối mạch MR-C3024FX
	if err := InitSerial(cfg.UartPort, cfg.UartBaud); err != nil {
		log.Printf("[CẢNH BÁO] Không mở được cổng UART: %v", err)
	}
	defer CloseSerial()

	// Chạy thử động tác nếu được yêu cầu từ command line
	if *actionTest != "" {
		res, err := ExecuteAction(*actionTest)
		if err != nil {
			log.Fatalf("[TEST ERROR] %v", err)
		}
		log.Printf("[TEST SUCCESS] %s", res)
		return
	}

	// Khởi tạo hệ thống âm thanh ALSA
	audio := NewAudioEngine()
	if err := audio.InitPlayer(24000); err != nil {
		log.Printf("[CẢNH BÁO] Không mở được aplay: %v", err)
	}
	defer audio.Stop()

	// Khởi tạo XiaoZhi Client
	client := NewXiaoZhiClient(cfg, audio)
	if err := client.CheckOtaAndPairing(); err != nil {
		log.Printf("[OTA ERROR] %v", err)
	}
	saveConfig(*configPath, cfg)

	if err := client.Connect(); err != nil {
		log.Printf("[WS ERROR] %v", err)
	}

	// Bắt đầu thu âm và gửi lên XiaoZhi
	err = audio.StartRecording(func(pcmFrame []byte) {
		_ = client.SendPcm(pcmFrame)
	})
	if err != nil {
		log.Printf("[CẢNH BÁO] Không mở được arecord: %v", err)
	}

	log.Println("[INFO] Mina Daemon đang chạy ngầm. Nhấn Ctrl+C để dừng.")

	// Chờ tín hiệu dừng
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	log.Println("[INFO] Đang dừng Mina Daemon...")
}
