//go:build wails

package main

import (
	"context"
	"embed"
	"log"

	"github.com/jianzhoujz/bilicast/crossplatform/pkg/backend"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed frontend/dist
var assets embed.FS

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	svc, err := backend.NewService(backend.ServiceOptions{})
	if err != nil {
		log.Fatal(err)
	}
	svc.StartControlServer(ctx)
	svc.StartProxyServer(ctx)
	app := NewApp()
	err = wails.Run(&options.App{
		Title:             "BiliCastHelper",
		Width:             980,
		Height:            680,
		HideWindowOnClose: true,
		Menu:              BuildShellMenu(app),
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		OnStartup: app.startup,
	})
	if err != nil {
		log.Fatal(err)
	}
}
