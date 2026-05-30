import Foundation
import MacCleanKit

// Standalone test runner — no XCTest dependency, works with CLI tools only.

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0
nonisolated(unsafe) var testErrors: [(String, String)] = []

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("  \u{2713} \(name)")
    } catch {
        failed += 1
        testErrors.append((name, "\(error)"))
        print("  \u{2717} \(name): \(error)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw TestError.assertionFailed("Expected \(a) == \(b) at \(file):\(line)")
    }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard condition else {
        throw TestError.assertionFailed("Expected true\(msg.isEmpty ? "" : ": \(msg)") at \(file):\(line)")
    }
}

func assertFalse(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition else {
        throw TestError.assertionFailed("Expected false\(msg.isEmpty ? "" : ": \(msg)") at \(file):\(line)")
    }
}

func assertThrows<T>(_ body: () throws -> T, file: String = #file, line: Int = #line) throws {
    do {
        _ = try body()
        throw TestError.assertionFailed("Expected throw at \(file):\(line)")
    } catch is TestError {
        throw TestError.assertionFailed("Expected throw at \(file):\(line)")
    } catch {
        // Good — it threw
    }
}

func assertNoThrow(_ body: () throws -> Void, file: String = #file, line: Int = #line) throws {
    do {
        try body()
    } catch {
        throw TestError.assertionFailed("Unexpected throw: \(error) at \(file):\(line)")
    }
}

enum TestError: Error {
    case assertionFailed(String)
}

// ============================================================
// MARK: - FileItem Tests
// ============================================================

print("\n--- FileItem Tests ---")

test("FileItem formatted size contains expected value") {
    let item = FileItem(
        url: URL(filePath: "/tmp/test.txt"),
        name: "test.txt",
        size: 5 * 1024 * 1024,
        allocatedSize: 5 * 1024 * 1024,
        isDirectory: false
    )
    try assertTrue(item.formattedSize.contains("5"), "formatted size should contain '5', got: \(item.formattedSize)")
}

test("FileItem file extension") {
    let item = FileItem(
        url: URL(filePath: "/tmp/test.log"),
        name: "test.log",
        size: 100,
        allocatedSize: 100,
        isDirectory: false
    )
    try assertEqual(item.fileExtension, "log")
}

test("FileItem equality by URL") {
    let url = URL(filePath: "/tmp/same.txt")
    let a = FileItem(url: url, name: "same.txt", size: 100, allocatedSize: 100, isDirectory: false)
    let b = FileItem(url: url, name: "same.txt", size: 999, allocatedSize: 999, isDirectory: false)
    try assertTrue(a == b, "same URL should be equal")
}

test("FileItem inequality by URL") {
    let a = FileItem(url: URL(filePath: "/a"), name: "a", size: 100, allocatedSize: 100, isDirectory: false)
    let b = FileItem(url: URL(filePath: "/b"), name: "b", size: 100, allocatedSize: 100, isDirectory: false)
    try assertFalse(a == b, "different URLs should not be equal")
}

test("FileItem age calculation") {
    let pastDate = Date().addingTimeInterval(-3600)
    let item = FileItem(
        url: URL(filePath: "/tmp/old.txt"), name: "old.txt",
        size: 100, allocatedSize: 100, isDirectory: false,
        modificationDate: pastDate
    )
    try assertTrue(item.age != nil, "age should not be nil")
    try assertTrue(item.age! > 3500, "age should be > 3500 seconds")
}

test("FileItem age nil when no modification date") {
    let item = FileItem(url: URL(filePath: "/tmp/new.txt"), name: "new.txt",
                        size: 100, allocatedSize: 100, isDirectory: false)
    try assertTrue(item.age == nil, "age should be nil")
}

// ============================================================
// MARK: - ScanCategory Tests
// ============================================================

print("\n--- ScanCategory Tests ---")

test("All categories have display names") {
    for cat in ScanCategory.allCases {
        try assertFalse(cat.displayName.isEmpty, "\(cat) missing display name")
    }
}

test("All categories have icons") {
    for cat in ScanCategory.allCases {
        try assertFalse(cat.systemImage.isEmpty, "\(cat) missing icon")
    }
}

test("All category IDs are unique") {
    let ids = ScanCategory.allCases.map(\.id)
    try assertEqual(ids.count, Set(ids).count)
}

