package backend

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
)

func DefaultConfigPath() string {
	if env := os.Getenv("BILICAST_CONFIG"); env != "" {
		return env
	}
	var base string
	switch runtime.GOOS {
	case "windows":
		base = os.Getenv("APPDATA")
		if base == "" {
			base = "."
		}
	default:
		base = os.Getenv("XDG_CONFIG_HOME")
		if base == "" {
			home, _ := os.UserHomeDir()
			base = filepath.Join(home, ".config")
		}
	}
	return filepath.Join(base, "BiliCastHelper", "config.json")
}

func LoadOrCreateConfig(path string) (Config, error) {
	if path == "" {
		path = DefaultConfigPath()
	}
	if token := os.Getenv("BILICAST_TOKEN"); token != "" {
		return Config{Token: token, APIVersion: APIVersion, QualityPreference: ParseQualityPreference(os.Getenv("BILICAST_QUALITY"))}, nil
	}
	if data, err := os.ReadFile(path); err == nil {
		var cfg Config
		if err := json.Unmarshal(data, &cfg); err == nil && cfg.Token != "" {
			if cfg.APIVersion == 0 {
				cfg.APIVersion = APIVersion
			}
			cfg.QualityPreference = ParseQualityPreference(string(cfg.QualityPreference))
			return cfg, nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return Config{}, err
	}
	cfg := Config{Token: GenerateToken(), APIVersion: APIVersion, QualityPreference: QualityMP4Safe}
	return cfg, SaveConfig(path, cfg)
}

func SaveConfig(path string, cfg Config) error {
	if path == "" {
		path = DefaultConfigPath()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}
