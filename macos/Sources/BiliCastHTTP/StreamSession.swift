import Foundation
import os
import BiliCastCore

public struct StreamSession: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case direct(url: URL, headers: [String: String])
        case muxedDash(videoURL: URL, audioURL: URL, headers: [String: String])
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let tier: QualityPreference   // which tier this session was created for
    public let createdAt: Date
    public var expiresAt: Date

    public init(
        id: String,
        kind: Kind,
        title: String,
        tier: QualityPreference,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.tier = tier
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public final class StreamSessionStore: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<[String: StreamSession]>(initialState: [:])

    public init() {}

    @discardableResult
    public func createDirect(
        upstream: URL,
        headers: [String: String] = [:],
        title: String = "BiliCast",
        tier: QualityPreference = .mp4Safe,
        ttl: TimeInterval = 6 * 3600
    ) -> StreamSession {
        let id = "cast_" + randomToken(byteCount: 9)
        let now = Date()
        let session = StreamSession(
            id: id,
            kind: .direct(url: upstream, headers: headers),
            title: title,
            tier: tier,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
        state.withLock { $0[id] = session }
        return session
    }

    @discardableResult
    public func createMuxedDash(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String] = [:],
        title: String = "BiliCast",
        ttl: TimeInterval = 6 * 3600
    ) -> StreamSession {
        let id = "cast_" + randomToken(byteCount: 9)
        let now = Date()
        let session = StreamSession(
            id: id,
            kind: .muxedDash(videoURL: videoURL, audioURL: audioURL, headers: headers),
            title: title,
            tier: .dashRemux,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
        state.withLock { $0[id] = session }
        return session
    }

    public func get(_ id: String) -> StreamSession? {
        state.withLock { dict in
            guard let s = dict[id] else { return nil }
            if s.expiresAt < Date() {
                dict.removeValue(forKey: id)
                return nil
            }
            return s
        }
    }

    public func remove(_ id: String) {
        state.withLock { _ = $0.removeValue(forKey: id) }
    }

    public func all() -> [StreamSession] {
        state.withLock { dict in
            dict.values.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func reapExpired() {
        let now = Date()
        state.withLock { dict in
            for (k, v) in dict where v.expiresAt < now {
                dict.removeValue(forKey: k)
            }
        }
    }

    private func randomToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }
}
