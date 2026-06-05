import Foundation
import MacCleanKit

public actor XPCClient {
    private var connection: NSXPCConnection?

    public static let shared = XPCClient()

    private init() {}

    /// Requirement string the client uses to verify the HELPER's signature.
    /// Without this, a hostile app that registers the same Mach service
    /// name (a "rogue helper") could intercept our commands and feed us
    /// fake responses. The kernel rejects the connection if the listener
    /// on the other end doesn't satisfy this requirement.
    private static let helperRequirement =
        MCConstants.codeSigningRequirement(for: MCConstants.helperBundleIdentifier)

    public func connect() -> NSXPCConnection {
        if let existing = connection, !existing.isEqual(nil) {
            return existing
        }

        let conn = NSXPCConnection(
            machServiceName: MCConstants.helperBundleIdentifier,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: MacCleanHelperProtocol.self)

        // Symmetric guard: if the helper isn't who we expect (e.g. a rogue
        // helper registered the same Mach service name), the kernel
        // refuses to wire up the connection. setCodeSigningRequirement
        // throws synchronously if the requirement string is malformed;
        // any malformation here is a build-time bug we want to fail loud
        // about, hence try!.
        try! conn.setCodeSigningRequirement(Self.helperRequirement)

        conn.invalidationHandler = {
            // Connection invalidated — next call to connect() will create a new one
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func handleDisconnect() {
        connection = nil
    }

    public func removeFiles(atPaths paths: [String]) async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! MacCleanHelperProtocol

            proxy.removeFiles(atPaths: paths) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func runMaintenanceScript(_ script: String) async throws -> String {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! MacCleanHelperProtocol

            proxy.runMaintenanceScript(script) { output, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    public func flushDNSCache() async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! MacCleanHelperProtocol

            proxy.flushDNSCache { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func reindexSpotlight() async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! MacCleanHelperProtocol

            proxy.reindexSpotlight { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
