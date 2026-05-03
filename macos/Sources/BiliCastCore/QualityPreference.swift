import Foundation

public enum QualityPreference: String, Codable, CaseIterable, Sendable {
    /// Single-file MP4 via B站 html5 path. Capped at 720P. Most stable.
    case mp4Safe
    /// 1080P FLV via TV-signed playurl. Experimental: appkey/secret may rotate.
    case flvTV
    /// DASH (separate audio/video) muxed locally via ffmpeg. Highest quality.
    case dashRemux

    public var displayName: String {
        switch self {
        case .mp4Safe:    return "标准（720P MP4）"
        case .flvTV:      return "高清（1080P FLV，实验性）"
        case .dashRemux:  return "极清（ffmpeg 实时合流）"
        }
    }

    public var summary: String {
        switch self {
        case .mp4Safe:
            return "兼容性最好。所有视频都能投，但清晰度只到 720P。"
        case .flvTV:
            return "用 B 站 TV 接口拿 1080P FLV。可能因 B 站策略调整失效。"
        case .dashRemux:
            return "Mac 实时合流后推给电视。最高清，但 Mac 必须一直开着。"
        }
    }

    public var pros: [String] {
        switch self {
        case .mp4Safe:
            return ["几乎所有公开视频都能投", "零额外依赖", "B 站接口最稳定，不会突然失效"]
        case .flvTV:
            return ["原生 1080P FLV，画质明显好于标准模式", "电视直连 B 站 CDN，Mac 关了也能继续看"]
        case .dashRemux:
            return ["最高清晰度（1080P60 / 4K / HDR 都可以）", "覆盖最广，DASH-only 视频也能投"]
        }
    }

    public var cons: [String] {
        switch self {
        case .mp4Safe:
            return ["清晰度封顶 720P，再高的画质 B 站不给单文件"]
        case .flvTV:
            return ["B 站 TV 签名密钥可能被换，到时这一档会失效", "失效会自动降级到标准模式，不会卡住"]
        case .dashRemux:
            return ["Mac 必须保持开机和运行，关掉电视立刻断流", "占用 Mac 一些 CPU 和网络上行带宽", "需要 ffmpeg（已自动随 App 安装）"]
        }
    }

    public var note: String? {
        switch self {
        case .mp4Safe: return nil
        case .flvTV:   return "实验性档位。建议偶尔用，主用还是标准模式或极清模式。"
        case .dashRemux: return "电视播放期间不要退出 BiliCastHelper。"
        }
    }
}
