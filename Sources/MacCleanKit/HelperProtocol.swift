import Foundation

@objc public protocol MacCleanHelperProtocol {
    func removeFiles(atPaths paths: [String], reply: @escaping (NSError?) -> Void)
    func runMaintenanceScript(_ script: String, reply: @escaping (String, NSError?) -> Void)
    func flushDNSCache(reply: @escaping (NSError?) -> Void)
    func repairPermissions(reply: @escaping (String, NSError?) -> Void)
    func reindexSpotlight(reply: @escaping (NSError?) -> Void)
    func thinTimeMachineSnapshots(reply: @escaping (String, NSError?) -> Void)
    func freeUpPurgeableSpace(reply: @escaping (String, NSError?) -> Void)

    /// Thin every fat Mach-O inside an .app bundle and re-sign it as the
    /// helper (root). Returns the byte count saved in `bytesSaved`. The
    /// app bundle must be writable by root (true for everything in
    /// /Applications), pass SafetyGuard's protected-path check on the
    /// helper side, and survive a `codesign --verify --deep` after.
    func thinAppBundle(
        atPath path: String,
        targetArchName: String,
        reply: @escaping (UInt64, NSError?) -> Void
    )
}
