import XCTest
@testable import MacCleanKit
import MacCleanTestSupport

/// Exercises the XPC helper's thinning entry point (`HelperThinning`),
/// which is the logic the LaunchDaemon runs on the user's behalf for
/// app bundles in root-owned locations like /Applications.
///
/// HelperOperations.thinAppBundle (in the MacCleanHelper executable
/// target) is a one-line shim that calls into this; testing the shim
/// itself requires installing a real LaunchDaemon which is out of scope.
final class HelperThinningTests: XCTestCase {

    private var bundleURL: URL!

    override func setUpWithError() throws {
        let raw = FileManager.default.temporaryDirectory
            .appending(path: "HelperOp-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        bundleURL = URL(filePath: raw.resolvingSymlinksInPath().path(percentEncoded: false))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleURL)
    }

    private func writeMinimalApp(name: String, bundleID: String) throws {
        let macOS = bundleURL.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let exec = macOS.appending(path: name)
        let built = try UniversalBinaryFixture.build(at: exec)
        try XCTSkipUnless(built, "cc not available")

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": name,
            "CFBundleName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try infoData.write(to: bundleURL.appending(path: "Contents/Info.plist"))
    }

    // MARK: - Happy path

    func testHappyPath_thinsBundleAndReportsBytesSaved() async throws {
        try writeMinimalApp(name: "HelperApp", bundleID: "com.acme.helperapp")
        let exec = bundleURL.appending(path: "Contents/MacOS/HelperApp")

        let result = try await HelperThinning.thinAppBundle(
            atPath: bundleURL.path(percentEncoded: false),
            targetArchName: BundleHostInfo.current.hostArch.lipoName
        )

        XCTAssertGreaterThan(result.bytesSaved, 0)
        XCTAssertEqual(UniversalBinaryFixture.architectures(of: exec),
                       [BundleHostInfo.current.hostArch.lipoName])
    }

    // MARK: - Defense in depth

    func testRefusesProtectedPath_evenAsRoot() async {
        do {
            _ = try await HelperThinning.thinAppBundle(
                atPath: "/System/Library/CoreServices/Finder.app",
                targetArchName: "arm64"
            )
            XCTFail("must refuse /System/* even when invoked as root")
        } catch HelperThinning.HelperError.protectedPath(let p) {
            XCTAssertTrue(p.hasPrefix("/System/"),
                          "error must surface the offending path: \(p)")
        } catch {
            XCTFail("expected .protectedPath, got: \(error)")
        }
    }

    func testRefusesArbitraryProtectedPath() async {
        do {
            _ = try await HelperThinning.thinAppBundle(
                atPath: "/usr/bin/lipo",
                targetArchName: "arm64"
            )
            XCTFail("must refuse a path under any of MCConstants.protectedPaths")
        } catch HelperThinning.HelperError.protectedPath {
            // Expected.
        } catch {
            XCTFail("expected .protectedPath, got: \(error)")
        }
    }

    // MARK: - Bad input

    func testRejectsUnknownArch() async {
        do {
            _ = try await HelperThinning.thinAppBundle(
                atPath: "/tmp/nonexistent.app",
                targetArchName: "ppc64"
            )
            XCTFail("ppc64 isn't a BinaryArch — must reject")
        } catch HelperThinning.HelperError.unknownArch(let a) {
            XCTAssertEqual(a, "ppc64")
        } catch {
            XCTFail("expected .unknownArch, got: \(error)")
        }
    }

    func testReportsOperationFailureForNonexistentBundle() async {
        do {
            _ = try await HelperThinning.thinAppBundle(
                atPath: "/tmp/macclean-does-not-exist-\(UUID().uuidString).app",
                targetArchName: BundleHostInfo.current.hostArch.lipoName
            )
            XCTFail("must propagate the underlying noFatBinariesFound failure")
        } catch HelperThinning.HelperError.operationFailed {
            // Expected — wrapped from ThinAppBundleOperation.OpError.
        } catch {
            XCTFail("expected .operationFailed, got: \(error)")
        }
    }

    // MARK: - Protocol contract

    func testHelperProtocolDeclaresThinAppBundleMethod() {
        // Compile-time check: ensure the protocol method exists with the
        // expected shape. If someone renames the method or changes the
        // arity, this fails to compile — a louder failure than a runtime
        // selector miss in production XPC.
        let _: (MacCleanHelperProtocol) -> (String, String, @escaping (UInt64, NSError?) -> Void) -> Void
            = { proto in proto.thinAppBundle(atPath:targetArchName:reply:) }
    }
}
