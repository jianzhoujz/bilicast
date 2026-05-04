//go:build linux && amd64

package backend

import _ "embed"

//go:embed ffmpeg_assets/ffmpeg_linux_amd64
var embeddedFFmpegLinuxAMD64 []byte

func embeddedFFmpegForPlatform() (string, []byte) {
	return "ffmpeg", embeddedFFmpegLinuxAMD64
}
