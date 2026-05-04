package backend

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

const minEmbeddedFFmpegSize = 1_000_000

func LocateEmbeddedFFmpeg() string {
	name, data := embeddedFFmpegForPlatform()
	if name == "" || len(data) < minEmbeddedFFmpegSize {
		return ""
	}

	cacheRoot, err := os.UserCacheDir()
	if err != nil || cacheRoot == "" {
		cacheRoot = os.TempDir()
	}
	sum := sha256.Sum256(data)
	dir := filepath.Join(cacheRoot, AppName, "ffmpeg", Version, fmt.Sprintf("%s-%s-%x", runtime.GOOS, runtime.GOARCH, sum[:8]))
	path := filepath.Join(dir, name)

	if info, err := os.Stat(path); err == nil && !info.IsDir() && info.Size() == int64(len(data)) {
		if runtime.GOOS != "windows" {
			_ = os.Chmod(path, 0o755)
		}
		return path
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return ""
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o755); err != nil {
		return ""
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(tmp, 0o755)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return ""
	}
	return path
}
