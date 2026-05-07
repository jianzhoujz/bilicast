package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/jianzhoujz/bilicast/crossplatform/pkg/backend"
)

func main() {
	var opts backend.ServiceOptions
	flag.StringVar(&opts.ConfigPath, "config", "", "config file path")
	flag.StringVar(&opts.ControlAddr, "control-addr", getenv("BILICAST_CONTROL_ADDR", "127.0.0.1:18787"), "control API listen address")
	flag.StringVar(&opts.ProxyAddr, "proxy-addr", getenv("BILICAST_PROXY_ADDR", "0.0.0.0:18788"), "stream proxy listen address")
	flag.StringVar(&opts.PublicHost, "public-host", os.Getenv("BILICAST_PUBLIC_HOST"), "host:port advertised to DLNA renderers")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	svc, err := backend.NewService(opts)
	if err != nil {
		log.Fatal(err)
	}
	control := &http.Server{Addr: opts.ControlAddr, Handler: svc.ControlHandler()}
	proxy := &http.Server{Addr: opts.ProxyAddr, Handler: svc.ProxyHandler()}

	go func() {
		fmt.Printf("BiliCast control API listening on http://%s\n", opts.ControlAddr)
		fmt.Printf("Pairing token: %s\n", svc.Token())
		if err := control.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("control server: %v", err)
		}
	}()
	go func() {
		fmt.Printf("BiliCast stream proxy listening on http://%s\n", opts.ProxyAddr)
		if err := proxy.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("proxy server: %v", err)
		}
	}()

	<-ctx.Done()
	_ = control.Shutdown(context.Background())
	_ = proxy.Shutdown(context.Background())
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
