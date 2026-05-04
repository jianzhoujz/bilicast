//go:build windows && amd64

package backend

import _ "embed"

//go:embed ffmpeg_assets/ffmpeg_windows_amd64.exe
var embeddedFFmpegWindowsAMD64 []byte

func embeddedFFmpegForPlatform() (string, []byte) {
	return "ffmpeg.exe", embeddedFFmpegWindowsAMD64
}
