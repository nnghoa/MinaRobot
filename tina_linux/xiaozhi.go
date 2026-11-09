package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type Config struct {
	DeviceMAC string `json:"device_mac"`
	ClientID  string `json:"client_id"`
	OtaURL    string `json:"ota_url"`
	WsURL     string `json:"ws_url"`
	WsToken   string `json:"ws_token"`
	UartPort  string `json:"uart_port"`
	UartBaud  int    `json:"uart_baud"`
}

type XiaoZhiClient struct {
	cfg       *Config
	audio     *AudioEngine
	conn      *websocket.Conn
	mu        sync.Mutex
	sessionID string
	connected bool
	onLog     func(string, string)
}

func NewXiaoZhiClient(cfg *Config, audio *AudioEngine) *XiaoZhiClient {
	return &XiaoZhiClient{
		cfg:   cfg,
		audio: audio,
		onLog: func(tag, msg string) {
			log.Printf("[%s] %s", tag, msg)
		},
	}
}

func GenerateMAC() string {
	buf := make([]byte, 6)
	_, _ = rand.Read(buf)
	buf[0] = 0x02 // Locally administered bit
	return fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X", buf[0], buf[1], buf[2], buf[3], buf[4], buf[5])
}

// CheckOtaAndPairing kiểm tra mã kích hoạt trên server XiaoZhi
func (c *XiaoZhiClient) CheckOtaAndPairing() error {
	if c.cfg.WsURL != "" && c.cfg.WsToken != "" {
		return nil
	}

	otaURL := c.cfg.OtaURL
	if otaURL == "" {
		otaURL = "https://api.tenclass.net/xiaozhi/ota/"
	}

	payload := map[string]interface{}{
		"version":                2,
		"language":               "vi",
		"flash_size":             16777216,
		"minimum_free_heap_size": 8388608,
		"mac_address":            c.cfg.DeviceMAC,
		"uuid":                   c.cfg.ClientID,
		"chip_model_name":        "Allwinner-R16-Tina",
		"application": map[string]string{
			"name":    "mina-tina-linux",
			"version": "1.0.0",
		},
	}

	body, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", otaURL, bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Device-Id", c.cfg.DeviceMAC)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("OTA request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	var otaResp map[string]interface{}
	if err := json.Unmarshal(respBody, &otaResp); err != nil {
		return fmt.Errorf("OTA JSON parse error: %w", err)
	}

	if code, ok := otaResp["code"].(string); ok && code != "" {
		c.onLog("OTA", fmt.Sprintf("MÃ KÍCH HOẠT: %s. Hãy truy cập https://xiaozhi.me để thêm thiết bị!", code))
	}

	if ws, ok := otaResp["websocket"].(map[string]interface{}); ok {
		if url, ok := ws["url"].(string); ok {
			c.cfg.WsURL = url
		}
		if token, ok := ws["token"].(string); ok {
			c.cfg.WsToken = token
		}
	}

	return nil
}

// Connect mở WebSocket tới máy chủ XiaoZhi
func (c *XiaoZhiClient) Connect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cfg.WsURL == "" {
		c.cfg.WsURL = "wss://api.tenclass.net/xiaozhi/v1/"
	}

	headers := http.Header{}
	if c.cfg.WsToken != "" {
		headers.Set("Authorization", "Bearer "+c.cfg.WsToken)
	}
	headers.Set("Protocol-Version", "1")
	headers.Set("Device-Id", c.cfg.DeviceMAC)
	headers.Set("Client-Id", c.cfg.ClientID)

	conn, _, err := websocket.DefaultDialer.Dial(c.cfg.WsURL, headers)
	if err != nil {
		return fmt.Errorf("websocket dial failed: %w", err)
	}

	c.conn = conn
	c.connected = true
	c.onLog("WS", fmt.Sprintf("Đã kết nối máy chủ giọng nói %s", c.cfg.WsURL))

	// Gửi Hello handshake
	hello := map[string]interface{}{
		"type":      "hello",
		"version":   1,
		"transport": "websocket",
		"features": map[string]bool{
			"mcp": true,
		},
		"audio_params": map[string]interface{}{
			"format":         "pcm", // Có thể dùng PCM trực tiếp hoặc Opus
			"sample_rate":    16000,
			"channels":       1,
			"frame_duration": 60,
		},
	}
	_ = conn.WriteJSON(hello)

	go c.readLoop()
	return nil
}