test("Category count >= 20") {
    try assertTrue(ScanCategory.allCases.count >= 20)
}

test("Auto-select defaults") {
    try assertTrue(ScanCategory.userCaches.autoSelect)
    try assertTrue(ScanCategory.systemCaches.autoSelect)
    try assertFalse(ScanCategory.unusedDiskImages.autoSelect)
    try assertFalse(ScanCategory.largeFiles.autoSelect)
    try assertFalse(ScanCategory.duplicates.autoSelect)
}

// ============================================================
// MARK: - ScanResult Tests
// ============================================================

print("\n--- ScanResult Tests ---")

test("ScanResult total size") {
    let items = (0..<5).map {
        FileItem(url: URL(filePath: "/\($0)"), name: "\($0)", size: 100, allocatedSize: 100, isDirectory: false)
    }
    let result = ScanResult(category: .userCaches, items: items)
    try assertEqual(result.totalSize, 500)
    try assertEqual(result.fileCount, 5)
}

test("Empty ScanResult") {
    let result = ScanResult(category: .userCaches, items: [])
    try assertEqual(result.totalSize, 0)
    try assertEqual(result.fileCount, 0)
}

test("ModuleScanResult aggregation") {
    let items1 = [FileItem(url: URL(filePath: "/a"), name: "a", size: 500, allocatedSize: 500, isDirectory: false)]
    let items2 = [
        FileItem(url: URL(filePath: "/b"), name: "b", size: 300, allocatedSize: 300, isDirectory: false),
        FileItem(url: URL(filePath: "/c"), name: "c", size: 200, allocatedSize: 200, isDirectory: false),
    ]
    let moduleResult = ModuleScanResult(
        moduleID: "test", moduleName: "Test",
        categories: [
            ScanResult(category: .userCaches, items: items1),
            ScanResult(category: .userLogs, items: items2),
        ],
        scanDuration: 1.5
    )
    try assertEqual(moduleResult.totalSize, 1000)
    try assertEqual(moduleResult.totalFileCount, 3)
}

// ============================================================
// MARK: - AppInfo Tests
// ============================================================

print("\n--- AppInfo Tests ---")

test("AppInfo creation") {
    let app = AppInfo(
        bundleIdentifier: "com.test.app", name: "Test App",
        path: URL(filePath: "/Applications/Test.app"), version: "1.0", size: 50_000_000
    )
    try assertEqual(app.bundleIdentifier, "com.test.app")
    try assertFalse(app.isAppleApp)
}

test("AppInfo unused detection") {
    let oldDate = Date().addingTimeInterval(-200 * 24 * 3600)
    let oldApp = AppInfo(bundleIdentifier: "com.test.old", name: "Old",
                         path: URL(filePath: "/Applications/Old.app"), lastOpened: oldDate)
    try assertTrue(oldApp.isUnused)

    let recentApp = AppInfo(bundleIdentifier: "com.test.new", name: "New",
                            path: URL(filePath: "/Applications/New.app"), lastOpened: Date())
    try assertFalse(recentApp.isUnused)
}

test("AppInfo formatted size") {
    let app = AppInfo(bundleIdentifier: "com.test.app", name: "Test",
                      path: URL(filePath: "/Applications/Test.app"), size: 50_000_000)
    try assertFalse(app.formattedSize.isEmpty)
}

// ============================================================
// MARK: - Constants Tests
// ============================================================

print("\n--- Constants Tests ---")

test("Protected paths not empty") {
    try assertFalse(MCConstants.protectedPaths.isEmpty)
}

test("Protected apps not empty") {
    try assertFalse(MCConstants.protectedApps.isEmpty)
}

test("Preserved languages contain English") {
    try assertTrue(MCConstants.preservedLanguages.contains("en.lproj"))
    try assertTrue(MCConstants.preservedLanguages.contains("Base.lproj"))
}

test("Home directory exists") {
    try assertTrue(FileManager.default.fileExists(atPath: MCConstants.home.path(percentEncoded: false)))
}

test("User Library exists") {
    try assertTrue(FileManager.default.fileExists(atPath: MCConstants.userLibrary.path(percentEncoded: false)))
}

