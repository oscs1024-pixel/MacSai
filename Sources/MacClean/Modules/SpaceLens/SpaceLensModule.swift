import Foundation
import MacCleanKit

public struct SpaceLensModule: ScanModule {
    public let id = "space_lens"
    public let name = "Space Lens"
    public let category = ModuleCategory.files
    public let includedInSmartScan = false

    public init() {}

    public func scan() async -> [ScanResult] {
        []
    }
}

// MARK: - Squarified Treemap Algorithm

public struct TreemapRect: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let node: TreemapNode
    public let rect: CGRect
}

public struct TreemapNode: Sendable {
    public let name: String
    public let size: UInt64
    public let url: URL
    public let isDirectory: Bool
    public let children: [TreemapNode]

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

public enum SquarifiedTreemap {
    public static func layout(nodes: [TreemapNode], in rect: CGRect) -> [TreemapRect] {
        guard !nodes.isEmpty else { return [] }

        let totalSize = nodes.reduce(0.0) { $0 + Double($1.size) }
        guard totalSize > 0 else { return [] }

        let sorted = nodes.sorted { $0.size > $1.size }
        let areas = sorted.map { Double($0.size) / totalSize * Double(rect.width * rect.height) }

        var results: [TreemapRect] = []
        var remaining = Array(zip(sorted, areas))
        var currentRect = rect

        while !remaining.isEmpty {
            let (row, rest, newRect) = squarify(remaining: remaining, in: currentRect)
            results.append(contentsOf: row)
            remaining = rest
            currentRect = newRect
        }

        return results
    }

    private static func squarify(
        remaining: [(TreemapNode, Double)],
        in rect: CGRect
    ) -> ([TreemapRect], [(TreemapNode, Double)], CGRect) {
        guard !remaining.isEmpty else { return ([], [], rect) }

        let isWide = rect.width >= rect.height
        let sideLength = isWide ? rect.height : rect.width

        var row: [(TreemapNode, Double)] = []
        var rowArea: Double = 0
        var bestAspect = Double.infinity
        var rest = remaining

        for (i, (node, area)) in remaining.enumerated() {
            let newRow = row + [(node, area)]
            let newRowArea = rowArea + area
            let aspect = worstAspectRatio(areas: newRow.map(\.1), totalArea: newRowArea, sideLength: Double(sideLength))

            if aspect <= bestAspect {
                row = newRow
                rowArea = newRowArea
                bestAspect = aspect
                rest = Array(remaining.dropFirst(i + 1))
            } else {
                rest = Array(remaining.dropFirst(i))
                break
            }
        }

        let rowLength = rowArea / Double(sideLength)
        var results: [TreemapRect] = []
        var offset: CGFloat = 0

        for (node, area) in row {
            let itemLength = area / rowLength
            let itemRect: CGRect

            if isWide {
                itemRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + offset,
                    width: CGFloat(rowLength),
                    height: CGFloat(itemLength)
                )
            } else {
                itemRect = CGRect(
                    x: rect.minX + offset,
                    y: rect.minY,
                    width: CGFloat(itemLength),
                    height: CGFloat(rowLength)
                )
            }

            results.append(TreemapRect(node: node, rect: itemRect))
            offset += CGFloat(itemLength)
        }

        let newRect: CGRect
        if isWide {
            newRect = CGRect(
                x: rect.minX + CGFloat(rowLength),
                y: rect.minY,
                width: rect.width - CGFloat(rowLength),
                height: rect.height
            )
        } else {
            newRect = CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(rowLength),
                width: rect.width,
                height: rect.height - CGFloat(rowLength)
            )
        }

        return (results, rest, newRect)
    }

    private static func worstAspectRatio(areas: [Double], totalArea: Double, sideLength: Double) -> Double {
        guard !areas.isEmpty, sideLength > 0, totalArea > 0 else { return .infinity }
        let s2 = sideLength * sideLength

        var worst: Double = 0
        for area in areas {
            let ratio1 = (s2 * area) / (totalArea * totalArea)
            let ratio2 = (totalArea * totalArea) / (s2 * area)
            worst = max(worst, max(ratio1, ratio2))
        }
        return worst
    }
}

// MARK: - Volume Info

public struct VolumeInfo: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let name: String
    public let url: URL
    public let totalCapacity: UInt64
    public let availableCapacity: UInt64
    public let fileSystemType: String?

    public var usedCapacity: UInt64 { totalCapacity - availableCapacity }
    public var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public static func mountedVolumes() -> [VolumeInfo] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeLocalizedFormatDescriptionKey,
            ],
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeLocalizedFormatDescriptionKey,
            ]) else { return nil }

            return VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                url: url,
                totalCapacity: UInt64(values.volumeTotalCapacity ?? 0),
                availableCapacity: UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0),
                fileSystemType: values.volumeLocalizedFormatDescription
            )
        }
    }
}
