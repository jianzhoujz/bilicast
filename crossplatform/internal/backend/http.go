package backend

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
)

const APIPrefix = "/api/bilicast"

func (s *Service) ControlHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", s.handleConsole)
	mux.HandleFunc("GET /console", s.handleConsole)
	s.addAPIRoutes(mux, APIPrefix)
	mux.HandleFunc("GET "+APIPrefix+"/pairing/token", s.handlePairingToken)
	// Compatibility aliases for the existing userscript / browser extension API.
	// New HTTP console and daemon docs use APIPrefix to avoid generic /api conflicts.
	s.addAPIRoutes(mux, "/api")
	return withCORS(mux)
}

func (s *Service) addAPIRoutes(mux *http.ServeMux, prefix string) {
	mux.HandleFunc("GET "+prefix+"/health", s.handleHealth)
	mux.HandleFunc("GET "+prefix+"/pairing/status", s.handlePairingStatus)
	mux.HandleFunc("GET "+prefix+"/devices", s.withToken(s.handleDevices))
	mux.HandleFunc("POST "+prefix+"/devices/refresh", s.withToken(s.handleRefreshDevices))
	mux.HandleFunc("GET "+prefix+"/status", s.withToken(s.handleStatus))
	mux.HandleFunc("GET "+prefix+"/preferences", s.withToken(s.handlePreferences))
	mux.HandleFunc("PUT "+prefix+"/preferences", s.withToken(s.handleSetPreferences))
	mux.HandleFunc("POST "+prefix+"/cast", s.withToken(s.handleCast))
	mux.HandleFunc("POST "+prefix+"/cast/stop", s.withToken(s.handleStopCast))
}

func (s *Service) StartControlServer(ctx context.Context) *http.Server {
	srv := &http.Server{Addr: s.options.ControlAddr, Handler: s.ControlHandler()}
	go func() {
		<-ctx.Done()
		_ = srv.Shutdown(context.Background())
	}()
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("control server failed", "err", err)
		}
	}()
	return srv
}

func (s *Service) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeOK(w, s.Health())
}

func (s *Service) handlePairingStatus(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-BiliCast-Token")
	writeOK(w, map[string]any{"paired": provided != "" && ConstantTimeEqual(provided, s.Token())})
}

func (s *Service) handlePairingToken(w http.ResponseWriter, r *http.Request) {
	writeOK(w, map[string]any{"token": s.Token()})
}

func (s *Service) handleDevices(w http.ResponseWriter, r *http.Request) {
	writeOK(w, map[string]any{"devices": s.Devices()})
}

func (s *Service) handleRefreshDevices(w http.ResponseWriter, r *http.Request) {
	writeOK(w, map[string]any{"count": s.RefreshDevices(r.Context())})
}

func (s *Service) handleStatus(w http.ResponseWriter, r *http.Request) {
	writeOK(w, s.Status())
}

func (s *Service) handlePreferences(w http.ResponseWriter, r *http.Request) {
	writeOK(w, s.Preferences())
}

func (s *Service) handleSetPreferences(w http.ResponseWriter, r *http.Request) {
	var body struct {
		QualityPreference string `json:"qualityPreference"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, NewAPIError("BAD_REQUEST", "JSON body required", 400))
		return
	}
	data, err := s.SetPreferences(ParseQualityPreference(body.QualityPreference))
	if err != nil {
		writeError(w, NewAPIError("UNKNOWN_ERROR", err.Error(), 500))
		return
	}
	writeOK(w, data)
}

func (s *Service) handleCast(w http.ResponseWriter, r *http.Request) {
	var req CastRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, NewAPIError("BAD_REQUEST", "JSON body required", 400))
		return
	}
	result, err := s.Cast(r.Context(), req)
	if err != nil {
		writeError(w, apiErr(err))
		return
	}
	writeOK(w, result)
}

func (s *Service) handleStopCast(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"deviceId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceID == "" {
		writeError(w, NewAPIError("BAD_REQUEST", "deviceId required", 400))
		return
	}
	if err := s.StopCast(r.Context(), req.DeviceID); err != nil {
		writeError(w, apiErr(err))
		return
	}
	writeOK(w, map[string]any{"deviceId": req.DeviceID})
}

func (s *Service) withToken(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		provided := r.Header.Get("X-BiliCast-Token")
		if provided == "" {
			writeError(w, NewAPIError("TOKEN_MISSING", "X-BiliCast-Token required", 401))
			return
		}
		if !ConstantTimeEqual(provided, s.Token()) {
			writeError(w, NewAPIError("TOKEN_INVALID", "invalid token", 403))
			return
		}
		next(w, r)
	}
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" || allowedOrigin(origin) {
			if origin != "" {
				w.Header().Set("Access-Control-Allow-Origin", origin)
			}
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-BiliCast-Token")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func allowedOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	switch u.Scheme {
	case "chrome-extension", "moz-extension":
		return u.Host != ""
	case "http":
		host := strings.ToLower(u.Hostname())
		return host == "127.0.0.1" || host == "localhost" || host == "::1"
	default:
		return false
	}
}

func writeOK(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(APIEnvelope{OK: true, Data: data, Error: nil})
}

func writeError(w http.ResponseWriter, err *APIError) {
	if err.HTTPStatus == 0 {
		err.HTTPStatus = 500
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(err.HTTPStatus)
	_ = json.NewEncoder(w).Encode(APIEnvelope{OK: false, Data: nil, Error: err})
}

func apiErr(err error) *APIError {
	var api *APIError
	if errors.As(err, &api) {
		return api
	}
	return NewAPIError("UNKNOWN_ERROR", err.Error(), 500)
}