test("User Caches directory exists") {
    try assertTrue(FileManager.default.fileExists(atPath: MCConstants.userCaches.path(percentEncoded: false)))
}

// ============================================================
// MARK: - FileSizeFormatter Tests
// ============================================================

print("\n--- FileSizeFormatter Tests ---")

test("Format bytes non-empty") {
    let result = FileSizeFormatter.format(UInt64(1024))
    try assertFalse(result.isEmpty)
}

test("Format zero bytes") {
    let result = FileSizeFormatter.format(UInt64(0))
    try assertFalse(result.isEmpty)
}

test("Short format returns value and unit") {
    let result = FileSizeFormatter.shortFormat(100 * 1024 * 1024)
    try assertFalse(result.value.isEmpty)
    try assertFalse(result.unit.isEmpty)
}

// ============================================================
// MARK: - HelperProtocol Tests
// ============================================================

print("\n--- HelperProtocol Tests ---")

test("HelperProtocol type exists") {
    let _: MacCleanHelperProtocol.Type = MacCleanHelperProtocol.self
}

// ============================================================
// MARK: - Safety Guard Tests (reimplemented without MacClean import)
// ============================================================

print("\n--- Safety Guard Tests ---")

// These test the safety model by directly checking Constants + path logic

test("System path /System is in protected set") {
    try assertTrue(MCConstants.protectedPaths.contains("/System"))
}

test("Path /usr is in protected set") {
    try assertTrue(MCConstants.protectedPaths.contains("/usr"))
}

test("Path /bin is in protected set") {
    try assertTrue(MCConstants.protectedPaths.contains("/bin"))
}

test("Path /sbin is in protected set") {
    try assertTrue(MCConstants.protectedPaths.contains("/sbin"))
}

test("Protected path check: /System/Library resolves to protected") {
    let path = "/System/Library/something"
    let isProtected = MCConstants.protectedPaths.contains { path.hasPrefix($0 + "/") || path == $0 }
    try assertTrue(isProtected)
}

test("Protected path check: user cache NOT protected") {
    let path = MCConstants.userCaches.path(percentEncoded: false) + "/com.test.app"
    let isProtected = MCConstants.protectedPaths.contains { path.hasPrefix($0 + "/") || path == $0 }
    try assertFalse(isProtected)
}

test("Protected path check: /usr/bin/ls is protected") {
    let path = "/usr/bin/ls"
    let isProtected = MCConstants.protectedPaths.contains { path.hasPrefix($0 + "/") || path == $0 }
    try assertTrue(isProtected)
}

test("Apple Finder is in protected apps") {
    try assertTrue(MCConstants.protectedApps.contains("com.apple.finder"))
}

test("Apple Safari is in protected apps") {
    try assertTrue(MCConstants.protectedApps.contains("com.apple.Safari"))
}

test("Apple Terminal is in protected apps") {
    try assertTrue(MCConstants.protectedApps.contains("com.apple.Terminal"))
}

test("Chrome is NOT in protected apps") {
    try assertFalse(MCConstants.protectedApps.contains("com.google.Chrome"))
}

test("Spotify is NOT in protected apps") {
    try assertFalse(MCConstants.protectedApps.contains("com.spotify.client"))
}

test("Max files per operation is 10000") {
    try assertEqual(MCConstants.maxFilesPerOperation, 10_000)
}

test("File cap: 10001 files exceeds limit") {
    try assertTrue(10_001 > MCConstants.maxFilesPerOperation)
}

test("File cap: 10000 files within limit") {
    try assertTrue(10_000 <= MCConstants.maxFilesPerOperation)
}

test("Orphan safety: user caches path is safe prefix") {
    let path = MCConstants.userCaches.path(percentEncoded: false)
    let safePrefixes = [
        MCConstants.userCaches.path(percentEncoded: false),
        MCConstants.userLogs.path(percentEncoded: false),
    ]
    let isSafe = safePrefixes.contains { (path + "/orphan").hasPrefix($0) }
    try assertTrue(isSafe)
}

test("Orphan safety: preferences path is NOT safe") {
    let path = MCConstants.userPreferences.path(percentEncoded: false) + "/orphan.plist"
    let safePrefixes = [
        MCConstants.userCaches.path(percentEncoded: false),
        MCConstants.userLogs.path(percentEncoded: false),
    ]
    let isSafe = safePrefixes.contains { path.hasPrefix($0) }
    try assertFalse(isSafe)
}

