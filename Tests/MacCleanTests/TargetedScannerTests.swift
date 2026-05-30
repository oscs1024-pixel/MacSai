import XCTest
import Foundation
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
}
