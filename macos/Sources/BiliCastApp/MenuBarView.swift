import SwiftUI
import BiliCastCore
import BiliCastDLNA
import BiliCastHTTP

struct MenuBarView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater: UpdateChecker
    @State private var refreshing = false
    @State private var showCopiedHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            Divider()

            apiSection

            tokenSection

            Divider()

            qualitySection

            Divider()

            devicesSection

            if let cs = state.currentSession {
                Divider()
                currentSessionSection(cs)
            }

            if let err = state.lastError, case .failed = state.status {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            Divider()

            aboutSection

            Divider()

            HStack {
                Spacer()
                Button("退出") {
                    state.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关于").sectionLabel()
            Text("\(BiliCast.appName) v\(BiliCast.version)")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(updater.inProgress ? "正在检查更新…" : "检查更新…") {
                    updater.checkForUpdates()
                }
                .controlSize(.small)
                .disabled(updater.inProgress)

                Button("GitHub 主页") {
                    NSWorkspace.shared.open(BiliCast.gitHubURL)
                }
                .controlSize(.small)

                Button("给个 Star") {
                    NSWorkspace.shared.open(BiliCast.gitHubURL)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Sections

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.headline)
            Spacer()
        }
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("控制 API").sectionLabel()
            Text("http://127.0.0.1:\(BiliCast.controlPort)")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(.secondary)
            Text("代理：0.0.0.0:\(BiliCast.proxyPort)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pairing Token").sectionLabel()
                Spacer()
                Button(showCopiedHint ? "已复制" : "复制") {
                    state.copyToken()
                    showCopiedHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showCopiedHint = false
                    }
                }
                .controlSize(.small)
                Button("重置") { state.resetToken() }
                    .controlSize(.small)
            }
            Text(maskedToken)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.secondary)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("清晰度模式").sectionLabel()
                Spacer()
                ffmpegStatusBadge
            }

            Picker("", selection: Binding(
                get: { state.qualityPreference },
                set: { state.setQualityPreference($0) }
            )) {
                ForEach(QualityPreference.allCases, id: \.rawValue) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()

            qualityInfoCard(for: state.qualityPreference)

            if state.qualityPreference == .dashRemux, state.ffmpegPath == nil {
                Text("当前选了「极清」但没找到 ffmpeg。会自动降级到「高清」或「标准」。")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    private func qualityInfoCard(for pref: QualityPreference) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pref.summary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(pref.pros.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 4) {
                        Text("+").foregroundColor(.green).font(.caption2.monospaced())
                        Text(p).font(.caption2).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Array(pref.cons.enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .top, spacing: 4) {
                        Text("−").foregroundColor(.orange).font(.caption2.monospaced())
                        Text(c).font(.caption2).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let note = pref.note {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var ffmpegStatusBadge: some View {
        if let src = state.ffmpegSource {
            let label = src == .bundled ? "ffmpeg 已内置" : "ffmpeg：系统"
            Text(label)
                .font(.caption2)
                .foregroundColor(.green)
        } else {
            Text("ffmpeg 未装")
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DLNA 设备").sectionLabel()
                Text("(\(state.devices.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(refreshing ? "扫描中…" : "重新扫描") {
                    refreshing = true
                    state.refreshDevicesNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        refreshing = false
                    }
                }
                .controlSize(.small)
                .disabled(refreshing)
            }

            if state.devices.isEmpty {
                Text("尚未发现设备。请确认电视和 Mac 在同一 Wi-Fi，并打开电视的 DLNA / 投屏功能。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.devices, id: \.id) { dev in
                        deviceRow(dev)
                    }
                }
            }
        }
    }

    private func deviceRow(_ dev: DLNADevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tv")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name)
                    .font(.caption.weight(.semibold))
                if let sub = subtitleFor(dev) {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func subtitleFor(_ dev: DLNADevice) -> String? {
        let bits = [dev.manufacturer, dev.modelName].compactMap { $0 }
        if bits.isEmpty { return dev.location.host }
        return bits.joined(separator: " · ")
    }

    private func currentSessionSection(_ cs: AppState.CurrentSessionView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("当前投屏").sectionLabel()
                Spacer()
                Text(cs.tier.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(3)
            }
            Text(cs.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(cs.deviceName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("停止投屏") { state.stopCurrentCast() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Computed

    private var statusSymbol: String {
        switch state.status {
        case .running: return "checkmark.circle.fill"
        case .starting: return "arrow.triangle.2.circlepath"
        case .stopped: return "circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .running: return .green
        case .starting: return .orange
        case .stopped: return .secondary
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch state.status {
        case .running: return "服务运行中"
        case .starting: return "服务启动中…"
        case .stopped: return "服务已停止"
        case .failed: return "服务异常"
        }
    }

    private var maskedToken: String {
        let t = state.token
        if t.isEmpty { return "(未设置)" }
        if t.count <= 10 { return String(repeating: "•", count: t.count) }
        let head = t.prefix(4)
        let tail = t.suffix(4)
        return "\(head)••••••••\(tail)"
    }
}

private extension Text {
    func sectionLabel() -> some View {
        self.font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }
}
