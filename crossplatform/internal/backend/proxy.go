package backend

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
)

func (s *Service) ProxyHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /stream/{sessionId}/video", s.handleStream)
	mux.HandleFunc("HEAD /stream/{sessionId}/video", s.handleStream)
	return mux
}

func (s *Service) StartProxyServer(ctx context.Context) *http.Server {
	srv := &http.Server{Addr: s.options.ProxyAddr, Handler: s.ProxyHandler()}
	go func() {
		<-ctx.Done()
		_ = srv.Shutdown(context.Background())
	}()
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("proxy server failed", "err", err)
		}
	}()
	return srv
}

func (s *Service) handleStream(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("sessionId")
	session, ok := s.Session(sessionID)
	if !ok {
		http.Error(w, "Session Not Found", http.StatusNotFound)
		return
	}
	if session.Kind == SessionDash {
		s.streamDash(w, r, session)
		return
	}
	s.streamDirect(w, r, session)
}

func (s *Service) streamDirect(w http.ResponseWriter, r *http.Request, session StreamSession) {
	method := http.MethodGet
	if r.Method == http.MethodHead {
		method = http.MethodHead
	}
	req, err := http.NewRequestWithContext(r.Context(), method, session.URL, nil)
	if err != nil {
		http.Error(w, "Bad Upstream URL", http.StatusBadGateway)
		return
	}
	for k, v := range session.Headers {
		req.Header.Set(k, v)
	}
	for _, h := range []string{"Range", "If-Range"} {
		if value := r.Header.Get(h); value != "" {
			req.Header.Set(h, value)
		}
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, "Upstream Failed", http.StatusBadGateway)
		return
	}
	defer res.Body.Close()
	copyHeader(w.Header(), res.Header)
	if w.Header().Get("Content-Type") == "" {
		w.Header().Set("Content-Type", session.ContentType)
	}
	w.WriteHeader(res.StatusCode)
	if r.Method != http.MethodHead {
		_, _ = io.Copy(w, res.Body)
	}
}

func (s *Service) streamDash(w http.ResponseWriter, r *http.Request, session StreamSession) {
	if r.Header.Get("Range") != "" {
		http.Error(w, "Range Not Supported", http.StatusRequestedRangeNotSatisfiable)
		return
	}
	w.Header().Set("Content-Type", "video/mp2t")
	w.Header().Set("Accept-Ranges", "none")
	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}
	cmd, err := s.FFmpegCommand(r.Context(), session)
	if err != nil {
		http.Error(w, "ffmpeg unavailable", http.StatusBadGateway)
		return
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		http.Error(w, "ffmpeg stdout failed", http.StatusBadGateway)
		return
	}
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		http.Error(w, "ffmpeg start failed", http.StatusBadGateway)
		return
	}
	go func() {
		if stderr != nil {
			_, _ = io.Copy(io.Discard, stderr)
		}
	}()
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, stdout)
	_ = cmd.Wait()
}

func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}
