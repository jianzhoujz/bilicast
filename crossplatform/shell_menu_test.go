//go:build wails

package main

import "testing"

func TestShellIntegrationForGOOS(t *testing.T) {
	cases := map[string]string{
		"windows": "tray-native-menu",
		"linux":   "tray-native-menu",
	}
	for goos, want := range cases {
		got := ShellIntegrationForGOOS(goos)
		if got.Surface != want {
			t.Fatalf("%s surface = %q, want %q", goos, got.Surface, want)
		}
		if !contains(got.Actions, "quit-application") {
			t.Fatalf("%s actions = %#v, want quit-application", goos, got.Actions)
		}
	}
}

func TestBuildShellMenu(t *testing.T) {
	menu := BuildShellMenu(&App{})
	if menu == nil || len(menu.Items) != 1 {
		t.Fatalf("unexpected menu: %#v", menu)
	}
	var found bool
	for _, item := range menu.Items {
		if item.Label == "BiliCast" && item.SubMenu != nil {
			found = true
			if len(item.SubMenu.Items) != 4 {
				t.Fatalf("BiliCast tray menu items = %d, want 4", len(item.SubMenu.Items))
			}
			if item.SubMenu.Items[3].Label != "Quit BiliCastHelper" {
				t.Fatalf("last BiliCast tray menu item = %q, want Quit BiliCastHelper", item.SubMenu.Items[3].Label)
			}
		}
	}
	if !found {
		t.Fatal("BiliCast menu not found")
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
