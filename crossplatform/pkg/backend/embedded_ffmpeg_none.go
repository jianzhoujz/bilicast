//go:build !(linux && amd64) && !(windows && amd64)

package backend

func embeddedFFmpegForPlatform() (string, []byte) {
	return "", nil
}
