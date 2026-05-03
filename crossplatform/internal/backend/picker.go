package backend

import "sort"

type PickResult struct {
	Tier      QualityPreference
	Kind      SessionKind
	Direct    *Candidate
	DashVideo *Candidate
	DashAudio *Candidate
}

func PickCandidate(candidates []Candidate, preference QualityPreference, ffmpegAvailable bool) *PickResult {
	priority := []QualityPreference{QualityMP4Safe}
	switch preference {
	case QualityDashRemux:
		if ffmpegAvailable {
			priority = []QualityPreference{QualityDashRemux, QualityFLVTV, QualityMP4Safe}
		} else {
			priority = []QualityPreference{QualityFLVTV, QualityMP4Safe}
		}
	case QualityFLVTV:
		priority = []QualityPreference{QualityFLVTV, QualityMP4Safe}
	}
	for _, tier := range priority {
		switch tier {
		case QualityMP4Safe:
			if c := bestByKind(candidates, "mp4"); c != nil {
				return &PickResult{Tier: tier, Kind: SessionDirect, Direct: c}
			}
		case QualityFLVTV:
			if c := bestByKind(candidates, "flv"); c != nil {
				return &PickResult{Tier: tier, Kind: SessionDirect, Direct: c}
			}
		case QualityDashRemux:
			v := bestByKind(candidates, "dash-video")
			a := bestByKind(candidates, "dash-audio")
			if v != nil && a != nil {
				return &PickResult{Tier: tier, Kind: SessionDash, DashVideo: v, DashAudio: a}
			}
		}
	}
	return nil
}

func bestByKind(candidates []Candidate, kind string) *Candidate {
	filtered := make([]Candidate, 0)
	for _, c := range candidates {
		if c.Kind == kind && c.URL != "" {
			filtered = append(filtered, c)
		}
	}
	if len(filtered) == 0 {
		return nil
	}
	sort.SliceStable(filtered, func(i, j int) bool {
		return qualityValue(filtered[i]) > qualityValue(filtered[j])
	})
	return &filtered[0]
}

func qualityValue(c Candidate) int {
	if c.Quality == nil {
		return 0
	}
	return *c.Quality
}
