import Foundation
import BiliCastCore

public enum BilibiliCast {
    public struct Candidate: Sendable {
        public let url: URL
        /// "mp4" | "flv" | "dash-video" | "dash-audio"
        public let kind: String
        public let quality: Int?
        public let mime: String?
        public let codec: String?

        public init(url: URL, kind: String, quality: Int? = nil, mime: String? = nil, codec: String? = nil) {
            self.url = url
            self.kind = kind
            self.quality = quality
            self.mime = mime
            self.codec = codec
        }
    }

    public enum Selection: Sendable {
        case direct(url: URL, kind: String, quality: Int?)
        case muxedDash(videoURL: URL, audioURL: URL, videoQuality: Int?, audioQuality: Int?)
    }

    public struct PickResult: Sendable {
        public let selection: Selection
        public let tier: QualityPreference
    }

    /// Headers required by B站 CDN for a video URL to actually return bytes.
    public static let upstreamHeaders: [String: String] = [
        "Referer": "https://www.bilibili.com/",
        "Origin":  "https://www.bilibili.com",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    ]

    /// Picks the best stream selection given user preference and available candidates.
    /// Falls back across tiers if the preferred tier has no candidates.
    public static func pick(
        from candidates: [Candidate],
        preference: QualityPreference,
        ffmpegAvailable: Bool
    ) -> PickResult? {
        let priorityList: [QualityPreference]
        switch preference {
        case .dashRemux:
            priorityList = ffmpegAvailable
                ? [.dashRemux, .flvTV, .mp4Safe]
                : [.flvTV, .mp4Safe]
        case .flvTV:
            priorityList = [.flvTV, .mp4Safe]
        case .mp4Safe:
            priorityList = [.mp4Safe]
        }

        for tier in priorityList {
            switch tier {
            case .mp4Safe:
                let mp4 = candidates
                    .filter { $0.kind == "mp4" }
                    .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                if let best = mp4.first {
                    return PickResult(
                        selection: .direct(url: best.url, kind: "mp4", quality: best.quality),
                        tier: .mp4Safe
                    )
                }

            case .flvTV:
                let flv = candidates
                    .filter { $0.kind == "flv" }
                    .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                if let best = flv.first {
                    return PickResult(
                        selection: .direct(url: best.url, kind: "flv", quality: best.quality),
                        tier: .flvTV
                    )
                }

            case .dashRemux:
                guard ffmpegAvailable else { continue }
                let v = candidates
                    .filter { $0.kind == "dash-video" }
                    .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                let a = candidates
                    .filter { $0.kind == "dash-audio" }
                    .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                if let bv = v.first, let ba = a.first {
                    return PickResult(
                        selection: .muxedDash(
                            videoURL: bv.url,
                            audioURL: ba.url,
                            videoQuality: bv.quality,
                            audioQuality: ba.quality
                        ),
                        tier: .dashRemux
                    )
                }
            }
        }
        return nil
    }

    public static func parseCandidates(_ raw: Any?) -> [Candidate] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        var out: [Candidate] = []
        for entry in arr {
            guard let urlStr = entry["url"] as? String, let u = URL(string: urlStr) else { continue }
            let kind = (entry["kind"] as? String) ?? "mp4"
            let quality = entry["quality"] as? Int
            let mime = entry["mime"] as? String
            let codec = entry["codec"] as? String
            out.append(Candidate(url: u, kind: kind, quality: quality, mime: mime, codec: codec))
        }
        return out
    }
}
