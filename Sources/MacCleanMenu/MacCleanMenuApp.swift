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
            // Label content must stay compact; the menu bar gives us
            // very little horizontal space. Original was leaf + disk;
            // we add the shield as a colored health indicator. Drop
            // the leaf — the shield + the disk-free text are enough
            // to make the widget recognizable and saves room for the
            // text on narrow menu bars.
            HStack(spacing: 4) {
                Image(systemName: shieldGlyph)
                    .foregroundStyle(shieldColor)
                if let stats {
                    Text(FileSizeFormatter.format(stats.diskFree))
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var shieldGlyph: String {
        guard let p = protection else { return "shield" }
        if p.threatsFound > 0 { return "shield.lefthalf.filled.trianglebadge.exclamationmark" }
        if p.isStale { return "shield.lefthalf.filled" }
        return "shield.fill"
    }

    private var shieldColor: Color {
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
                // Cheap reads on every fast tick (3s).
                protection = SharedAppState.protectionStatus
                // Expensive collectors and threshold evaluation run on
                // the slow tick (every 10th fast tick = ~30s) so the
                // popover stays snappy and we don't hammer the file
                // system with directory walks every 3 seconds.
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

struct MenuContentView: View {
    let stats: SystemStatsCollector.SystemStats?
    let networkSpeed: NetworkSpeedMonitor.NetworkSpeed?
    let devices: ConnectedDevices?
    let protection: SharedAppState.ProtectionStatus?
    let tips: [TipsEngine.Tip]
    let onDismissTip: (String) -> Void

    var body: some View {
        // ScrollView inside MenuBarExtra(.window) collapses to ~0 height
        // when given only a maxHeight constraint (the popover sizes to
        // the ScrollView's idealSize, which is 0). Use a plain VStack
        // sized by content; if a future power user with many external
        // drives + tips overflows their screen, wrap THIS in a
        // ScrollView with explicit height THEN.
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                Text("Mac Clean")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if let stats {
                statsSection(stats: stats)
                if !tips.isEmpty {
                    Divider()
                    tipsSection
                }
                if let p = protection {
                    Divider()
                    protectionSection(p)
                }
                if let d = devices, d.hasAny {
                    Divider()
                    devicesSection(d)
                }
            } else {
                ProgressView("Loading...")
                    .frame(height: 80)
            }

            Divider()

            Button("Open Mac Clean") {
                TipAction.open()
            }

            Button("Quit Monitor") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
    }

    @ViewBuilder
    private func statsSection(stats: SystemStatsCollector.SystemStats) -> some View {
        MonitorRow(
            icon: "cpu", title: "CPU",
            value: String(format: "%.1f%%", stats.cpuUsage * 100),
            bar: stats.cpuUsage, color: barColor(stats.cpuUsage)
        )

        MonitorRow(
            icon: "memorychip", title: "Memory",
            value: "\(FileSizeFormatter.format(stats.memoryUsed)) / \(FileSizeFormatter.format(stats.memoryTotal))",
            bar: stats.memoryPressure, color: barColor(stats.memoryPressure)
        )

        let diskUsage = stats.diskTotal > 0 ? Double(stats.diskTotal - stats.diskFree) / Double(stats.diskTotal) : 0
        MonitorRow(
            icon: "internaldrive", title: "Disk",
            value: "\(FileSizeFormatter.format(stats.diskFree)) free",
            bar: diskUsage, color: barColor(diskUsage)
        )

        if let level = stats.batteryLevel {
            MonitorRow(
                icon: stats.batteryIsCharging ? "battery.100.bolt" : "battery.75",
                title: "Battery",
                value: String(format: "%.0f%%", level * 100) + (stats.batteryIsCharging ? " Charging" : ""),
                bar: level, color: level > 0.2 ? .green : .red
            )
        }

        if let net = networkSpeed {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text(net.formattedIn)
                        .font(.system(size: 11, design: .monospaced))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                    Text(net.formattedOut)
                        .font(.system(size: 11, design: .monospaced))
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }

        HStack {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text("Uptime")
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatUptime(stats.uptime))
                .font(.system(.caption, design: .monospaced))
        }

        if stats.swapUsed > 0 {
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Swap")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(FileSizeFormatter.format(stats.swapUsed))
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private func protectionSection(_ p: SharedAppState.ProtectionStatus) -> some View {
        HStack {
            Image(systemName: p.threatsFound > 0 ? "shield.lefthalf.filled.trianglebadge.exclamationmark"
                  : (p.isStale ? "shield.lefthalf.filled" : "shield.fill"))
                .foregroundStyle(p.threatsFound > 0 ? .red : (p.isStale ? .yellow : .green))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.threatsFound > 0 ? "\(p.threatsFound) threat\(p.threatsFound == 1 ? "" : "s") found" : "Protected")
                    .font(.system(size: 12, weight: .medium))
                Text("Last scan: \(relativeTime(p.lastScanDate)) (\(p.scanDepth))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func devicesSection(_ d: ConnectedDevices) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Connected")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            if !d.externalVolumes.isEmpty {
                ForEach(d.externalVolumes) { v in
                    HStack {
                        Text("• \(v.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(FileSizeFormatter.format(v.freeBytes)) free")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if d.externalDisplays > 0 {
                HStack {
                    Text("• \(d.externalDisplays) external display\(d.externalDisplays == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 20)
                Text("Suggestions")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            ForEach(tips.prefix(3)) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: tip.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tip.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                        Text(tip.body)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button {
                        TipAction.open()
                    } label: {
                        Text("Open")
                            .font(.system(size: 10))
                    }
                    .controlSize(.mini)
                    Button {
                        onDismissTip(tip.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .help("Don't show this for 30 days")
                }
            }
        }
    }

    private func barColor(_ value: Double) -> Color {
        if value > 0.85 { return .red }
        if value > 0.65 { return .orange }
        return .green
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

struct MonitorRow: View {
    let icon: String
    let title: String
    let value: String
    let bar: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(max(bar, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}
