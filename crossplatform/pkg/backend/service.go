package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

type ServiceOptions struct {
	ConfigPath  string
	ControlAddr string
	ProxyAddr   string
	PublicHost  string
}

type Service struct {
	mu         sync.RWMutex
	cfg        Config
	configPath string
	devices    map[string]Device
	sessions   map[string]StreamSession
	options    ServiceOptions
	ffmpegPath string
	dlna       *DLNAClient
}

func NewService(options ServiceOptions) (*Service, error) {
	cfg, err := LoadOrCreateConfig(options.ConfigPath)
	if err != nil {
		return nil, err
	}
	if options.ControlAddr == "" {
		options.ControlAddr = "127.0.0.1:18787"
	}
	if options.ProxyAddr == "" {
		options.ProxyAddr = "0.0.0.0:18788"
	}
	s := &Service{
		cfg:        cfg,
		configPath: options.ConfigPath,
		devices:    map[string]Device{},
		sessions:   map[string]StreamSession{},
		options:    options,
		ffmpegPath: LocateFFmpeg(),
		dlna:       &DLNAClient{},
	}
	s.loadDevicesFromEnv()
	return s, nil
}

func (s *Service) Token() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cfg.Token
}

func (s *Service) ControlAddr() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.options.ControlAddr
}

func (s *Service) ProxyAddr() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.options.ProxyAddr
}

func (s *Service) Health() map[string]any {
	return map[string]any{"app": AppName, "version": Version, "apiVersion": APIVersion}
}

func (s *Service) Status() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var current any
	now := time.Now()
	for _, session := range s.sessions {
		if session.ExpiresAt.After(now) {
			current = map[string]any{
				"sessionId":  session.ID,
				"deviceId":   session.DeviceID,
				"title":      session.Title,
				"deviceName": session.DeviceName,
				"tier":       session.Tier,
				"startedAt":  session.CreatedAt.Format(time.RFC3339),
			}
			break
		}
	}
	return map[string]any{
		"running":                  true,
		"currentSession":           current,
		"qualityPreference":        s.cfg.QualityPreference,
		"qualityPreferenceOptions": []string{string(QualityMP4Safe), string(QualityFLVTV), string(QualityDashRemux)},
		"ffmpegAvailable":          s.ffmpegPath != "",
		"controlAddr":              s.options.ControlAddr,
		"proxyAddr":                s.options.ProxyAddr,
		"clients":                  []string{"userscript", "browser-extension", "wails-desktop"},
	}
}

func (s *Service) Preferences() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return map[string]any{
		"qualityPreference":        s.cfg.QualityPreference,
		"qualityPreferenceOptions": []string{string(QualityMP4Safe), string(QualityFLVTV), string(QualityDashRemux)},
		"ffmpegAvailable":          s.ffmpegPath != "",
	}
}

func (s *Service) SetPreferences(pref QualityPreference) (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg.QualityPreference = ParseQualityPreference(string(pref))
	if os.Getenv("BILICAST_TOKEN") == "" {
		if err := SaveConfig(s.configPath, s.cfg); err != nil {
			return nil, err
		}
	}
	return map[string]any{"qualityPreference": s.cfg.QualityPreference, "ffmpegAvailable": s.ffmpegPath != ""}, nil
}

func (s *Service) Devices() []Device {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Device, 0, len(s.devices))
	for _, d := range s.devices {
		out = append(out, d)
	}
	return out
}

func (s *Service) RefreshDevices(ctx context.Context) int {
	// Try SSDP discovery first.
	if discovered, err := discoverDevices(ctx, 3*time.Second); err == nil && len(discovered) > 0 {
		s.mu.Lock()
		s.devices = make(map[string]Device, len(discovered))
		for _, d := range discovered {
			s.devices[d.ID] = d
		}
		s.mu.Unlock()
		return len(discovered)
	}
	// Fallback to env-configured devices.
	s.loadDevicesFromEnv()
	return len(s.Devices())
}

func (s *Service) Cast(ctx context.Context, req CastRequest) (*CastResult, error) {
	if req.DeviceID == "" || req.PageURL == "" {
		return nil, NewAPIError("BAD_REQUEST", "deviceId and pageUrl required", 400)
	}
	if req.Title == "" {
		req.Title = "BiliCast"
	}
	s.mu.RLock()
	device, ok := s.devices[req.DeviceID]
	pref := s.cfg.QualityPreference
	ffmpegAvailable := s.ffmpegPath != ""
	s.mu.RUnlock()
	if !ok {
		return nil, NewAPIError("NO_DEVICE", "device not found", 404)
	}
	pick := PickCandidate(req.Candidates, pref, ffmpegAvailable)
	if pick == nil {
		return nil, NewAPIError("NO_PLAYABLE_STREAM", "no playable stream candidate", 422)
	}
	session := StreamSession{
		ID:         "cast_" + GenerateToken()[:16],
		Title:      req.Title,
		DeviceID:   device.ID,
		DeviceName: device.Name,
		Kind:       pick.Kind,
		Tier:       pick.Tier,
		Headers: map[string]string{
			"Referer":    "https://www.bilibili.com/",
			"Origin":     "https://www.bilibili.com",
			"User-Agent": "Mozilla/5.0 BiliCast/" + Version,
		},
		CreatedAt: time.Now(),
		ExpiresAt: time.Now().Add(6 * time.Hour),
	}
	if pick.Kind == SessionDirect {
		session.URL = pick.Direct.URL
		session.ContentType = contentTypeFor(pick.Direct.Kind)
	} else {
		session.VideoURL = pick.DashVideo.URL
		session.AudioURL = pick.DashAudio.URL
		session.ContentType = "video/mp2t"
	}
	streamURL := s.streamURL(session.ID)
	s.mu.Lock()
	s.sessions[session.ID] = session
	s.mu.Unlock()
	if device.AVTransportControlURL != "" {
		if err := s.dlna.Play(ctx, device, streamURL); err != nil {
			s.mu.Lock()
			delete(s.sessions, session.ID)
			s.mu.Unlock()
			return nil, NewAPIError("DLNA_PLAY_FAILED", err.Error(), 502)
		}
	}
	return &CastResult{SessionID: session.ID, DeviceName: device.Name, StreamURL: streamURL, Title: req.Title, Tier: string(pick.Tier)}, nil
}

