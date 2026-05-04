package backend

import "testing"

func TestPlaceholderEmbeddedFFmpegIsIgnored(t *testing.T) {
	if path := LocateEmbeddedFFmpeg(); path != "" {
		t.Fatalf("placeholder embedded ffmpeg should be ignored, got %q", path)
	}
}
