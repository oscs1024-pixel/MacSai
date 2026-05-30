import Foundation
import AppKit
import MacCleanKit

struct BrokenPreferencesCategory: JunkCategory {
    let scanCategory = ScanCategory.brokenPreferences

    var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.userPreferences,
                recursive: false,
                fileExtensions: ["plist"]
            ),
        ]
    }

    /// Filters down to only plists that are PROVABLY broken — i.e. fail to
    /// deserialize. Delegates to the pure `PlistJunkFilter` so the safety
    /// logic stays testable in isolation.
    ///
    /// Previously this also flagged any plist whose filename looked like an
    /// orphaned bundle ID. That caused false positives on Apple system files
    /// (`com.apple.loginwindow.plist`, etc.) and any app not currently
    /// registered with Launch Services. Removed for safety. See
    /// `MacCleanKit/PlistJunkFilter.swift` for the contract and tests.
    func filterBrokenPlists(_ items: [FileItem]) -> [FileItem] {
        items.filter { item in
            PlistJunkFilter.isLikelyBroken(
                at: item.url,
                loadData: { url in try? Data(contentsOf: url) },
                appExistsForBundleID: { bundleID in
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
                }
            )
        }
    }
}
