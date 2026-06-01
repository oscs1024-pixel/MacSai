import Foundation
import MacCleanKit

public struct TrashBinsModule: ScanModule {
    public let id = "trash_bins"
    public let name = "Trash Bins"
    public let category = ModuleCategory.cleanup

    private let scanner = TargetedScanner()

    public init() {}

    public func scan() async -> [ScanResult] {
        var targets: [ScanTarget] = [
            // Main user trash
            ScanTarget(path: MCConstants.userTrash, recursive: true),
        ]

        // External drive trash bins
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes {
                let trashURL = volume.appending(path: ".Trashes")
                if FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) {
                    targets.append(ScanTarget(path: trashURL, recursive: true))
                }
            }
        }

        let items = await scanner.scan(targets: targets)
        guard !items.isEmpty else { return [] }

        return [ScanResult(category: .trashBins, items: items)]
            .filteringUncleanable()
    }
}
