import Foundation
import MacCleanKit

/// System-side wrapper around `DeletedUsersCategory`'s pure logic.
/// Reads active usernames via `dscl`, compares to `/Users` contents using
/// the pure `isResidualHomeFolder` decision function.
public enum DeletedUsersScanner {

    public static func scanForDeletedUserFolders() -> [FileItem] {
        let fm = FileManager.default
        let usersDir = URL(filePath: "/Users")

        guard let userFolders = try? fm.contentsOfDirectory(
            at: usersDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let activeUsers = readActiveUsernames()

        var results: [FileItem] = []
        for folder in userFolders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let name = folder.lastPathComponent
            guard DeletedUsersCategory.isResidualHomeFolder(name: name, activeUsers: activeUsers)
            else { continue }

            let size = directorySize(folder)
            results.append(FileItem(
                url: folder,
                name: name,
                size: size,
                allocatedSize: size,
                isDirectory: true
            ))
        }
        return results
    }

    private static func readActiveUsernames() -> Set<String> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/dscl")
        process.arguments = [".", "-list", "/Users"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return DeletedUsersCategory.parseDsclOutput(output)
        } catch {
            return Set()
        }
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(v?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
