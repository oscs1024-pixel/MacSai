import XCTest
import Foundation
import Darwin
@testable import MacClean
import MacCleanKit
import MacCleanTestSupport

/// Integration tests for `TargetedScanner` — uses real synthetic file trees
/// to exercise the actual `FileManager.enumerator` code path.
final class TargetedScannerTests: XCTestCase {

    func testScansFlatDirectory() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "a.log"), size: 100)
            try TestFixtures.writeFile(at: dir.appending(path: "b.log"), size: 100)
            try TestFixtures.writeFile(at: dir.appending(path: "c.txt"), size: 100)

            let target = ScanTarget(path: dir, recursive: false)
            let items = await TargetedScanner().scan(targets: [target])
            XCTAssertEqual(items.count, 3)
        }
    }

    func testExtensionFilterRespected() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "x.log"), size: 1)
            try TestFixtures.writeFile(at: dir.appending(path: "y.crash"), size: 1)
            try TestFixtures.writeFile(at: dir.appending(path: "z.json"), size: 1)

            let target = ScanTarget(path: dir, recursive: false,
                                    fileExtensions: ["log", "crash"])
            let items = await TargetedScanner().scan(targets: [target])
            XCTAssertEqual(items.count, 2)
            XCTAssertTrue(items.allSatisfy { ["log", "crash"].contains($0.fileExtension) })
        }
    }

    func testExcludePatternRespected() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "com.spotify.client.cache"), size: 1)
            try TestFixtures.writeFile(at: dir.appending(path: "com.apple.cache"), size: 1)

            let target = ScanTarget(path: dir, recursive: false,
                                    excludePatterns: ["spotify"])
            let items = await TargetedScanner().scan(targets: [target])
            XCTAssertEqual(items.count, 1)
            XCTAssertFalse(items.contains { $0.name.contains("spotify") })
        }
    }

    func testMinSizeFilter() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "tiny.bin"), size: 100)
            try TestFixtures.writeFile(at: dir.appending(path: "big.bin"), size: 5000)

            let target = ScanTarget(path: dir, recursive: false, minSize: 1000)
            let items = await TargetedScanner().scan(targets: [target])
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.name, "big.bin")
        }
    }

    func testRecursiveScanFindsNestedFiles() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "top.log"), size: 100)
            try TestFixtures.writeFile(at: dir.appending(path: "nested/deep.log"), size: 100)
            try TestFixtures.writeFile(at: dir.appending(path: "nested/again/deepest.log"), size: 100)

            let items = await TargetedScanner().scan(
                targets: [ScanTarget(path: dir, recursive: true)]
            )
            // Expect 3 files + possibly the directories themselves
            let logs = items.filter { $0.fileExtension == "log" }
            XCTAssertEqual(logs.count, 3)
        }
    }

    func testNonExistentPathReturnsEmpty() async throws {
        let target = ScanTarget(
            path: URL(filePath: "/nonexistent-\(UUID().uuidString)"),
            recursive: true
        )
        let items = await TargetedScanner().scan(targets: [target])
        XCTAssertTrue(items.isEmpty)
    }

    func testMultipleTargetsAggregated() async throws {
        try await TestFixtures.withTempDir { dir in
            let a = dir.appending(path: "a")
            let b = dir.appending(path: "b")
            try TestFixtures.writeFile(at: a.appending(path: "x.log"), size: 1)
            try TestFixtures.writeFile(at: b.appending(path: "y.log"), size: 1)

            let items = await TargetedScanner().scan(targets: [
                ScanTarget(path: a, recursive: false),
                ScanTarget(path: b, recursive: false),
            ])
            XCTAssertEqual(items.count, 2)
        }
    }

    // MARK: - Overlapping targets must not double-count (duplicate-row bug)

    /// Mirrors the real Large & Old Files bug: that module scans `~`
    /// recursively *and* `~/Downloads` recursively, so every Downloads file
    /// was enumerated twice and surfaced as two identical rows (and a
    /// double-counted size estimate). Overlapping targets must emit each
    /// URL exactly once.
    func testOverlappingTargetsDeduplicateByURL() async throws {
        try await TestFixtures.withTempDir { dir in
            let downloads = dir.appending(path: "Downloads")
            try TestFixtures.writeFile(at: downloads.appending(path: "big.dmg"), size: 100)

            let items = await TargetedScanner().scan(targets: [
                ScanTarget(path: dir, recursive: true),        // parent sweep
                ScanTarget(path: downloads, recursive: true),  // explicit child — overlaps
            ])

            let dmgs = items.filter { $0.name == "big.dmg" }
            XCTAssertEqual(dmgs.count, 1,
                           "overlapping targets must not emit the same file twice")
        }
    }

    func testSameTargetListedTwiceDeduplicates() async throws {
        try await TestFixtures.withTempDir { dir in
            try TestFixtures.writeFile(at: dir.appending(path: "a.log"), size: 1)
            try TestFixtures.writeFile(at: dir.appending(path: "b.log"), size: 1)

            let target = ScanTarget(path: dir, recursive: false)
            let items = await TargetedScanner().scan(targets: [target, target])
            XCTAssertEqual(items.count, 2)
        }
    }

    // MARK: - Permission denial is surfaced, not swallowed (#1)

    /// `~/.Trash` without Full Disk Access reads as "empty" because the
    /// enumerator silently swallows EPERM. A chmod-000 directory reproduces
    /// the same EACCES denial: the scan must report it as `permissionDenied`
    /// rather than an indistinguishable empty result.
    func testPermissionDeniedDirectoryIsReported() async throws {
        try await TestFixtures.withTempDir { dir in
            let locked = dir.appending(path: "locked")
            try TestFixtures.writeFile(at: locked.appending(path: "secret.bin"), size: 10)
            _ = chmod(locked.path(percentEncoded: false), 0o000)
            defer { _ = chmod(locked.path(percentEncoded: false), 0o755) } // so cleanup can remove it

            let outcome = await TargetedScanner().scanReportingPermissions(
                targets: [ScanTarget(path: locked, recursive: true)]
            )

            XCTAssertTrue(outcome.items.isEmpty)
            XCTAssertTrue(outcome.permissionDenied,
                          "an unreadable directory must surface as permissionDenied")
            XCTAssertEqual(outcome.permissionDeniedPaths, [locked])
        }
    }

    func testReadableEmptyDirectoryIsNotPermissionDenied() async throws {
        try await TestFixtures.withTempDir { dir in
            let outcome = await TargetedScanner().scanReportingPermissions(
                targets: [ScanTarget(path: dir, recursive: true)]
            )
            XCTAssertFalse(outcome.permissionDenied,
                           "a readable but empty dir is not a permission problem")
        }
    }
}
