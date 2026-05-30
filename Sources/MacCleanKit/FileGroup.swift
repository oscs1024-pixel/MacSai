import Foundation

/// Groups a list of `FileItem` values for display. Pure logic.
public enum FileGroup: Sendable {
    case byType
    case bySize
    case byAge

    public func group(_ items: [FileItem], now: Date = Date()) -> [(String, [FileItem])] {
        switch self {
        case .byType: Self.groupByType(items)
        case .bySize: Self.groupBySize(items)
        case .byAge: Self.groupByAge(items, now: now)
        }
    }

    static func groupByType(_ items: [FileItem]) -> [(String, [FileItem])] {
        var groups: [String: [FileItem]] = [:]
        for item in items {
            let type = fileTypeLabel(item.fileExtension)
            groups[type, default: []].append(item)
        }
        return groups.sorted { $0.key < $1.key }
    }

    static func groupBySize(_ items: [FileItem]) -> [(String, [FileItem])] {
        var groups: [String: [FileItem]] = [
            "1 GB+": [],
            "500 MB - 1 GB": [],
            "100 - 500 MB": [],
            "50 - 100 MB": [],
        ]
        for item in items {
            let mb = item.size / (1024 * 1024)
            if mb >= 1024 {
                groups["1 GB+", default: []].append(item)
            } else if mb >= 500 {
                groups["500 MB - 1 GB", default: []].append(item)
            } else if mb >= 100 {
                groups["100 - 500 MB", default: []].append(item)
            } else {
                groups["50 - 100 MB", default: []].append(item)
            }
        }
        return groups.filter { !$0.value.isEmpty }.sorted { $0.key > $1.key }
    }

    static func groupByAge(_ items: [FileItem], now: Date) -> [(String, [FileItem])] {
        var groups: [String: [FileItem]] = [:]
        for item in items {
            guard let modDate = item.modificationDate else { continue }
            let days = Int(now.timeIntervalSince(modDate) / (24 * 3600))
            let label = ageLabel(days: days)
            groups[label, default: []].append(item)
        }
        return groups.sorted { $0.key > $1.key }
    }

    public static func ageLabel(days: Int) -> String {
        if days > 365 { return "Over 1 year" }
        if days > 180 { return "6 months - 1 year" }
        if days > 90 { return "3 - 6 months" }
        if days > 30 { return "1 - 3 months" }
        return "Last month"
    }

    public static func fileTypeLabel(_ ext: String) -> String {
        switch ext {
        case "mp4", "mov", "avi", "mkv", "wmv", "flv": "Videos"
        case "mp3", "wav", "flac", "aac", "m4a", "ogg": "Audio"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "raw": "Images"
        case "pdf": "PDFs"
        case "doc", "docx", "pages", "rtf", "txt": "Documents"
        case "xls", "xlsx", "numbers", "csv": "Spreadsheets"
        case "zip", "gz", "tar", "rar", "7z", "bz2": "Archives"
        case "dmg", "iso", "img": "Disk Images"
        case "app": "Applications"
        case "pkg", "mpkg": "Installers"
        default: "Other"
        }
    }
}
