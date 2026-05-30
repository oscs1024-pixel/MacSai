import XCTest
import Foundation
@testable import MacClean
@testable import MacCleanKit

final class LargeOldFilesSplitterTests: XCTestCase {

    private func makeFile(_ name: String, size: UInt64, mod: Date? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: "/\(name)"),
            name: name, size: size, allocatedSize: size,
            isDirectory: false, modificationDate: mod
        )
    }

    func testSplitLargeAndOld_classifies() {
        let now = Date()
        let yearOld = now.addingTimeInterval(-365 * 24 * 3600)
        let recent = now.addingTimeInterval(-10 * 24 * 3600)

        let items = [
            makeFile("big-recent", size: 100 * 1024 * 1024, mod: recent),
            makeFile("small-old", size: 1024, mod: yearOld),
            makeFile("big-old", size: 200 * 1024 * 1024, mod: yearOld),
        ]
        let split = LargeOldFilesModule.splitLargeAndOld(items: items, minSize: 50 * 1024 * 1024, now: now)
        // Large = anything ≥ 50 MB → big-recent + big-old
        XCTAssertEqual(split.large.count, 2)
        // Old = > 180 days → small-old + big-old (small-old by date only)
        XCTAssertEqual(split.old.count, 2)
    }

    func testSplitSortsLargeBySize() {
        let items = [
            makeFile("a", size: 100 * 1024 * 1024),
            makeFile("b", size: 500 * 1024 * 1024),
            makeFile("c", size: 200 * 1024 * 1024),
        ]
        let split = LargeOldFilesModule.splitLargeAndOld(items: items, minSize: 50 * 1024 * 1024)
        XCTAssertEqual(split.large.map(\.name), ["b", "c", "a"])
    }

    func testSplitIgnoresDirectories() {
        let dir = FileItem(
            url: URL(filePath: "/folder"), name: "folder", size: 1_000_000_000,
            allocatedSize: 1_000_000_000, isDirectory: true
        )
        let split = LargeOldFilesModule.splitLargeAndOld(items: [dir], minSize: 1024)
        XCTAssertTrue(split.large.isEmpty)
        XCTAssertTrue(split.old.isEmpty)
    }

    func testSplitNoModDateNotIncludedInOld() {
        let items = [makeFile("undated", size: 100 * 1024 * 1024, mod: nil)]
        let split = LargeOldFilesModule.splitLargeAndOld(items: items, minSize: 50 * 1024 * 1024)
        XCTAssertEqual(split.large.count, 1)
        XCTAssertEqual(split.old.count, 0)
    }
}
