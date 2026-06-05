import Foundation
import MacCleanKit

final class HelperTool: NSObject {
    private var listener: NSXPCListener?
    private var connections: [NSXPCConnection] = []

    /// Requirement string every inbound connection's caller must satisfy.
    /// macOS rejects any message on the connection whose remote end fails
    /// this check — without it, ANY local process could connect to our
    /// LaunchDaemon and call its root-privileged RPC methods.
    private static let callerRequirement =
        MCConstants.codeSigningRequirement(for: MCConstants.bundleIdentifier)

    func run() {
        let listener = NSXPCListener(
            machServiceName: MCConstants.helperBundleIdentifier
        )
        listener.delegate = self
        self.listener = listener
        listener.resume()
        RunLoop.current.run()
    }
}

extension HelperTool: NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Primary defense (kernel-enforced): demand the caller's signature
        // matches our requirement before any message is dispatched. Without
        // this, any local process could connect and trigger our root RPCs
        // (removeFiles, runMaintenanceScript, etc) — a clean local
        // privilege-escalation vector. setCodeSigningRequirement throws
        // only on a malformed requirement string; we'd treat that as
        // refuse-the-connection.
        do {
            try newConnection.setCodeSigningRequirement(Self.callerRequirement)
        } catch {
            fputs("HelperTool: setCodeSigningRequirement failed: \(error)\n",
                  stderr)
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(
            with: MacCleanHelperProtocol.self
        )
        newConnection.exportedObject = HelperOperations()
        newConnection.invalidationHandler = { [weak self] in
            self?.connections.removeAll { $0 === newConnection }
        }
        connections.append(newConnection)
        newConnection.resume()
        return true
    }
}
