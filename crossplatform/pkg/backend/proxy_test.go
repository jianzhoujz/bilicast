package backend

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func TestProxyForwardsRangeAndHeaders(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Range") != "bytes=1-3" {
			t.Fatalf("range header = %q", r.Header.Get("Range"))
		}
		if r.Header.Get("Referer") != "https://www.bilibili.com/" {
			t.Fatalf("referer header = %q", r.Header.Get("Referer"))
		}
		w.Header().Set("Content-Type", "video/mp4")
		w.Header().Set("Content-Range", "bytes 1-3/5")
		w.WriteHeader(http.StatusPartialContent)
		_, _ = w.Write([]byte("bcd"))
	}))
	defer upstream.Close()

	svc, err := NewService(ServiceOptions{ConfigPath: filepath.Join(t.TempDir(), "config.json")})
	if err != nil {
		t.Fatal(err)
	}
	svc.sessions["cast_test"] = StreamSession{
		ID: "cast_test", Kind: SessionDirect, URL: upstream.URL, ContentType: "video/mp4",
		Headers: map[string]string{"Referer": "https://www.bilibili.com/"}, CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour),
	}
	proxy := httptest.NewServer(svc.ProxyHandler())
	defer proxy.Close()

	req, _ := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/stream/cast_test/video", proxy.URL), nil)
	req.Header.Set("Range", "bytes=1-3")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusPartialContent {
		t.Fatalf("proxy status = %d", res.StatusCode)
	}
	if res.Header.Get("Content-Range") != "bytes 1-3/5" {
		t.Fatalf("content-range = %q", res.Header.Get("Content-Range"))
	}
}

func TestDashHeadDoesNotRequireFFmpeg(t *testing.T) {
	svc, err := NewService(ServiceOptions{ConfigPath: filepath.Join(t.TempDir(), "config.json")})
	if err != nil {
		t.Fatal(err)
	}
	svc.ffmpegPath = ""
	svc.sessions["cast_dash"] = StreamSession{
		ID: "cast_dash", Kind: SessionDash, VideoURL: "https://example.test/video.m4s", AudioURL: "https://example.test/audio.m4s",
		CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour),
	}
	proxy := httptest.NewServer(svc.ProxyHandler())
	defer proxy.Close()

	res, err := http.Head(fmt.Sprintf("%s/stream/cast_dash/video", proxy.URL))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("HEAD status = %d", res.StatusCode)
	}
	if res.Header.Get("Accept-Ranges") != "none" {
		t.Fatalf("accept-ranges = %q", res.Header.Get("Accept-Ranges"))
	}
}
