import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var token: String
    public var apiVersion: Int
    public var qualityPreference: QualityPreference

    public init(
        token: String,
        apiVersion: Int = BiliCast.apiVersion,
        qualityPreference: QualityPreference = .mp4Safe
    ) {
        self.token = token
        self.apiVersion = apiVersion
        self.qualityPreference = qualityPreference
    }

    enum CodingKeys: String, CodingKey {
        case token, apiVersion, qualityPreference
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try c.decode(String.self, forKey: .token)
        self.apiVersion = try c.decodeIfPresent(Int.self, forKey: .apiVersion) ?? BiliCast.apiVersion
        // Backwards-compat: older configs may carry "auto" — fold to mp4Safe.
        if let raw = try c.decodeIfPresent(String.self, forKey: .qualityPreference),
           let pref = QualityPreference(rawValue: raw) {
            self.qualityPreference = pref
        } else {
            self.qualityPreference = .mp4Safe
        }
    }
}

public enum ConfigStore {
    public static var configDirURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("BiliCastHelper", isDirectory: true)
    }

    public static var configFileURL: URL {
        configDirURL.appendingPathComponent("config.json")
    }

    public static func loadOrCreate() throws -> Config {
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)
        let url = configFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if let cfg = try? JSONDecoder().decode(Config.self, from: data), !cfg.token.isEmpty {
                return cfg
            }
        }
        let cfg = Config(token: TokenGenerator.generate())
        try save(cfg)
        return cfg
    }

    public static func save(_ cfg: Config) throws {
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)
        let url = configFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cfg)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
