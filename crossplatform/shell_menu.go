//go:build wails

package main

import (
	"runtime"

	"github.com/wailsapp/wails/v2/pkg/menu"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

type ShellIntegration struct {
	OS          string   `json:"os"`
	Surface     string   `json:"surface"`
	Description string   `json:"description"`
	Actions     []string `json:"actions"`
}

func (a *App) ShellIntegration() ShellIntegration {
	return ShellIntegrationForGOOS(runtime.GOOS)
}

func ShellIntegrationForGOOS(goos string) ShellIntegration {
	actions := []string{"show-window", "hide-window", "quit-application"}
	switch goos {
	case "windows":
		return ShellIntegration{OS: goos, Surface: "tray-native-menu", Description: "Windows tray/native menu support shows/hides the main window and can quit the application.", Actions: actions}
	case "linux":
		return ShellIntegration{OS: goos, Surface: "tray-native-menu", Description: "Linux tray/native menu support shows/hides the main window and can quit the application.", Actions: actions}
	default:
		return ShellIntegration{OS: goos, Surface: "background-menu", Description: "Desktop shell support shows/hides the main window and can quit the application.", Actions: actions}
	}
}

func BuildShellMenu(app *App) *menu.Menu {
	root := menu.NewMenu()

	bilicast := root.AddSubmenu("BiliCast")
	bilicast.AddText("Show BiliCastHelper", nil, func(_ *menu.CallbackData) { app.ShowWindow() })
	bilicast.AddText("Hide BiliCastHelper", nil, func(_ *menu.CallbackData) { app.HideWindow() })
	bilicast.AddSeparator()
	bilicast.AddText("Quit BiliCastHelper", nil, func(_ *menu.CallbackData) { app.QuitApp() })

	return root
}

func (a *App) ShowWindow() {
	if a.ctx == nil {
		return
	}
	wailsruntime.WindowShow(a.ctx)
}

func (a *App) HideWindow() {
	if a.ctx == nil {
		return
	}
	wailsruntime.WindowHide(a.ctx)
}

func (a *App) QuitApp() {
	if a.ctx == nil {
		return
	}
	wailsruntime.Quit(a.ctx)
}
