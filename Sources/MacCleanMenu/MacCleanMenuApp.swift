import SwiftUI
import AppKit
import MacCleanKit

@main
struct MacCleanMenuApp: App {
    init() {
        // Single-instance enforcement. macOS does NOT auto-deduplicate
        // LSUIElement apps by bundle id the way it does for regular
        // apps — and we have two launch paths (SMAppService at register
        // time + NSWorkspace.openApplication from the main app's
        // setEnabled). Either alone is fine, but in some macOS states
        // both fire and the user ends up with two shields in the menu
        // bar. Check on launch: if another instance with our bundle id
        // is already running, terminate self immediately.
        let myBundleID = Bundle.main.bundleIdentifier
        let myPID = ProcessInfo.processInfo.processIdentifier
        let duplicate = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == myBundleID && $0.processIdentifier != myPID
        }
        if duplicate { exit(0) }
    }

    @State private var statsCollector = SystemStatsCollector()
    @State private var networkMonitor = NetworkSpeedMonitor()
    @State private var devicesCollector = ConnectedDevicesCollector()
    @State private var tipsEngine = TipsEngine()
    @State private var healthMonitor = HealthMonitor()
    @State private var stats: SystemStatsCollector.SystemStats?
    @State private var networkSpeed: NetworkSpeedMonitor.NetworkSpeed?
    @State private var devices: ConnectedDevices?
    @State private var protection: SharedAppState.ProtectionStatus?
    @State private var tips: [TipsEngine.Tip] = []
    @State private var pollingTask: Task<Void, Never>?
    @State private var slowTickCount = 0

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                stats: stats,
                networkSpeed: networkSpeed,
                devices: devices,
                protection: protection,
                tips: tips,
                onDismissTip: { tipId in
                    SharedAppState.dismissTip(id: tipId)
                    tips.removeAll { $0.id == tipId }
                }
            )
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: cleanerGlyph)
                    .foregroundStyle(cleanerColor)
                if let stats {
                    Text(FileSizeFormatter.format(stats.diskFree))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Menu bar label icon. Replaces the earlier shield with a
    /// cleaner-themed sparkle (the canonical "clean" glyph in macOS
    /// UI vocabulary — used in CleanUp Mode, Finder cleanup actions,
    /// etc.). Threat state escalates to a hazard triangle so a real
    /// problem is impossible to miss.
    private var cleanerGlyph: String {
        guard let p = protection else { return "sparkles" }
        if p.threatsFound > 0 { return "exclamationmark.triangle.fill" }
        return "sparkles"
    }

    private var cleanerColor: Color {
        guard let p = protection else { return .secondary }
        if p.threatsFound > 0 { return .red }
        if p.isStale { return .yellow }
        return .green
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                let s = await statsCollector.collect()
                let n = await networkMonitor.measure()
                stats = s
                networkSpeed = n
                protection = SharedAppState.protectionStatus
                slowTickCount += 1
                if slowTickCount % 10 == 1 {
                    devices = await devicesCollector.collect()
                    tips = await tipsEngine.generateTips()
                }
                await healthMonitor.evaluate(stats: s)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

// MARK: - Popover

struct MenuContentView: View {
    let stats: SystemStatsCollector.SystemStats?
    let networkSpeed: NetworkSpeedMonitor.NetworkSpeed?
    let devices: ConnectedDevices?
    let protection: SharedAppState.ProtectionStatus?
    let tips: [TipsEngine.Tip]
    let onDismissTip: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider().opacity(0.25)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if let stats {
                        statCard(
                            icon: "cpu",
                            tint: .blue,
                            title: "CPU",
                            value: String(format: "%.1f%%", stats.cpuUsage * 100),
                            progress: stats.cpuUsage,
                            barColor: barColor(stats.cpuUsage)
                        )
                        statCard(
                            icon: "memorychip",
                            tint: .purple,
                            title: "Memory",
                            value: "\(FileSizeFormatter.format(stats.memoryUsed)) · \(FileSizeFormatter.format(stats.memoryTotal))",
                            progress: stats.memoryPressure,
                            barColor: barColor(stats.memoryPressure)
                        )
                        let diskUsage = stats.diskTotal > 0
                            ? Double(stats.diskTotal - stats.diskFree) / Double(stats.diskTotal)
                            : 0
                        statCard(
                            icon: "internaldrive",
                            tint: .orange,
                            title: "Disk",
                            value: "\(FileSizeFormatter.format(stats.diskFree)) free",
                            progress: diskUsage,
                            barColor: barColor(diskUsage)
                        )
                        if let level = stats.batteryLevel {
                            statCard(
                                icon: stats.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                                tint: stats.batteryIsCharging ? .yellow : .green,
                                title: "Battery" + (stats.batteryIsCharging ? " · Charging" : ""),
                                value: String(format: "%.0f%%", level * 100),
                                progress: level,
                                barColor: level > 0.2 ? .green : .red
                            )
                        }

                        infoStrip(stats: stats)

                        if !tips.isEmpty {
                            tipsCard
                        }
                        if let p = protection {
                            protectionCard(p)
                        }
                        if let d = devices, d.hasAny {
                            devicesCard(d)
                        }
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 520)

            Divider().opacity(0.25)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Color.green.gradient)
                    .font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Mac Clean")
                    .font(.system(size: 14, weight: .semibold))
                Text("Live system stats")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Stat card (CPU / Memory / Disk / Battery)

    private func statCard(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        progress: Double,
        barColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            progressBar(progress: progress, color: barColor)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassCard()
    }

    private func progressBar(progress: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
    }

    // MARK: - Info strip (Network, Uptime, Swap)

    private func infoStrip(stats: SystemStatsCollector.SystemStats) -> some View {
        HStack(spacing: 0) {
            if let net = networkSpeed {
                infoCell {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.green)
                        Text(net.formattedIn)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                infoCell {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text(net.formattedOut)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
            infoCell {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formatUptime(stats.uptime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if stats.swapUsed > 0 {
                infoCell {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(FileSizeFormatter.format(stats.swapUsed))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .glassCard()
    }

    private func infoCell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
    }

    // MARK: - Suggestions / Protection / Connected cards

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                icon: "lightbulb.fill",
                tint: .yellow,
                title: "Suggestions"
            )
            ForEach(tips.prefix(3)) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: tip.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                        Text(tip.body)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button { TipAction.open() } label: {
                        Text("Open")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.accentColor)
                    Button {
                        onDismissTip(tip.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(3)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Don't show this for 30 days")
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassCard()
    }

    private func protectionCard(_ p: SharedAppState.ProtectionStatus) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(protectionTint(p).opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: protectionGlyph(p))
                    .foregroundStyle(protectionTint(p).gradient)
                    .font(.system(size: 13, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.threatsFound > 0
                     ? "\(p.threatsFound) threat\(p.threatsFound == 1 ? "" : "s")"
                     : "Protected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.threatsFound > 0 ? .red : .primary)
                Text("Scanned \(relativeTime(p.lastScanDate)) · \(p.scanDepth)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassCard()
    }

    private func devicesCard(_ d: ConnectedDevices) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                icon: "externaldrive",
                tint: .teal,
                title: "Connected"
            )
            ForEach(d.externalVolumes) { v in
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.teal.opacity(0.7))
                    Text(v.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(FileSizeFormatter.format(v.freeBytes)) free")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if d.externalDisplays > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "tv")
                        .font(.system(size: 9))
                        .foregroundStyle(.teal.opacity(0.7))
                    Text("\(d.externalDisplays) external display\(d.externalDisplays == 1 ? "" : "s")")
                        .font(.system(size: 11))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassCard()
    }

    private func sectionHeader(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                TipAction.open()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10))
                    Text("Open Mac Clean")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Quit Monitor")
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading stats…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func barColor(_ value: Double) -> Color {
        if value > 0.85 { return .red }
        if value > 0.65 { return .orange }
        return .green
    }

    private func protectionTint(_ p: SharedAppState.ProtectionStatus) -> Color {
        if p.threatsFound > 0 { return .red }
        if p.isStale { return .yellow }
        return .green
    }

    private func protectionGlyph(_ p: SharedAppState.ProtectionStatus) -> String {
        if p.threatsFound > 0 { return "shield.lefthalf.filled.trianglebadge.exclamationmark" }
        if p.isStale { return "shield.lefthalf.filled" }
        return "shield.fill"
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hr ago" }
        return "\(Int(interval / 86400)) day\(Int(interval / 86400) == 1 ? "" : "s") ago"
    }
}

// MARK: - Glassmorphism card modifier

private extension View {
    /// Applies the shared glass-card look: ultraThinMaterial fill,
    /// rounded corners, hairline highlight border. Reused across stat
    /// cards, info strip, suggestions, protection, connected sections
    /// so the whole popover reads as a stack of consistent translucent
    /// tiles over the MenuBarExtra(.window) blurred background.
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
