import Foundation
import ServiceManagement

/// Registers / unregisters the main app as a login item via
/// `SMAppService.mainApp`. Mirrors `MenuBarLauncher`: best-effort
/// `setEnabled`, errors surfaced through `lastError` for the Settings UI.
///
/// Under `swift run` (no .app bundle) registration fails and the error
/// shows in Settings; same dev-workflow caveat as the widget toggle.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public enum LaunchAtLoginError: Error, LocalizedError {
        case updateFailed(enabling: Bool, message: String)

        public var errorDescription: String? {
            switch self {
            case .updateFailed(let enabling, let message):
                let verb = enabling ? "enable" : "disable"
                return "Couldn't \(verb) launch at login: \(message)"
            }
        }
    }

    public static let shared = LaunchAtLoginManager()

    public internal(set) var lastError: LaunchAtLoginError?

    private let service = SMAppService.mainApp

    public var isEnabled: Bool { service.status == .enabled }
    public var status: SMAppService.Status { service.status }

    private init() {}

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = .updateFailed(enabling: enabled, message: error.localizedDescription)
        }
    }
}
