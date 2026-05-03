package backend

import "testing"

func qi(v int) *int { return &v }

func TestPickCandidateFallbacks(t *testing.T) {
	candidates := []Candidate{
		{URL: "https://example.test/720.mp4", Kind: "mp4", Quality: qi(64)},
		{URL: "https://example.test/1080.flv", Kind: "flv", Quality: qi(80)},
		{URL: "https://example.test/video.m4s", Kind: "dash-video", Quality: qi(120)},
		{URL: "https://example.test/audio.m4s", Kind: "dash-audio", Quality: qi(30280)},
	}
	if got := PickCandidate(candidates, QualityDashRemux, true); got == nil || got.Tier != QualityDashRemux || got.Kind != SessionDash {
		t.Fatalf("dashRemux with ffmpeg should pick dash, got %#v", got)
	}
	if got := PickCandidate(candidates, QualityDashRemux, false); got == nil || got.Tier != QualityFLVTV || got.Direct.Kind != "flv" {
		t.Fatalf("dashRemux without ffmpeg should fall back to flv, got %#v", got)
	}
	if got := PickCandidate(candidates, QualityMP4Safe, true); got == nil || got.Tier != QualityMP4Safe || got.Direct.Kind != "mp4" {
		t.Fatalf("mp4Safe should pick mp4 only, got %#v", got)
	}
}
