import Foundation
import MacCleanKit

final class HelperOperations: NSObject, MacCleanHelperProtocol {

    func removeFiles(atPaths paths: [String], reply: @escaping (NSError?) -> Void) {
        let fm = FileManager.default
        var lastError: NSError?

        for path in paths {
            // Safety: never touch protected paths even from the helper
            let url = URL(filePath: path)
            let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)

            if isProtected(resolved) {
                lastError = NSError(
                    domain: "MacCleanHelper",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Protected path: \(resolved)"]
                )
                continue
            }

            do {
                try fm.removeItem(atPath: path)
            } catch {
                lastError = error as NSError
            }
        }

        reply(lastError)
    }

    func runMaintenanceScript(_ script: String, reply: @escaping (String, NSError?) -> Void) {
        let allowedScripts = ["daily", "weekly", "monthly"]
        guard allowedScripts.contains(script) else {
            reply("", NSError(domain: "MacCleanHelper", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Script not allowed: \(script)"]))
            return
        }

        let result = runProcess("/usr/sbin/periodic", args: [script])
        reply(result.output, result.error)
    }

    func flushDNSCache(reply: @escaping (NSError?) -> Void) {
        _ = runProcess("/usr/bin/dscacheutil", args: ["-flushcache"])
        let result = runProcess("/usr/bin/killall", args: ["-HUP", "mDNSResponder"])
        reply(result.error)
    }

    func repairPermissions(reply: @escaping (String, NSError?) -> Void) {
        let result = runProcess("/usr/sbin/diskutil", args: ["repairPermissions", "/"])
        reply(result.output, result.error)
    }

    func reindexSpotlight(reply: @escaping (NSError?) -> Void) {
        let result = runProcess("/usr/bin/mdutil", args: ["-E", "/"])
        reply(result.error)
    }

    func thinTimeMachineSnapshots(reply: @escaping (String, NSError?) -> Void) {
        let result = runProcess("/usr/bin/tmutil", args: [
            "thinlocalsnapshots", "/", "999999999999", "4",
        ])
        reply(result.output, result.error)
    }

    func freeUpPurgeableSpace(reply: @escaping (String, NSError?) -> Void) {
        let result = runProcess("/usr/sbin/diskutil", args: [
            "apfs", "defragment", "/", "live",
        ])
        reply(result.output, result.error)
    }

    func thinAppBundle(
        atPath path: String,
        targetArchName: String,
        reply: @escaping (UInt64, NSError?) -> Void
    ) {
        // All defenses live in HelperThinning (MacCleanKit) so tests can
        // exercise them without an XPC harness. This thin shim just bridges
        // the @objc reply closure to async throws.
        let bridge = ReplyBridge(reply: reply)
        Task.detached {
            do {
                let r = try await HelperThinning.thinAppBundle(
                    atPath: path, targetArchName: targetArchName
                )
                bridge.deliver(bytes: r.bytesSaved, error: nil)
            } catch let e as HelperThinning.HelperError {
                let (code, msg): (Int, String) = {
                    switch e {
                    case .protectedPath(let p):  (10, "Refused to thin protected path: \(p)")
                    case .unknownArch(let a):    (11, "Unknown architecture: \(a)")
                    case .operationFailed(let m): (12, m)
                    }
                }()
                bridge.deliver(bytes: 0, error: NSError(
                    domain: "MacCleanHelper", code: code,
                    userInfo: [NSLocalizedDescriptionKey: msg]
                ))
            } catch {
                bridge.deliver(bytes: 0, error: error as NSError)
            }
        }
    }

    // MARK: - Helpers

    private func isProtected(_ path: String) -> Bool {
        for protected in MCConstants.protectedPaths {
            if path.hasPrefix(protected + "/") || path == protected {
                return true
            }
        }
        return false
    }

    /// Sendable wrapper around the @objc reply closure so detached Tasks
    /// can deliver results without Swift 6 strict-concurrency complaints.
    /// The closure is delivered to exactly once by XPC semantics — no
    /// actual concurrent access risk.
    private final class ReplyBridge: @unchecked Sendable {
        private let reply: (UInt64, NSError?) -> Void
        init(reply: @escaping (UInt64, NSError?) -> Void) { self.reply = reply }
        func deliver(bytes: UInt64, error: NSError?) { reply(bytes, error) }
    }

    private struct ProcessResult {
        let output: String
        let error: NSError?
    }

    private func runProcess(_ command: String, args: [String]) -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(filePath: command)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorStr = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                return ProcessResult(
                    output: output,
                    error: NSError(domain: "MacCleanHelper", code: Int(process.terminationStatus),
                                   userInfo: [NSLocalizedDescriptionKey: errorStr.isEmpty ? "Process exited with code \(process.terminationStatus)" : errorStr])
                )
            }

            return ProcessResult(output: output, error: nil)
        } catch {
            return ProcessResult(output: "", error: error as NSError)
        }
    }
}