// ============================================================
// MARK: - Scanner Path Tests
// ============================================================

print("\n--- Scanner Path Tests ---")

test("Xcode DerivedData path is reasonable") {
    let path = MCConstants.xcodeDerivedData.path(percentEncoded: false)
    try assertTrue(path.contains("Developer/Xcode/DerivedData"))
}

test("iOS backup path is reasonable") {
    let path = MCConstants.mobileBackups.path(percentEncoded: false)
    try assertTrue(path.contains("MobileSync/Backup"))
}

test("Safari cache path is reasonable") {
    let path = MCConstants.safariCache.path(percentEncoded: false)
    try assertTrue(path.contains("com.apple.Safari"))
}

test("Chrome cache path is reasonable") {
    let path = MCConstants.chromeCache.path(percentEncoded: false)
    try assertTrue(path.contains("Google/Chrome"))
}

test("Mail data path is reasonable") {
    let path = MCConstants.mailData.path(percentEncoded: false)
    try assertTrue(path.contains("Library/Mail"))
}

test("Operation log path is inside user Logs") {
    let path = MCConstants.operationLogFile.path(percentEncoded: false)
    try assertTrue(path.contains("Library/Logs/MacClean"))
}

// ============================================================
// MARK: - Live System Tests
// ============================================================

print("\n--- Live System Tests ---")

test("Can enumerate user Caches directory") {
    let fm = FileManager.default
    let path = MCConstants.userCaches.path(percentEncoded: false)
    try assertTrue(fm.fileExists(atPath: path), "~/Library/Caches should exist")
    let contents = try fm.contentsOfDirectory(atPath: path)
    try assertTrue(contents.count > 0, "~/Library/Caches should not be empty")
}

test("Can enumerate user Logs directory") {
    let fm = FileManager.default
    let path = MCConstants.userLogs.path(percentEncoded: false)
    try assertTrue(fm.fileExists(atPath: path), "~/Library/Logs should exist")
}

test("Can read Downloads directory") {
    let fm = FileManager.default
    let path = MCConstants.downloads.path(percentEncoded: false)
    try assertTrue(fm.fileExists(atPath: path), "~/Downloads should exist")
}

test("Trash directory exists") {
    let fm = FileManager.default
    let path = MCConstants.userTrash.path(percentEncoded: false)
    try assertTrue(fm.fileExists(atPath: path), "~/.Trash should exist")
}

test("Volume info returns at least one volume") {
    let url = URL(filePath: "/")
    let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    let total = values.volumeTotalCapacity ?? 0
    let free = values.volumeAvailableCapacityForImportantUsage ?? 0
    try assertTrue(total > 0, "Total capacity should be > 0")
    try assertTrue(free > 0, "Free capacity should be > 0")
    try assertTrue(free < total, "Free should be less than total")
}

test("URLResourceKey prefetch works for size") {
    let tmpFile = FileManager.default.temporaryDirectory.appending(path: "macclean_test_\(UUID()).txt")
    let testData = Data("Hello Mac Clean Test".utf8)
    try testData.write(to: tmpFile)
    defer { try? FileManager.default.removeItem(at: tmpFile) }

    let values = try tmpFile.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .nameKey])
    try assertTrue(values.fileSize ?? 0 > 0, "File size should be > 0")
    try assertFalse(values.isDirectory ?? true, "Should not be directory")
}

// ============================================================
// MARK: - PlistJunkFilter Tests
// ============================================================
//
// These tests exist because the BrokenPreferences scanner previously
// flagged any plist whose bundle ID wasn't currently registered with
// Launch Services — which caught Apple system daemons, helpers,
// frameworks, and any third-party app not currently registered with
// LS. That's a data-loss risk. These tests document the safe contract.

print("\n--- PlistJunkFilter Tests ---")

// Helper: build a valid binary plist payload so deserialization succeeds.
let validPlistData = try! PropertyListSerialization.data(
    fromPropertyList: ["key": "value"],
    format: .binary,
    options: 0
)
let validPlistLoader: (URL) -> Data? = { _ in validPlistData }

