package backend

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func newTestService(t *testing.T) *Service {
	t.Helper()
	t.Setenv("BILICAST_ALLOW_MOCK_DEVICE", "1")
	svc, err := NewService(ServiceOptions{ConfigPath: filepath.Join(t.TempDir(), "config.json"), ProxyAddr: "127.0.0.1:18788", PublicHost: "127.0.0.1:18788"})
	if err != nil {
		t.Fatal(err)
	}
	return svc
}

func TestControlAPIAuthPreferencesAndCast(t *testing.T) {
	svc := newTestService(t)
	h := svc.ControlHandler()

	console := httptest.NewRecorder()
	h.ServeHTTP(console, httptest.NewRequest(http.MethodGet, "/console", nil))
	if console.Code != http.StatusOK || console.Header().Get("Content-Type") != "text/html; charset=utf-8" {
		t.Fatalf("console response = %d %q", console.Code, console.Header().Get("Content-Type"))
	}

	health := httptest.NewRecorder()
	h.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/api/bilicast/health", nil))
	if health.Code != http.StatusOK {
		t.Fatalf("health status = %d", health.Code)
	}
	legacyHealth := httptest.NewRecorder()
	h.ServeHTTP(legacyHealth, httptest.NewRequest(http.MethodGet, "/api/health", nil))
	if legacyHealth.Code != http.StatusOK {
		t.Fatalf("legacy health status = %d", legacyHealth.Code)
	}
	pairingToken := httptest.NewRecorder()
	h.ServeHTTP(pairingToken, httptest.NewRequest(http.MethodGet, "/api/bilicast/pairing/token", nil))
	if pairingToken.Code != http.StatusOK || !bytes.Contains(pairingToken.Body.Bytes(), []byte(svc.Token())) {
		t.Fatalf("pairing token response = %d body=%s", pairingToken.Code, pairingToken.Body.String())
	}

	missing := httptest.NewRecorder()
	h.ServeHTTP(missing, httptest.NewRequest(http.MethodGet, "/api/bilicast/status", nil))
	if missing.Code != http.StatusUnauthorized {
		t.Fatalf("missing token status = %d", missing.Code)
	}

	prefBody := bytes.NewBufferString(`{"qualityPreference":"flvTV"}`)
	prefReq := httptest.NewRequest(http.MethodPut, "/api/bilicast/preferences", prefBody)
	prefReq.Header.Set("X-BiliCast-Token", svc.Token())
	pref := httptest.NewRecorder()
	h.ServeHTTP(pref, prefReq)
	if pref.Code != http.StatusOK {
		t.Fatalf("preferences status = %d body=%s", pref.Code, pref.Body.String())
	}

	castPayload := map[string]any{
		"deviceId": "mock-tv",
		"pageUrl":  "https://www.bilibili.com/video/BV1xx411c7mD",
		"title":    "demo",
		"candidates": []map[string]any{
			{"url": "https://example.test/video.mp4", "kind": "mp4", "quality": 64},
			{"url": "https://example.test/video.flv", "kind": "flv", "quality": 80},
		},
	}
	body, _ := json.Marshal(castPayload)
	castReq := httptest.NewRequest(http.MethodPost, "/api/bilicast/cast", bytes.NewReader(body))
	castReq.Header.Set("X-BiliCast-Token", svc.Token())
	cast := httptest.NewRecorder()
	h.ServeHTTP(cast, castReq)
	if cast.Code != http.StatusOK {
		t.Fatalf("cast status = %d body=%s", cast.Code, cast.Body.String())
	}
	var envelope APIEnvelope
	if err := json.Unmarshal(cast.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	data := envelope.Data.(map[string]any)
	if data["tier"] != string(QualityFLVTV) {
		t.Fatalf("tier = %v", data["tier"])
	}
}

func TestLoadOrCreateConfigHonorsEnvToken(t *testing.T) {
	t.Setenv("BILICAST_TOKEN", "fixed-token")
	t.Setenv("BILICAST_QUALITY", "dashRemux")
	cfg, err := LoadOrCreateConfig(filepath.Join(t.TempDir(), "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Token != "fixed-token" || cfg.QualityPreference != QualityDashRemux {
		t.Fatalf("unexpected cfg: %#v", cfg)
	}
}

func TestAllowedOrigin(t *testing.T) {
	allowed := []string{
		"http://127.0.0.1:18787",
		"http://localhost:18787",
		"http://[::1]:18787",
		"chrome-extension://abcdef",
		"moz-extension://abcdef",
	}
	for _, origin := range allowed {
		if !allowedOrigin(origin) {
			t.Fatalf("origin should be allowed: %s", origin)
		}
	}

	blocked := []string{
		"https://127.0.0.1:18787",
		"http://127.0.0.1.example.com",
		"http://localhost.example.com",
		"https://example.com",
		"file://local",
	}
	for _, origin := range blocked {
		if allowedOrigin(origin) {
			t.Fatalf("origin should be blocked: %s", origin)
		}
	}
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