func (s *Service) StopCast(ctx context.Context, deviceID string) error {
	s.mu.Lock()
	device, ok := s.devices[deviceID]
	if !ok {
		s.mu.Unlock()
		return NewAPIError("NO_DEVICE", "device not found", 404)
	}
	for id, session := range s.sessions {
		if session.DeviceID == deviceID {
			delete(s.sessions, id)
		}
	}
	s.mu.Unlock()
	if device.AVTransportControlURL != "" {
		return s.dlna.Stop(ctx, device)
	}
	return nil
}

func (s *Service) Session(id string) (StreamSession, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	session, ok := s.sessions[id]
	if !ok || time.Now().After(session.ExpiresAt) {
		return StreamSession{}, false
	}
	return session, true
}

func (s *Service) loadDevicesFromEnv() {
	raw := os.Getenv("BILICAST_DEVICES_JSON")
	devices := map[string]Device{}
	if raw != "" {
		var list []Device
		if err := json.Unmarshal([]byte(raw), &list); err == nil {
			for _, d := range list {
				if d.ID == "" {
					d.ID = d.Name
				}
				if d.Name == "" {
					d.Name = d.ID
				}
				if d.AVTransportServiceType == "" {
					d.AVTransportServiceType = "urn:schemas-upnp-org:service:AVTransport:1"
				}
				d.Available = true
				devices[d.ID] = d
			}
		}
	}
	if len(devices) == 0 && os.Getenv("BILICAST_ALLOW_MOCK_DEVICE") == "1" {
		devices["mock-tv"] = Device{ID: "mock-tv", Name: "Mock DLNA Renderer", ModelName: "Development", Manufacturer: "BiliCast", Available: true}
	}
	s.mu.Lock()
	s.devices = devices
	s.mu.Unlock()
}

func (s *Service) streamURL(sessionID string) string {
	host := s.options.PublicHost
	if host == "" {
		host = os.Getenv("BILICAST_PUBLIC_HOST")
	}
	if host == "" {
		host = firstUsableHost(s.options.ProxyAddr)
	}
	return "http://" + host + "/stream/" + url.PathEscape(sessionID) + "/video"
}

func firstUsableHost(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return "127.0.0.1:18788"
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = firstLANIP()
	}
	return net.JoinHostPort(host, port)
}

func firstLANIP() string {
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipNet.IP.To4()
			if ip != nil && !ip.IsLoopback() {
				return ip.String()
			}
		}
	}
	return "127.0.0.1"
}

func contentTypeFor(kind string) string {
	switch strings.ToLower(kind) {
	case "flv":
		return "video/x-flv"
	default:
		return "video/mp4"
	}
}

func LocateFFmpeg() string {
	name := "ffmpeg"
	if runtime.GOOS == "windows" {
		name = "ffmpeg.exe"
	}
	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		for _, candidate := range []string{
			filepath.Join(exeDir, name),
			filepath.Join(exeDir, "bin", name),
			filepath.Join(exeDir, "resources", name),
		} {
			if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
				return candidate
			}
		}
	}
	for _, candidate := range []string{"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	if path, err := exec.LookPath(name); err == nil {
		return path
	}
	if name != "ffmpeg" {
		if path, err := exec.LookPath("ffmpeg"); err == nil {
			return path
		}
	}
	return ""
}

func (s *Service) FFmpegCommand(ctx context.Context, session StreamSession) (*exec.Cmd, error) {
	if s.ffmpegPath == "" {
		return nil, fmt.Errorf("ffmpeg not found")
	}
	headers := "Referer: https://www.bilibili.com/\r\nUser-Agent: Mozilla/5.0 BiliCast/" + Version + "\r\n"
	cmd := exec.CommandContext(ctx, s.ffmpegPath,
		"-loglevel", "warning", "-hide_banner", "-y",
		"-headers", headers, "-i", session.VideoURL,
		"-headers", headers, "-i", session.AudioURL,
		"-map", "0:v:0", "-map", "1:a:0",
		"-c", "copy", "-bsf:a", "aac_adtstoasc",
		"-f", "mpegts", "-flush_packets", "1", "pipe:1",
	)
	return cmd, nil
}
