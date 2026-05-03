package backend

import "time"

const (
	AppName    = "BiliCastHelper"
	Version    = "0.4.0-crossplatform"
	APIVersion = 1
)

type QualityPreference string

const (
	QualityMP4Safe   QualityPreference = "mp4Safe"
	QualityFLVTV     QualityPreference = "flvTV"
	QualityDashRemux QualityPreference = "dashRemux"
)

func ParseQualityPreference(raw string) QualityPreference {
	switch QualityPreference(raw) {
	case QualityFLVTV, QualityDashRemux, QualityMP4Safe:
		return QualityPreference(raw)
	default:
		return QualityMP4Safe
	}
}

type Config struct {
	Token             string            `json:"token"`
	APIVersion        int               `json:"apiVersion"`
	QualityPreference QualityPreference `json:"qualityPreference"`
}

type APIEnvelope struct {
	OK    bool      `json:"ok"`
	Data  any       `json:"data"`
	Error *APIError `json:"error"`
}

type APIError struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	HTTPStatus int    `json:"-"`
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

func NewAPIError(code, message string, status int) *APIError {
	return &APIError{Code: code, Message: message, HTTPStatus: status}
}

type Device struct {
	ID                     string `json:"id"`
	Name                   string `json:"name"`
	ModelName              string `json:"modelName,omitempty"`
	Manufacturer           string `json:"manufacturer,omitempty"`
	Location               string `json:"location,omitempty"`
	Available              bool   `json:"available"`
	AVTransportControlURL  string `json:"avTransportControlURL,omitempty"`
	AVTransportServiceType string `json:"avTransportServiceType,omitempty"`
}

type Candidate struct {
	URL     string `json:"url"`
	Kind    string `json:"kind"`
	Quality *int   `json:"quality,omitempty"`
	Mime    string `json:"mime,omitempty"`
	Codec   string `json:"codec,omitempty"`
}

type CastRequest struct {
	DeviceID    string      `json:"deviceId"`
	PageURL     string      `json:"pageUrl"`
	BV          string      `json:"bv,omitempty"`
	Title       string      `json:"title,omitempty"`
	CurrentTime float64     `json:"currentTime,omitempty"`
	Source      string      `json:"source,omitempty"`
	Candidates  []Candidate `json:"candidates,omitempty"`
}

type CastResult struct {
	SessionID  string `json:"sessionId"`
	DeviceName string `json:"deviceName"`
	StreamURL  string `json:"streamUrl"`
	Title      string `json:"title"`
	Tier       string `json:"tier"`
}

type SessionKind string

const (
	SessionDirect SessionKind = "direct"
	SessionDash   SessionKind = "dashRemux"
)

type StreamSession struct {
	ID          string
	Title       string
	DeviceID    string
	DeviceName  string
	Kind        SessionKind
	Tier        QualityPreference
	URL         string
	VideoURL    string
	AudioURL    string
	ContentType string
	Headers     map[string]string
	CreatedAt   time.Time
	ExpiresAt   time.Time
}
