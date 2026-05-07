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
	"github.com/wailsapp/wails/v2/pkg/options/mac"
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
		Title:             "BiliCast",
		Width:             400,
		Height:            720,
		MinWidth:          360,
		MinHeight:         480,
		HideWindowOnClose: true,
		Menu:              BuildShellMenu(app),
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		Mac: &mac.Options{
			TitleBar:   mac.TitleBarDefault(),
			Appearance: mac.DefaultAppearance,
			About: &mac.AboutInfo{
				Title:   "BiliCast (Wails)",
				Message: "Cross-platform Wails build of BiliCast.",
			},
		},
		OnStartup: app.startup,
	})
	if err != nil {
		log.Fatal(err)
	}
}
