import Foundation

/// The logic the XPC helper runs when the main app asks it to thin an
/// app bundle on the user's behalf. Lives in MacCleanKit (not in the
/// MacCleanHelper executable target) so tests can exercise it without
/// spinning up an actual LaunchDaemon — and so the helper executable
/// stays a thin shim that just bridges XPC into this function.
///
/// All defenses (protected-path check, arch parsing, ThinAppBundleOperation
/// dispatch) live here; the executable just translates the @objc reply
/// closure into a sendable callback.
public enum HelperThinning {

    public enum HelperError: Error, Equatable {
        case protectedPath(String)
        case unknownArch(String)
        case operationFailed(String)
    }

    public struct Result: Sendable, Equatable {
        public let bytesSaved: UInt64
        public init(bytesSaved: UInt64) { self.bytesSaved = bytesSaved }
    }

    /// Returns the bytes saved on success, throws on protected-path /
    /// unknown-arch / operation-failure. Caller maps to whatever transport
    /// (NSError + reply, async throws, etc) it needs.
    public static func thinAppBundle(
        atPath path: String,
        targetArchName: String,
        protectedPaths: Set<String> = MCConstants.protectedPaths
    ) async throws -> Result {
        let resolved = URL(filePath: path)
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)

        for protected in protectedPaths {
            if resolved == protected || resolved.hasPrefix(protected + "/") {
                throw HelperError.protectedPath(resolved)
            }
        }
        if resolved.hasPrefix("/System/") || resolved == "/System" {
            throw HelperError.protectedPath(resolved)
        }

        guard let arch = BinaryArch(lipoName: targetArchName) else {
            throw HelperError.unknownArch(targetArchName)
        }

        do {
            let result = try await ThinAppBundleOperation().thin(
                bundle: URL(filePath: resolved), to: arch
            )
            if !result.perBinaryErrors.isEmpty {
                let joined = result.perBinaryErrors
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "; ")
                throw HelperError.operationFailed("per-binary errors: \(joined)")
            }
            return Result(bytesSaved: result.bytesSaved)
        } catch let helperError as HelperError {
            throw helperError
        } catch {
            throw HelperError.operationFailed(error.localizedDescription)
        }
    }
}
