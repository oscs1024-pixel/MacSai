import Foundation
import MacCleanKit

/// Walks `.app` bundles under a search root, asks `UniversalBinariesPolicy`
/// whether each is safe to thin, and surfaces the eligible main executables
/// as `FileItem`s.
///
/// Decision logic is pure and lives in MacCleanKit (`UniversalBinariesPolicy`);
/// this type's only job is to gather the inputs from the filesystem and
/// call into the policy.
public enum UniversalBinariesScanner {

    /// Scans `searchRoot` (default `/Applications`) for thinnable apps.
    /// Returns one `FileItem` per eligible main executable. The item's `size`
    /// is the estimated savings, not the executable's real size, so the
    /// scan-results UI shows the user a meaningful "you'll save X MB" number.
    public static func scan(
        in searchRoot: URL = URL(filePath: "/Applications"),
        host: BundleHostInfo = .current,
        policy: UniversalBinariesPolicy = UniversalBinariesPolicy()
    ) -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: searchRoot, includingPropertiesForKeys: nil
        ) else { return [] }

        var results: [FileItem] = []
        for appURL in entries where appURL.pathExtension == "app" {
            guard let item = thinnableItem(appURL: appURL, host: host, policy: policy) else {
                continue
            }
            results.append(item)
        }
        return results
    }

    /// Gathers info for one bundle, asks the policy, and returns the
    /// associated `FileItem` if the policy says to thin.
    static func thinnableItem(
        appURL: URL,
        host: BundleHostInfo,
        policy: UniversalBinariesPolicy
    ) -> FileItem? {
        // Read Info.plist directly rather than going through Bundle — Bundle's
        // load behavior varies across macOS versions and quietly returns nil
        // for bundles missing keys we don't actually need.
        let infoURL = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String
        else { return nil }

        let executableURL = appURL.appending(path: "Contents/MacOS/\(executable)")
        guard FileManager.default.fileExists(
            atPath: executableURL.path(percentEncoded: false)
        ) else { return nil }

        let isAppStore = FileManager.default.fileExists(
            atPath: appURL.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false)
        )
        let lipoArchs = runLipoInfo(at: executableURL)
        let archSet: Set<BinaryArch> = Set(lipoArchs.compactMap(BinaryArch.init(lipoName:)))
        guard !archSet.isEmpty else { return nil }

        let info = AppBundleInfo(
            bundlePath: appURL.path(percentEncoded: false),
            bundleID: bundleID,
            isAppStore: isAppStore,
            architectures: archSet
        )

        guard case .thin(_, let dropping) = policy.decideThinning(for: info, host: host) else {
            return nil
        }

        let execSize: UInt64 = {
            let attrs = try? FileManager.default
                .attributesOfItem(atPath: executableURL.path(percentEncoded: false))
            return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        }()

        let savings = UniversalBinariesPolicy.estimatedSavings(
            originalSize: execSize,
            originalArchCount: archSet.count,
            droppingCount: dropping.count
        )

        return FileItem(
            url: executableURL,
            name: "\(appURL.deletingPathExtension().lastPathComponent) (drop \(dropping.map { $0.lipoName }.sorted().joined(separator: ", ")))",
            size: savings,
            allocatedSize: savings,
            isDirectory: false
        )
    }

    private static func runLipoInfo(at url: URL) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/lipo")
        process.arguments = ["-info", url.path(percentEncoded: false)]
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        if let r = output.range(of: "are: ") {
            return output[r.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").map(String.init)
        }
        if let r = output.range(of: "is architecture: ") {
            return [output[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }
}
