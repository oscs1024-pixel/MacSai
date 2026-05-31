import Foundation
import MacCleanKit
import OSLog

/// Walks an entire `.app` bundle, thins every fat Mach-O inside it via
/// `ThinBinaryOperation`, then re-seals the outer bundle (and its nested
/// `.framework` / `.xpc` / `.appex` bundles) with `codesign --deep`.
///
/// `ThinBinaryOperation` re-signs each Mach-O individually, but a nested
/// bundle's `_CodeSignature/CodeResources` file references hashes of its
/// contents — those hashes change when we lipo the inner binary, so the
/// nested bundle's seal also has to be regenerated. `--deep` does that
/// recursively in one shot. The flag is deprecated for *initial* signing,
/// but it's the practical answer for re-signing after a binary mod.
public actor ThinAppBundleOperation {

    public struct Result: Sendable {
        public let binariesProcessed: Int
        public let binariesThinned: Int
        public let bytesSaved: UInt64
        public let perBinaryErrors: [String: String]   // path → error
        public let bundleVerifyFailed: Bool
    }

    public enum OpError: Error, LocalizedError, Sendable {
        case noFatBinariesFound
        case bundleResignFailed(stderr: String)
        case bundleVerifyFailed(stderr: String)

        public var errorDescription: String? {
            switch self {
            case .noFatBinariesFound:
                "no fat (universal) Mach-O binaries found in bundle"
            case .bundleResignFailed(let s):
                "bundle re-sign failed: \(s)"
            case .bundleVerifyFailed(let s):
                "bundle verification failed after re-sign: \(s)"
            }
        }
    }

    private let logger = Logger(subsystem: MCConstants.bundleIdentifier,
                                category: "ThinAppBundleOperation")

    public init() {}

    public func thin(bundle: URL, to targetArch: BinaryArch) async throws -> Result {
        let binaries = MachOWalker.fatBinaries(in: bundle)
        guard !binaries.isEmpty else { throw OpError.noFatBinariesFound }

        let op = ThinBinaryOperation()
        var thinned = 0
        var saved: UInt64 = 0
        var perBin: [String: String] = [:]

        for binary in binaries {
            do {
                // thinOnly: skip the per-binary codesign step — we'll do
                // one --deep pass over the whole bundle below.
                let r = try await op.thinOnly(binary: binary, to: targetArch)
                thinned += 1
                saved += r.bytesSaved
            } catch {
                let path = binary.path(percentEncoded: false)
                perBin[path] = error.localizedDescription
                logger.error("ThinBinaryOperation failed on \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Re-seal the outer bundle (and its nested bundles via --deep).
        // Skip the seal step if every binary failed — the bundle is unchanged.
        var verifyFailed = false
        if thinned > 0 {
            try Self.runCodesignDeep(bundle: bundle)
            do {
                try Self.runCodesignVerify(bundle: bundle)
            } catch {
                verifyFailed = true
                throw OpError.bundleVerifyFailed(stderr: error.localizedDescription)
            }
        }

        return Result(
            binariesProcessed: binaries.count,
            binariesThinned: thinned,
            bytesSaved: saved,
            perBinaryErrors: perBin,
            bundleVerifyFailed: verifyFailed
        )
    }

    // MARK: - codesign helpers

    private static func runCodesignDeep(bundle: URL) throws {
        let (status, _, stderr) = try runProcess("/usr/bin/codesign", [
            "--force",
            "--deep",
            "--sign", "-",
            "--preserve-metadata=identifier,entitlements,requirements,flags,runtime",
            bundle.path(percentEncoded: false),
        ])
        guard status == 0 else { throw OpError.bundleResignFailed(stderr: stderr) }
    }

    private static func runCodesignVerify(bundle: URL) throws {
        let (status, _, stderr) = try runProcess("/usr/bin/codesign", [
            "--verify",
            "--deep",
            bundle.path(percentEncoded: false),
        ])
        guard status == 0 else { throw OpError.bundleVerifyFailed(stderr: stderr) }
    }

    private static func runProcess(
        _ executable: String, _ args: [String]
    ) throws -> (Int32, String, String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
