import XCTest
import Foundation
@testable import MacCleanKit

/// Tests for the pure splitter logic that lives on `LargeOldFilesModule.splitLargeAndOld`.
/// (The module type itself is in MacClean target, but we test the static
/// splitter from here via the MacClean test target — see LargeOldFilesModuleTests.)
///
/// This file just provides shared FileItem fixtures used across tests.
enum LargeOldFilesFixtures {
    static func makeFile(_ name: String, size: UInt64, mod: Date? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: "/\(name)"),
            name: name, size: size, allocatedSize: size,
            isDirectory: false, modificationDate: mod
        )
    }
}
