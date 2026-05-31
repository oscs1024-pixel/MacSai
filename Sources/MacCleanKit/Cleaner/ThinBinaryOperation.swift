import Foundation
import MacCleanKit
import OSLog

/// Strips redundant architecture slices from a Mach-O universal binary
/// and re-signs it. Atomic per-binary: makes a backup on the same volume,
/// promotes the thinned file by rename, re-signs in place, and rolls back
/// the backup if anything fails.
///
/// Pure decision-making lives in `UniversalBinariesPolicy` in MacCleanKit;
/// this type is the system-side actuator that actually invokes lipo +
/// codesign.
public actor ThinBinaryOperation {

    public struct Result: Sendable {
        public let originalSize: UInt64
        public let thinnedSize: UInt64
        public var bytesSaved: UInt64 {
            originalSize > thinnedSize ? originalSize - thinnedSize : 0
        }
    }

    public enum OpError: Error, LocalizedError, Sendable {
        case notFat
        case raceDetected(String)
        case lipoFailed(stderr: String)
        case codesignFailed(stderr: String)
        case verifyFailed(stderr: String)
        case backupFailed(String)
        /// The signing step failed AND the rollback failed too. This is the
        /// scariest state — the original file is gone, the thinned file may
        /// be unsigned. The error carries the backup URL so the caller can
        /// surface it to the user for manual recovery.
        case rollbackFailed(originalBackupAt: URL, underlying: String)

        public var errorDescription: String? {
            switch self {
            case .notFat:
                "input binary is not a fat (universal) Mach-O"
            case .raceDetected(let message):
                "binary changed under us while thinning: \(message)"
            case .lipoFailed(let stderr):
                "lipo failed: \(stderr)"
            case .codesignFailed(let stderr):
                "codesign failed: \(stderr)"
            case .verifyFailed(let stderr):
                "codesign verification failed: \(stderr)"
            case .backupFailed(let message):
                "atomic backup/promote failed: \(message)"
            case .rollbackFailed(let url, let underlying):
                "thinning failed AND rollback failed — manual recovery needed. " +
                "Original backup is at: \(url.path(percentEncoded: false)). Details: \(underlying)"
            }
        }
    }

    private let logger = Logger(subsystem: MCConstants.bundleIdentifier,
                                category: "ThinBinaryOperation")

    public init() {}

    /// Thin a binary AND re-sign it ad-hoc. Use for standalone binaries
    /// (not inside an app bundle whose other contents are mid-mutation).
    public func thin(binary: URL, to targetArch: BinaryArch) async throws -> Result {
        try await thin(binary: binary, to: targetArch, resign: true)
    }

    /// Thin only — no codesign step. Use this when an outer orchestrator
    /// (ThinAppBundleOperation) will do a single `codesign --deep` pass
    /// over the whole bundle once every binary is in its final form. Inner
    /// per-binary signing would otherwise fail because codesign validates
    /// the parent bundle's subcomponents on the way through, and an
    /// in-progress neighbor binary or framework would still be unsigned.
    public func thinOnly(binary: URL, to targetArch: BinaryArch) async throws -> Result {
        try await thin(binary: binary, to: targetArch, resign: false)
    }

    private func thin(binary: URL, to targetArch: BinaryArch, resign: Bool) async throws -> Result {
        let fm = FileManager.default
        let path = binary.path(percentEncoded: false)

        // 1. Confirm input is fat — if not, refuse cleanly without touching it.
        let archs = try Self.runLipoInfo(at: path)
        guard archs.count > 1 else {
            throw OpError.notFat
        }
        guard archs.contains(targetArch.lipoName) else {
            throw OpError.lipoFailed(stderr: "target arch \(targetArch.lipoName) not present in \(archs)")
        }

        let originalAttrs = try fm.attributesOfItem(atPath: path)
        let originalSize = (originalAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        let originalMode = (originalAttrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0o755
        let originalInode = (originalAttrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0

        // 2. Stage everything in a separate temp directory — NOT next to the
        //    original. codesign walks the bundle subtree looking for
        //    subcomponents to validate, so any stray backup file in the
        //    binary's parent dir (e.g. Contents/MacOS/) would be flagged as
        //    "code object is not signed at all" and abort the signing step.
        let workDir = fm.temporaryDirectory
            .appending(path: "macclean-thinning-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let thinningURL = workDir.appending(path: "\(binary.lastPathComponent).thinned")
        let backupURL = workDir.appending(path: "\(binary.lastPathComponent).original")

        // Race check: re-stat immediately before lipo. If the file has been
        // replaced (different inode) or grown/shrunk (different size), abort
        // — something else is rewriting this file and our lipo would overwrite
        // their changes.
        let preLipoAttrs = try fm.attributesOfItem(atPath: path)
        let preLipoSize = (preLipoAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        let preLipoInode = (preLipoAttrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        if preLipoInode != originalInode || preLipoSize != originalSize {
            throw OpError.raceDetected(
                "inode \(originalInode)→\(preLipoInode) or size \(originalSize)→\(preLipoSize) changed between start and lipo step"
            )
        }

        try Self.runLipoThin(
            input: path,
            output: thinningURL.path(percentEncoded: false),
            arch: targetArch.lipoName
        )
        try fm.setAttributes(
            [.posixPermissions: NSNumber(value: originalMode)],
            ofItemAtPath: thinningURL.path(percentEncoded: false)
        )

        // 3. Atomic-ish swap: move original out, move thinned in.
        do {
            try fm.moveItem(at: binary, to: backupURL)
        } catch {
            throw OpError.backupFailed("could not back up original: \(error.localizedDescription)")
        }
        do {
            try fm.moveItem(at: thinningURL, to: binary)
        } catch {
            try? fm.moveItem(at: backupURL, to: binary)
            throw OpError.backupFailed("could not promote thinned file: \(error.localizedDescription)")
        }

        // 4. Re-sign + verify (unless caller opted out — orchestrator will
        //    deep-sign at the bundle level).
        if resign {
            do {
                try Self.runCodesignAdhoc(at: path)
                try Self.runCodesignVerify(at: path)
            } catch {
                do {
                    try? fm.removeItem(at: binary)
                    try fm.moveItem(at: backupURL, to: binary)
                    throw error
                } catch let restoreError {
                    throw OpError.rollbackFailed(
                        originalBackupAt: backupURL,
                        underlying: "sign/verify failed: \(error.localizedDescription); rollback also failed: \(restoreError.localizedDescription)"
                    )
                }
            }
        }

        let thinnedAttrs = try fm.attributesOfItem(atPath: path)
        let thinnedSize = (thinnedAttrs[.size] as? NSNumber)?.uint64Value ?? 0
        logger.info("Thinned \(path, privacy: .public): \(originalSize) → \(thinnedSize)")
        return Result(originalSize: originalSize, thinnedSize: thinnedSize)
    }

    // MARK: - Shell-out helpers

    private static func runLipoInfo(at path: String) throws -> [String] {
        let (status, stdout, _) = try runProcess(
            "/usr/bin/lipo", ["-info", path]
        )
        guard status == 0 else { throw OpError.lipoFailed(stderr: stdout) }
        if let range = stdout.range(of: "are: ") {
            return stdout[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .map(String.init)
        }
        if let range = stdout.range(of: "is architecture: ") {
            return [stdout[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }

    private static func runLipoThin(input: String, output: String, arch: String) throws {
        let (status, _, stderr) = try runProcess(
            "/usr/bin/lipo", ["-thin", arch, input, "-output", output]
        )
        guard status == 0 else { throw OpError.lipoFailed(stderr: stderr) }
    }

    private static func runCodesignAdhoc(at path: String) throws {
        let (status, _, stderr) = try runProcess("/usr/bin/codesign", [
            "--force",
            "--sign", "-",
            "--preserve-metadata=identifier,entitlements,requirements,flags,runtime",
            path,
        ])
        guard status == 0 else { throw OpError.codesignFailed(stderr: stderr) }
    }

    private static func runCodesignVerify(at path: String) throws {
        let (status, _, stderr) = try runProcess(
            "/usr/bin/codesign", ["-v", path]
        )
        guard status == 0 else { throw OpError.verifyFailed(stderr: stderr) }
    }

    /// Returns `(status, stdout, stderr)`. Throws only if the process can't
    /// be launched at all.
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
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
