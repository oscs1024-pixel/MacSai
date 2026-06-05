import XCTest
@testable import MacClean

final class SettingsNavigationTests: XCTestCase {
    func testSettingsDeepLinkRoundTrips() {
        XCTAssertEqual(SidebarItem.settings.deepLinkID, "settings")
        XCTAssertEqual(SidebarItem(deepLinkID: "settings"), .settings)
    }

    /// Settings is opened from the pinned footer, never from the scrolling
    /// section list. If it leaks into a section the sidebar shows it twice.
    func testSettingsExcludedFromSidebarSections() {
        let listed = SidebarSection.allCases.flatMap(\.items)
        XCTAssertFalse(listed.contains(.settings))
        XCTAssertTrue(SidebarItem.allCases.contains(.settings))
    }

    /// Existing module rows must be unaffected by the items filter.
    func testExistingSectionsStillListTheirItems() {
        XCTAssertEqual(SidebarSection.main.items, [.smartScan])
        XCTAssertTrue(SidebarSection.cleanup.items.contains(.systemJunk))
        XCTAssertTrue(SidebarSection.files.items.contains(.shredder))
    }
}
