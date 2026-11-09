package main

import (
	"fmt"
	"io"
	"log"
	"os/exec"
	"sync"
)

type AudioEngine struct {
	recCmd    *exec.Cmd
	recStdout io.ReadCloser

	playCmd   *exec.Cmd
	playStdin io.WriteCloser

	mu      sync.Mutex
	running bool
}

func NewAudioEngine() *AudioEngine {
	return &AudioEngine{}
}

// StartRecording mở luồng thu âm ALSA 16kHz 16-bit Mono (1920 bytes/60ms)
func (a *AudioEngine) StartRecording(onFrame func([]byte)) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.running {
		return nil
	}

	cmd := exec.Command("arecord",
		"-D", "default",
		"-r", "16000",
		"-c", "1",
		"-f", "S16_LE",
		"-t", "raw",
		"-q",
	)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("arecord StdoutPipe error: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("arecord Start error: %w", err)
	}

	a.recCmd = cmd
	a.recStdout = stdout
	a.running = true

	go func() {
		buf := make([]byte, 1920) // 960 samples @ 16kHz = 60ms
		for a.running {
			n, err := io.ReadFull(stdout, buf)
			if err != nil {
				if a.running {
					log.Printf("[AUDIO] Lỗi đọc arecord: %v", err)
				}
				break
			}
			if n == 1920 {
				cp := make([]byte, 1920)
				copy(cp, buf)
				onFrame(cp)
			}
		}
	}()

	log.Printf("[AUDIO] arecord 16kHz mono đã khởi động")
	return nil
}

// InitPlayer mở luồng phát loa ALSA qua aplay
func (a *AudioEngine) InitPlayer(sampleRate int) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.playCmd != nil {
		_ = a.playStdin.Close()
		_ = a.playCmd.Process.Kill()
		_ = a.playCmd.Wait()
	}

	cmd := exec.Command("aplay",
		"-D", "default",
		"-r", fmt.Sprintf("%d", sampleRate),
		"-c", "1",
		"-f", "S16_LE",
		"-t", "raw",
		"-q",
	)

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("aplay StdinPipe error: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("aplay Start error: %w", err)
	}

	a.playCmd = cmd
	a.playStdin = stdin
	log.Printf("[AUDIO] aplay %dHz mono đã khởi động", sampleRate)
	return nil
}

// WritePcm gửi các byte PCM ra loa
func (a *AudioEngine) WritePcm(pcm []byte) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.playStdin == nil {
		return fmt.Errorf("aplay chưa khởi tạo")
	}

	_, err := a.playStdin.Write(pcm)
	return err
}

func (a *AudioEngine) Stop() {
	a.mu.Lock()
	defer a.mu.Unlock()

	a.running = false
	if a.recCmd != nil && a.recCmd.Process != nil {
		_ = a.recCmd.Process.Kill()
		_ = a.recCmd.Wait()
		a.recCmd = nil
	}
	if a.playCmd != nil && a.playCmd.Process != nil {
		_ = a.playStdin.Close()
		_ = a.playCmd.Process.Kill()
		_ = a.playCmd.Wait()
		a.playCmd = nil
	}
}