func (c *XiaoZhiClient) SendPcm(pcm []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.connected || c.conn == nil {
		return nil
	}
	return c.conn.WriteMessage(websocket.BinaryMessage, pcm)
}

func (c *XiaoZhiClient) readLoop() {
	defer func() {
		c.mu.Lock()
		c.connected = false
		if c.conn != nil {
			_ = c.conn.Close()
			c.conn = nil
		}
		c.mu.Unlock()
		c.onLog("WS", "Kết nối WebSocket đã ngắt, thử kết nối lại sau 3s...")
		time.Sleep(3 * time.Second)
		_ = c.Connect()
	}()

	for {
		msgType, msg, err := c.conn.ReadMessage()
		if err != nil {
			log.Printf("[WS] Read error: %v", err)
			return
		}

		if msgType == websocket.BinaryMessage {
			// Âm thanh phản hồi từ AI XiaoZhi -> chuyển ra loa ALSA
			_ = c.audio.WritePcm(msg)
			continue
		}

		if msgType == websocket.TextMessage {
			var event map[string]interface{}
			if err := json.Unmarshal(msg, &event); err != nil {
				continue
			}

			typ, _ := event["type"].(string)
			switch typ {
			case "hello":
				c.sessionID, _ = event["session_id"].(string)
				c.onLog("WS", fmt.Sprintf("Phiên làm việc sẵn sàng: %s", c.sessionID))

			case "mcp":
				c.handleMcpRequest(event)

			case "tts":
				state, _ := event["state"].(string)
				if state == "stop" {
					c.onLog("AI", "AI đã nói xong.")
				}
			}
		}
	}
}

// handleMcpRequest xử lý yêu cầu gọi hàm (Tool Call) từ AI XiaoZhi
func (c *XiaoZhiClient) handleMcpRequest(event map[string]interface{}) {
	payload, ok := event["payload"].(map[string]interface{})
	if !ok {
		return
	}

	method, _ := payload["method"].(string)
	id := payload["id"]

	if method == "tools/list" {
		c.replyMcpToolsList(id)
		return
	}

	if method == "tools/call" {
		params, _ := payload["params"].(map[string]interface{})
		name, _ := params["name"].(string)
		args, _ := params["arguments"].(map[string]interface{})

		c.onLog("MCP", fmt.Sprintf("AI gọi lệnh: %s (%v)", name, args))
		var resultText string
		var isErr bool

		if name == "self.robot.action" {
			actQuery, _ := args["action"].(string)
			res, err := ExecuteAction(actQuery)
			if err != nil {
				resultText = err.Error()
				isErr = true
			} else {
				resultText = res
			}
		} else {
			resultText = "Không hỗ trợ công cụ " + name
			isErr = true
		}

		reply := map[string]interface{}{
			"type": "mcp",
			"payload": map[string]interface{}{
				"jsonrpc": "2.0",
				"id":      id,
				"result": map[string]interface{}{
					"content": []map[string]string{
						{"type": "text", "text": resultText},
					},
					"isError": isErr,
				},
			},
		}
		c.mu.Lock()
		if c.conn != nil {
			_ = c.conn.WriteJSON(reply)
		}
		c.mu.Unlock()
	}
}

func (c *XiaoZhiClient) replyMcpToolsList(id interface{}) {
	tools := []map[string]interface{}{
		{
			"name":        "self.robot.action",
			"description": "Điều khiển cử động, thế võ, nhảy múa của robot người Robonova-II (MR-C3024FX).",
			"inputSchema": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"action": map[string]interface{}{
						"type":        "string",
						"description": "Tên hoặc ID hành động (ví dụ: 'bow', 'hands_up', 'walk_forward', 'martial_arts_1', 'dance_1', 'pushup_music')",
					},
				},
				"required": []string{"action"},
			},
		},
	}

	reply := map[string]interface{}{
		"type": "mcp",
		"payload": map[string]interface{}{
			"jsonrpc": "2.0",
			"id":      id,
			"result": map[string]interface{}{
				"tools": tools,
			},
		},
	}
	c.mu.Lock()
	if c.conn != nil {
		_ = c.conn.WriteJSON(reply)
	}
	c.mu.Unlock()
}
