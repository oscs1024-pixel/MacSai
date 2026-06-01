import SwiftUI
import MacCleanKit

@MainActor @Observable
final class SystemJunkViewModel {
    enum State {
        case idle
        case scanning(progress: Double)
        case results
        case empty
        case cleaning
        case done(summary: CleanSummary)
    }

    var state: State = .idle
    var results: [ScanResult] = []
    var selectedItems: Set<URL> = []
    var filesFound: Int = 0
    var scanPhase: String = "Scanning..."

    private let module = SystemJunkModule()

    var totalSelectedSize: UInt64 {
        let allItems = results.flatMap(\.items)
        return allItems
            .filter { selectedItems.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        selectedItems.count
    }

    var totalFileCount: Int {
        results.reduce(0) { $0 + $1.fileCount }
    }

    func startScan() {
        state = .scanning(progress: 0)
        filesFound = 0
        results = []
        selectedItems = []
        scanPhase = "Scanning caches..."

        Task {
            let scanStart = Date()

            state = .scanning(progress: 0.1)
            scanPhase = "Scanning user caches..."
            try? await Task.sleep(for: .milliseconds(300))

            scanPhase = "Scanning system logs..."
            state = .scanning(progress: 0.25)

            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = "Checking language files..."
            state = .scanning(progress: 0.4)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = "Inspecting preferences..."
            state = .scanning(progress: 0.55)

            try? await Task.sleep(for: .milliseconds(300))
            scanPhase = "Checking login items..."
            state = .scanning(progress: 0.7)

            let scanResults = await scanTask

            scanPhase = "Analyzing results..."
            state = .scanning(progress: 0.9)

            results = scanResults
            filesFound = scanResults.reduce(0) { $0 + $1.fileCount }

            for result in scanResults where result.autoSelect {
                for item in result.items {
                    selectedItems.insert(item.url)
                }
            }

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
            }

            state = .scanning(progress: 1.0)
            try? await Task.sleep(for: .milliseconds(300))
            state = scanResults.isEmpty ? .empty : .results
        }
    }

    func startCleaning(engine: CleaningEngine) {
        state = .cleaning
        let preCleanSelectedCount = selectedItems.count

        Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: engine
            )
            state = .done(summary: CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorCount: result.errors.count,
                firstErrorMessage: result.errors.first?.error
            ))
        }
    }

    func reset() {
        state = .idle
        results = []
        selectedItems = []
        filesFound = 0
    }
}
