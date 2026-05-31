import XCTest
@testable import MacClean
import MacCleanKit
import MacCleanTestSupport

/// Walks a synthetic `.app` bundle in /tmp to verify the scanner correctly
/// combines bundle inspection (Info.plist, _MASReceipt) with the pure
/// `UniversalBinariesPolicy` decision logic.
final class UniversalBinariesScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "UBScanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates a `.app` bundle structure with a real fat Mach-O executable.
    /// Returns the `.app` URL.
    private func makeFakeApp(
        name: String,
        bundleID: String,
        archs: [String] = ["x86_64", "arm64"],
        appStore: Bool = false
    ) throws -> URL {
        let appURL = root.appending(path: "\(name).app")
        let macOS = appURL.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let executableName = name.replacingOccurrences(of: " ", with: "")
        let exec = macOS.appending(path: executableName)
        let built = try UniversalBinaryFixture.build(at: exec, architectures: archs)
        try XCTSkipUnless(built, "cc not available")

        let infoPlist = appURL.appending(path: "Contents/Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": executableName,
            "CFBundleName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try plistData.write(to: infoPlist)

        if appStore {
            let receipt = appURL.appending(path: "Contents/_MASReceipt/receipt")
            try FileManager.default.createDirectory(
                at: receipt.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("fake-receipt".utf8).write(to: receipt)
        }
        return appURL
    }

    func testScanner_picksUpFatNonAppleApp() throws {
        _ = try makeFakeApp(name: "AcmeChat", bundleID: "com.acme.chat")

        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertEqual(items.count, 1, "AcmeChat should be eligible")
        XCTAssertTrue(items[0].url.path(percentEncoded: false).contains("AcmeChat.app"))
        XCTAssertGreaterThan(items[0].size, 0,
                             "estimated savings must be reported for the UI")
    }

    func testScanner_skipsAppleSystemBundleByID() throws {
        _ = try makeFakeApp(name: "Pretend Safari", bundleID: "com.apple.Safari")
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "com.apple.* bundles must be skipped by policy")
    }

    func testScanner_skipsAppStoreApps() throws {
        _ = try makeFakeApp(
            name: "AppStoreThing",
            bundleID: "com.example.appstore",
            appStore: true
        )
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "_MASReceipt presence must skip the bundle")
    }

    func testScanner_skipsSingleArchApp() throws {
        let onlyHost = BundleHostInfo.current.hostArch.lipoName
        _ = try makeFakeApp(name: "NativeOnly", bundleID: "com.example.native", archs: [onlyHost])
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertTrue(items.isEmpty, "single-arch app already matches host — nothing to thin")
    }

    /// End-to-end: scan a synthetic app, take its FileItem, hand to
    /// CleanActions.executeUserClean as a .universalBinaries ScanResult.
    /// Confirm the binary on disk is now single-arch.
    func testScannerToCleanActions_endToEnd_thinsTheBinaryInPlace() async throws {
        let appURL = try makeFakeApp(name: "AcmeChat", bundleID: "com.acme.chat")
        let items = UniversalBinariesScanner.scan(in: root)
        XCTAssertEqual(items.count, 1)
        let item = items[0]

        let result = await CleanActions.executeUserClean(
            results: [ScanResult(category: .universalBinaries, items: items, autoSelect: false)],
            selectedItems: [item.url],
            engine: CleaningEngine()
        )

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertTrue(result.errors.isEmpty, "no errors expected: \(result.errors)")

        let archsAfter = UniversalBinaryFixture.architectures(of: item.url)
        XCTAssertEqual(archsAfter, [BundleHostInfo.current.hostArch.lipoName])
        XCTAssertTrue(UniversalBinaryFixture.codesignVerifies(item.url))

        // App bundle still exists (just smaller).
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path(percentEncoded: false)))
    }
}
