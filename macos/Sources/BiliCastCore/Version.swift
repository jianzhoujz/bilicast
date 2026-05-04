import Foundation

public enum BiliCast {
    public static let appName = "BiliCast"
    public static let bundleID = "local.bilicast"
    public static let version = "0.4.4"
    public static let apiVersion = 1
    public static let controlPort: UInt16 = 18787
    public static let proxyPort: UInt16 = 18788

    public static let gitHubOwner = "jianzhoujz"
    public static let gitHubRepo  = "bilicast"
    public static let gitHubURL   = URL(string: "https://github.com/jianzhoujz/bilicast")!
    public static let gitHubLatestReleaseURL = URL(string: "https://github.com/jianzhoujz/bilicast/releases/latest")!
}
