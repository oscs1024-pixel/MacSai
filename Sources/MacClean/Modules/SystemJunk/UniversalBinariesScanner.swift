import Foundation
import MacCleanKit

/// System-side wrapper around `UniversalBinariesCategory`'s pure logic.
/// Walks `/Applications`, shells out to `lipo`, and uses the pure
/// `parseLipoOutput` + `hasRedundantSlice` functions to decide what's
/// safe to surface for cleanup.
public enum UniversalBinariesScanner {

    public static func scanForRedundantSlices() -> [FileItem] {
        var results: [FileItem] = []
        let fm = FileManager.default
        let appsDir = URL(filePath: "/Applications")

        guard let apps = try? fm.contentsOfDirectory(at: appsDir, includingPropertiesForKeys: nil)
        else { return [] }

        let hostArch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "x86_64"
            #endif
        }()

        for appURL in apps where appURL.pathExtension == "app" {
            let macOSDir = appURL.appending(path: "Contents/MacOS")
            guard let binaries = try? fm.contentsOfDirectory(at: macOSDir, includingPropertiesForKeys: nil)
            else { continue }

            for binaryURL in binaries {
                guard let lipoOutput = runLipoInfo(on: binaryURL),
                      let archs = UniversalBinariesCategory.parseLipoOutput(lipoOutput),
                      UniversalBinariesCategory.hasRedundantSlice(architectures: archs, hostArch: hostArch)
                else { continue }

                let values = try? binaryURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                let size = UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                let estimatedSaving = size / UInt64(archs.count)

                results.append(FileItem(
                    url: binaryURL,
                    name: "\(appURL.deletingPathExtension().lastPathComponent) (other-arch slice)",
                    size: estimatedSaving,
                    allocatedSize: estimatedSaving,
                    isDirectory: false
                ))
            }
        }

        return results
    }

    private static func runLipoInfo(on url: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/lipo")
        process.arguments = ["-info", url.path(percentEncoded: false)]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