// LS state simulator: by default, NO bundle IDs are registered. This is the
// worst-case for false positives, because every real Apple system plist
// would fail a Launch Services lookup.
let noAppRegistered: (String) -> Bool = { _ in false }
let alwaysAppRegistered: (String) -> Bool = { _ in true }

test("PlistJunkFilter: corrupt plist is flagged") {
    let url = URL(filePath: "/tmp/com.example.broken.plist")
    let corruptLoader: (URL) -> Data? = { _ in Data([0x00, 0xFF, 0x00]) }
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: corruptLoader, appExistsForBundleID: alwaysAppRegistered
    )
    try assertTrue(result, "A plist that fails to deserialize must be flagged")
}

test("PlistJunkFilter: valid third-party plist is NOT flagged when app is registered") {
    let url = URL(filePath: "/tmp/com.example.realapp.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: alwaysAppRegistered
    )
    try assertFalse(result, "A valid plist with a registered owning app must never be flagged")
}

// --- SAFETY-CRITICAL tests below. These exposed the original bug. ---

test("PlistJunkFilter: Apple system plist (com.apple.loginwindow) is NEVER flagged") {
    let url = URL(filePath: "/Users/me/Library/Preferences/com.apple.loginwindow.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: noAppRegistered
    )
    try assertFalse(result, "com.apple.loginwindow.plist must never be flagged for deletion — it's a critical system file")
}

test("PlistJunkFilter: Apple system plist (com.apple.dock) is NEVER flagged") {
    let url = URL(filePath: "/Users/me/Library/Preferences/com.apple.dock.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: noAppRegistered
    )
    try assertFalse(result, "com.apple.dock.plist must never be flagged")
}

test("PlistJunkFilter: Apple system plist (com.apple.finder) is NEVER flagged") {
    let url = URL(filePath: "/Users/me/Library/Preferences/com.apple.finder.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: noAppRegistered
    )
    try assertFalse(result, "com.apple.finder.plist must never be flagged")
}

test("PlistJunkFilter: Apple App Group plist (group.com.apple.notes) is NEVER flagged") {
    let url = URL(filePath: "/Users/me/Library/Preferences/group.com.apple.notes.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: noAppRegistered
    )
    try assertFalse(result, "App Group preferences for Apple apps must never be flagged")
}

test("PlistJunkFilter: third-party plist NOT flagged just because LS doesn't know the bundle") {
    // Real-world case: an app the user installed but hasn't launched yet,
    // or one installed outside /Applications. LS may not know about it.
    let url = URL(filePath: "/Users/me/Library/Preferences/com.example.myapp.plist")
    let result = PlistJunkFilter.isLikelyBroken(
        at: url, loadData: validPlistLoader, appExistsForBundleID: noAppRegistered
    )
    try assertFalse(result, "A valid plist must never be flagged solely because Launch Services doesn't recognize its bundle ID. Too many false positives (uninstalled apps the user wants prefs preserved for, helpers, daemons, command-line tools, etc.)")
}

test("PlistJunkFilter: isAppleSystemDomain recognizes com.apple.* prefix") {
    try assertTrue(PlistJunkFilter.isAppleSystemDomain("com.apple.loginwindow"))
    try assertTrue(PlistJunkFilter.isAppleSystemDomain("com.apple.dock"))
    try assertTrue(PlistJunkFilter.isAppleSystemDomain("COM.APPLE.FINDER"))
    try assertFalse(PlistJunkFilter.isAppleSystemDomain("com.example.app"))
    try assertFalse(PlistJunkFilter.isAppleSystemDomain("net.macromates.TextMate"))
}

test("PlistJunkFilter: isAppleSystemDomain recognizes group.com.apple.* App Groups") {
    try assertTrue(PlistJunkFilter.isAppleSystemDomain("group.com.apple.notes"))
    try assertTrue(PlistJunkFilter.isAppleSystemDomain("group.com.apple.mail"))
}

// ============================================================
// MARK: - Summary
// ============================================================

print("\n" + String(repeating: "=", count: 50))
print("Results: \(passed) passed, \(failed) failed, \(passed + failed) total")
if !testErrors.isEmpty {
    print("\nFailed tests:")
    for (name, err) in testErrors {
        print("  - \(name): \(err)")
    }
}
print(String(repeating: "=", count: 50))

if failed > 0 {
    exit(1)
}
