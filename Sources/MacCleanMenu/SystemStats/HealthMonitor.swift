import Foundation
import UserNotifications
import MacCleanKit

/// Watches the rolling stats stream for crossed thresholds and fires
/// macOS notifications via `UNUserNotificationCenter`. Throttled
/// via `SharedAppState.recentlyNotified` so we don't spam — disk-low
/// re-fires every 15 minutes, battery-health/cycle once a week.
///
/// Authorization is requested lazily on first notification attempt
/// (not eagerly on app launch — the menu widget shouldn't prompt
/// for permissions before the user has done anything).
public actor HealthMonitor {
    public init() {}

    public struct Thresholds: Sendable {
        public var minimumDiskFreeBytes: UInt64 = 5 * 1024 * 1024 * 1024    // 5 GB
        public var memoryPressureSustained: Double = 0.85
        public var memoryPressureSustainedSamples: Int = 5  // ~15s at 3s poll
        public var batteryHealthFloor: Double = 0.80
        public var batteryCyclesCeiling: Int = 1000
    }

    public var thresholds = Thresholds()

    private var memoryPressureSampleStreak = 0
    private var authorizationRequested = false

    /// Called every tick from the polling loop. Compares the latest
    /// snapshot to thresholds and fires throttled notifications.
    public func evaluate(stats: SystemStatsCollector.SystemStats) async {
        await checkLowDisk(stats: stats)
        await checkMemoryPressure(stats: stats)
        await checkBatteryHealth(stats: stats)
        await checkBatteryCycles(stats: stats)
    }

    // MARK: - Individual checks

    private func checkLowDisk(stats: SystemStatsCollector.SystemStats) async {
        guard stats.diskFree < thresholds.minimumDiskFreeBytes else { return }
        // 15 min throttle — disk fills up gradually; one alert every
        // quarter hour is plenty.
        if SharedAppState.recentlyNotified(kind: "disk_low", throttle: 15 * 60) { return }
        await fire(
            kind: "disk_low",
            title: "Storage critical",
            body: "Only \(FileSizeFormatter.format(stats.diskFree)) free on your startup disk. Open Mac Clean to free up space."
        )
    }

    private func checkMemoryPressure(stats: SystemStatsCollector.SystemStats) async {
        if stats.memoryPressure >= thresholds.memoryPressureSustained {
            memoryPressureSampleStreak += 1
        } else {
            memoryPressureSampleStreak = 0
            return
        }
        guard memoryPressureSampleStreak >= thresholds.memoryPressureSustainedSamples else { return }
        if SharedAppState.recentlyNotified(kind: "memory_high", throttle: 30 * 60) { return }
        // Reset the streak so we don't re-trigger immediately after
        // the next sample.
        memoryPressureSampleStreak = 0
        await fire(
            kind: "memory_high",
            title: "Memory pressure high",
            body: "Sustained \(Int(stats.memoryPressure * 100))% memory pressure. Mac Clean's Maintenance module can free up RAM."
        )
    }

    private func checkBatteryHealth(stats: SystemStatsCollector.SystemStats) async {
        guard let health = stats.batteryHealth, health < thresholds.batteryHealthFloor else { return }
        // Battery health degrades very slowly — once a week is more
        // than enough.
        if SharedAppState.recentlyNotified(kind: "battery_health", throttle: 7 * 24 * 3600) { return }
        await fire(
            kind: "battery_health",
            title: "Battery health below \(Int(thresholds.batteryHealthFloor * 100))%",
            body: "Your battery's maximum capacity is now \(Int(health * 100))%. Consider scheduling a service appointment."
        )
    }

    private func checkBatteryCycles(stats: SystemStatsCollector.SystemStats) async {
        guard let cycles = stats.batteryCycleCount, cycles > thresholds.batteryCyclesCeiling else { return }
        if SharedAppState.recentlyNotified(kind: "battery_cycles", throttle: 7 * 24 * 3600) { return }
        await fire(
            kind: "battery_cycles",
            title: "Battery cycle count high",
            body: "Your battery has been through \(cycles) cycles. Apple rates most batteries for ~1000 before noticeable wear."
        )
    }

    // MARK: - Notification plumbing

    private func fire(kind: String, title: String, body: String) async {
        let granted = await ensureAuthorization()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macclean.health.\(kind).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            SharedAppState.recordNotification(kind: kind)
        } catch {
            // Swallow — a failed notification is recoverable; the
            // throttle log isn't updated, so the next eligible tick
            // tries again.
        }
    }

    private func ensureAuthorization() async -> Bool {
        if authorizationRequested {
            return await Self.isAuthorized()
        }
        authorizationRequested = true
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// `UNNotificationSettings` is non-Sendable, so awaiting it from
    /// inside the actor fails Swift 6 strict-concurrency. Hop through
    /// a static (actor-unisolated) helper: the settings object is
    /// created and consumed in the nonisolated context, and only the
    /// Sendable `Bool` crosses back to the actor.
    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }
}
