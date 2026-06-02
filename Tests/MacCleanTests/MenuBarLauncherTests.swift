import XCTest
import ServiceManagement
@testable import MacClean
import MacCleanKit

/// Tests for the `MenuBarLauncher` SMAppService wrapper.
///
/// These tests deliberately **do not** call `register()` / `unregister()`
/// / `setEnabled()` — those mutate the real launchd database and would
/// plant a login item on every test run. See the comparable LaunchAgent
/// guidance: tests must not pollute the user's macOS state. The surface
/// we can safely exercise is the read-only side: identity, initial
/// state, status readability.
@MainActor
final class MenuBarLauncherTests: XCTestCase {

    func testSharedInstanceIsSingleton() {
        let a = MenuBarLauncher.shared
        let b = MenuBarLauncher.shared
        XCTAssertTrue(a === b, "shared should return the same instance every time")
    }

    func testInitialLastErrorIsNil() {
        // Fresh state from the singleton — no prior register attempt
        // should have left an error behind.
        XCTAssertNil(MenuBarLauncher.shared.lastError)
    }

    func testStatusIsReadableWithoutCrashing() {
        // The actual returned status depends on whether the helper is
        // bundled in the test runtime (it isn't, under `swift test`),
        // but reading the value must not crash and must yield a known
        // SMAppService.Status case.
        let status = MenuBarLauncher.shared.status
        let knownCases: [SMAppService.Status] = [
            .notRegistered, .enabled, .requiresApproval, .notFound,
        ]
        XCTAssertTrue(knownCases.contains(status),
                      "status returned an unexpected case: \(status)")
    }

    func testIsRegisteredMatchesStatus() {
        // isRegistered is the boolean projection of `status == .enabled`.
        // Whichever side launchd reports, the two must agree.
        let launcher = MenuBarLauncher.shared
        XCTAssertEqual(launcher.isRegistered, launcher.status == .enabled)
    }

    func testBundleIdentifierIsTheConstant() {
        // The Service Management identifier must equal the constant the
        // build script writes into MacCleanMenu.app's Info.plist
        // (`com.macclean.menu`). If these ever diverge, register() fails
        // silently with `.notFound`. Catch the drift here.
        XCTAssertEqual(MCConstants.menuBundleIdentifier, "com.macclean.menu")
    }
}
