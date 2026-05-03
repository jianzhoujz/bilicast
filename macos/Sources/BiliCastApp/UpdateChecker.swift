import Foundation
import AppKit
import BiliCastCore

/// Compares dotted version strings ("0.3.0", "v1.2.3-beta", etc.) numerically.
struct VersionNumber: Comparable {
    let parts: [Int]

    init(_ value: String) {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let core = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        parts = core.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let n = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<n {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}

struct GitHubRelease {
    let tagName: String
    let htmlURL: URL
}

/// Checks GitHub Releases by following the redirect from `/releases/latest`
/// to `/releases/tag/<tagName>`. No auth, no JSON parsing — purely a HEAD probe.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var inProgress: Bool = false

    func checkForUpdates() {
        guard !inProgress else { return }
        inProgress = true
        Log.app.info("update check: GET \(BiliCast.gitHubLatestReleaseURL.absoluteString, privacy: .public)")

        var req = URLRequest(url: BiliCast.gitHubLatestReleaseURL)
        req.httpMethod = "HEAD"
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.setValue("\(BiliCast.appName)/\(BiliCast.version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.finish(response: response, error: error)
            }
        }.resume()
    }

    private func finish(response: URLResponse?, error: Error?) {
        inProgress = false

        if let error = error {
            Log.app.error("update check error: \(error.localizedDescription, privacy: .public)")
            showMessage(title: "检查更新失败", message: error.localizedDescription)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            showMessage(title: "检查更新失败", message: "没有收到 GitHub 的有效响应。")
            return
        }
        if http.statusCode == 404 {
            showMessage(title: "暂无可用更新", message: "GitHub 上还没有可用的正式 Release。")
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            showMessage(title: "检查更新失败", message: "GitHub 返回 HTTP \(http.statusCode)。")
            return
        }
        guard let release = parseLatest(from: http) else {
            showMessage(title: "检查更新失败", message: "无法识别 GitHub 最新 Release 版本。")
            return
        }

        Log.app.info("latest release tag=\(release.tagName, privacy: .public) current=\(BiliCast.version, privacy: .public)")

        if VersionNumber(BiliCast.version) < VersionNumber(release.tagName) {
            showUpdateAvailable(release)
        } else {
            showMessage(
                title: "已是最新版本",
                message: "\(BiliCast.appName) 当前版本为 \(BiliCast.version)。"
            )
        }
    }

    private func parseLatest(from response: HTTPURLResponse) -> GitHubRelease? {
        guard let final = response.url else { return nil }
        let parts = final.pathComponents
        guard let tagIndex = parts.firstIndex(of: "tag"), tagIndex + 1 < parts.count else {
            return nil
        }
        let tag = parts[tagIndex + 1].removingPercentEncoding ?? parts[tagIndex + 1]
        guard !tag.isEmpty else { return nil }
        return GitHubRelease(tagName: tag, htmlURL: final)
    }

    private func showUpdateAvailable(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(release.tagName)"
        alert.informativeText = "\(BiliCast.appName) 当前版本为 \(BiliCast.version)。是否打开 GitHub Releases 下载更新？"
        alert.addButton(withTitle: "打开下载页")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
