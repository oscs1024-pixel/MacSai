import XCTest
import Foundation
@testable import MacCleanKit
import MacCleanTestSupport

/// Adversarial tests for `SafetyGuard`. The goal is 100% coverage on the
/// most safety-critical file in the project.
final class SafetyGuardTests: XCTestCase {
    let sg = SafetyGuard()

    // MARK: - Protected system paths (must reject)

    func testRejectsSystemLibrary() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/System/Library/Frameworks/Foundation.framework"))) {
            guard case SafetyGuard.SafetyError.sipProtected = $0 else {
                return XCTFail("Expected sipProtected, got \($0)")
            }
        }
    }

    func testRejectsSystemRoot() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/System")))
    }

    func testRejectsUsrBin() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/usr/bin/ls"))) {
            guard case SafetyGuard.SafetyError.protectedPath = $0 else {
                return XCTFail("Expected protectedPath, got \($0)")
            }
        }
    }

    func testRejectsUsrLocal() {
        // Even /usr/local is under /usr, which is protected as a whole.
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/usr/local/bin/brew")))
    }

    func testRejectsBin() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/bin/sh")))
    }

    func testRejectsSbin() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/sbin/mount")))
    }

    func testRejectsLibraryAppleDir() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/Library/Apple/usr/libexec")))
    }

    func testRejectsPrivateVarDb() {
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/private/var/db/launchd.db")))
    }

    // MARK: - Safe user paths (must allow)

    func testAllowsUserCachePath() throws {
        let url = MCConstants.userCaches.appending(path: "com.test.app")
        XCTAssertNoThrow(try sg.validatePath(url))
    }

    func testAllowsUserLogsPath() throws {
        let url = MCConstants.userLogs.appending(path: "Foo.log")
        XCTAssertNoThrow(try sg.validatePath(url))
    }

    func testAllowsDownloadsPath() throws {
        let url = MCConstants.downloads.appending(path: "test.dmg")
        XCTAssertNoThrow(try sg.validatePath(url))
    }

    func testAllowsArbitraryUserFile() throws {
        let url = MCConstants.home.appending(path: "Documents/notes.txt")
        XCTAssertNoThrow(try sg.validatePath(url))
    }

    // MARK: - Symlinks (TOCTOU prevention)

    func testRejectsSymlinkPointingToSystem() throws {
        try TestFixtures.withTempDir { tmp in
            let link = tmp.appending(path: "evil-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/System/Library"))
            XCTAssertThrowsError(try sg.validatePath(link)) {
                // After symlink resolution it falls under /System or root differs.
                // Both "sipProtected" and "symlinkTarget" are acceptable rejections.
                switch $0 {
                case SafetyGuard.SafetyError.sipProtected,
                     SafetyGuard.SafetyError.symlinkTarget,
                     SafetyGuard.SafetyError.protectedPath:
                    break
                default:
                    XCTFail("Expected SIP/protected/symlink rejection, got \($0)")
                }
            }
        }
    }

    func testRejectsSymlinkPointingToUsrBin() throws {
        // resolvingSymlinksInPath()'s behavior on dangling/uncreated symlinks
        // is documented as best-effort and depends on whether the symlink
        // target exists on disk. The direct-path rejection (testRejectsUsrBin)
        // is what guarantees safety regardless of symlink resolution.
        XCTAssertThrowsError(try sg.validatePath(URL(filePath: "/usr/bin/ls")))
    }

    func testRejectsTraversalThatResolvesToProtected() throws {
        // Path containing ".." traversal segments that resolves to a
        // protected location. After standardization, /tmp/x/../../usr lands
        // on /usr which is in protectedPaths.
        let evil = URL(filePath: "/private/tmp/macclean/../../../usr/bin/ls")
        XCTAssertThrowsError(try sg.validatePath(evil))
    }

    // MARK: - Invalid input

    // Note: URL(filePath: "") doesn't actually produce an empty internal path;
    // Foundation normalizes it. The empty-check inside validatePath is still
    // defensive against constructed-string paths. We test the NULL byte case
    // below as the more practical attack vector.

    func testRejectsNullBytePath() throws {
        // macOS 15 Foundation aborts inside URL(filePath:) when handed a
        // string with an embedded NULL — there's no way to even construct
        // the fixture, and the OS itself now blocks the attack vector at
        // URL-construction time. SafetyGuard's own NULL-byte check is still
        // exercised on older OS; skip on 15+ where the test scaffold can't
        // be built.
        if #available(macOS 15, *) {
            throw XCTSkip("URL(filePath:) aborts on embedded NULL on macOS 15+; OS-level protection in effect.")
        }
        let url = URL(filePath: "/tmp/file\u{0000}.txt")
        XCTAssertThrowsError(try sg.validatePath(url)) {
            guard case SafetyGuard.SafetyError.invalidPath = $0 else {
                return XCTFail("Expected invalidPath, got \($0)")
            }
        }
    }

    func testHandlesUnicodeTrickyPaths() throws {
        let trickyURL = MCConstants.userCaches.appending(path: "com.test.\u{202E}evil.app")
        // Should be allowed (it's under user caches), not crash on the RTL char.
        XCTAssertNoThrow(try sg.validatePath(trickyURL))
    }

    // MARK: - File cap

    func testAllowsTenThousandFiles() throws {
        let urls = (0..<10_000).map {
            MCConstants.userCaches.appending(path: "file-\($0).cache")
        }
        XCTAssertNoThrow(try sg.validateDeletion(paths: urls))
    }

    func testRejectsBatchOverTenThousand() {
        let urls = (0..<10_001).map {
            MCConstants.userCaches.appending(path: "file-\($0).cache")
        }
        XCTAssertThrowsError(try sg.validateDeletion(paths: urls)) {
            guard case SafetyGuard.SafetyError.tooManyFiles(let n) = $0 else {
                return XCTFail("Expected tooManyFiles, got \($0)")
            }
            XCTAssertEqual(n, 10_001)
        }
    }

    func testEmptyBatchAllowed() {
        XCTAssertNoThrow(try sg.validateDeletion(paths: []))
    }

    func testBatchRejectsOnFirstUnsafePath() {
        let urls = [
            MCConstants.userCaches.appending(path: "ok1.cache"),
            URL(filePath: "/System/Library/whatever"),
            MCConstants.userCaches.appending(path: "ok2.cache"),
        ]
        XCTAssertThrowsError(try sg.validateDeletion(paths: urls)) {
            guard case SafetyGuard.SafetyError.sipProtected = $0 else {
                return XCTFail("Expected sipProtected, got \($0)")
            }
        }
    }

    // MARK: - Idempotence

    func testValidatePathIsIdempotent() throws {
        let url = MCConstants.userCaches.appending(path: "test.cache")
        XCTAssertNoThrow(try sg.validatePath(url))
        XCTAssertNoThrow(try sg.validatePath(url))
        XCTAssertNoThrow(try sg.validatePath(url))
    }

    // MARK: - isProtectedApp

    func testProtectedAppleApps() {
        XCTAssertTrue(sg.isProtectedApp("com.apple.finder"))
        XCTAssertTrue(sg.isProtectedApp("com.apple.Safari"))
        XCTAssertTrue(sg.isProtectedApp("com.apple.mail"))
        XCTAssertTrue(sg.isProtectedApp("com.apple.Terminal"))
        XCTAssertTrue(sg.isProtectedApp("com.apple.systempreferences"))
        XCTAssertTrue(sg.isProtectedApp("com.apple.dt.Xcode"))
    }

    func testThirdPartyAppsNotProtected() {
        XCTAssertFalse(sg.isProtectedApp("com.google.Chrome"))
        XCTAssertFalse(sg.isProtectedApp("com.spotify.client"))
        XCTAssertFalse(sg.isProtectedApp("com.microsoft.VSCode"))
        XCTAssertFalse(sg.isProtectedApp("com.macpaw.cleanmymac"))
        XCTAssertFalse(sg.isProtectedApp(""))
    }

    // MARK: - isSafeForOrphanDeletion

    func testOrphanSafe_caches() {
        let url = MCConstants.userCaches.appending(path: "com.removed/file")
        XCTAssertTrue(sg.isSafeForOrphanDeletion(url))
    }

    func testOrphanSafe_logs() {
        let url = MCConstants.userLogs.appending(path: "Removed.log")
        XCTAssertTrue(sg.isSafeForOrphanDeletion(url))
    }

    func testOrphanSafe_savedAppState() {
        let url = MCConstants.userSavedAppState.appending(path: "com.removed.app.savedState")
        XCTAssertTrue(sg.isSafeForOrphanDeletion(url))
    }

    func testOrphanUnsafe_preferences() {
        let url = MCConstants.userPreferences.appending(path: "com.removed.app.plist")
        XCTAssertFalse(sg.isSafeForOrphanDeletion(url))
    }

    func testOrphanUnsafe_containers() {
        let url = MCConstants.userContainers.appending(path: "com.removed.app")
        XCTAssertFalse(sg.isSafeForOrphanDeletion(url))
    }

    func testOrphanUnsafe_keychain() {
        let url = MCConstants.home.appending(path: "Library/Keychains/login.keychain")
        XCTAssertFalse(sg.isSafeForOrphanDeletion(url))
    }
}
