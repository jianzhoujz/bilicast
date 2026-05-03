import SwiftUI
import AppKit
import BiliCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState()
    let updateChecker = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }
}

@main
struct BiliCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state, updater: delegate.updateChecker)
        } label: {
            // 13pt monospaced semibold matches input-indicator's status item width.
            Text("🐝")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
