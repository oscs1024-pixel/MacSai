import Foundation
import AppKit
import ServiceManagement
import MacCleanKit

/// Registers / unregisters the menu bar widget as a login item via
/// `SMAppService.loginItem(identifier:)`. The identifier is the bundle id
/// of the helper app embedded at
/// `Mac Clean.app/Contents/Library/LoginItems/MacCleanMenu.app/`. macOS
/// looks at that exact path to find the helper, so the bundling in
/// `scripts/build-dmg.sh` must match.
///
/// On registration the system launches the helper immediately (no need
/// to call NSWorkspace.open). On unregister the helper is also stopped.
/// State is queryable via `status` so the Settings toggle can reflect
/// the truth of "is the widget actually running right now."
@MainActor
@Observable
public final class MenuBarLauncher {
    public enum LauncherError: Error, LocalizedError {
        case registrationFailed(String)
        case unregisterFailed(String)

        public var errorDescription: String? {
            switch self {
            case .registrationFailed(let msg):
                return "Couldn't enable the menu bar widget: \(msg)"
            case .unregisterFailed(let msg):
                return "Couldn't disable the menu bar widget: \(msg)"
            }
        }
    }

    public static let shared = MenuBarLauncher()

    public private(set) var lastError: LauncherError?

    private let service = SMAppService.loginItem(identifier: MCConstants.menuBundleIdentifier)

    public var isRegistered: Bool {
        service.status == .enabled
    }

    public var status: SMAppService.Status {
        service.status
    }

    private init() {}

    public func register() throws {
        do {
            try service.register()
            lastError = nil
        } catch {
            let wrapped = LauncherError.registrationFailed(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    public func unregister() throws {
        do {
            try service.unregister()
            lastError = nil
        } catch {
            let wrapped = LauncherError.unregisterFailed(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    /// Best-effort enable; swallows errors so app launch can't be
    /// blocked by a Settings-level "show in menu bar" preference flip
    /// going sideways. The error surfaces via `lastError` and the
    /// Settings UI can prompt the user to retry.
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled, !isRegistered {
                try register()
            } else if !enabled, isRegistered {
                try unregister()
            }
        } catch {
            // Error already captured in lastError by register/unregister.
        }
    }
}
