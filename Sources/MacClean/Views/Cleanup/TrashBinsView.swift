import SwiftUI
import MacCleanKit

struct TrashBinsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanComplete = false
    @State private var isDone = false
    @State private var freedSize: UInt64 = 0

    private let module = TrashBinsModule()

    var body: some View {
        ModuleContainerView(
            title: "Trash Bins",
            subtitle: "Empty all trash locations including external drives",
            theme: .cleanup,
            emptyMessage: "Trash is empty",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            isDone: isDone,
            freedSize: freedSize,
            onScan: scan,
            onClean: clean,
            onReset: reset
        )
    }

    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        Task {
            let scanStart = Date()

            scanPhase = "Scanning user Trash..."
            scanProgress = 0.3
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Checking external drives..."
            scanProgress = 0.6

            async let scanTask = module.scan()
            results = await scanTask

            scanPhase = "Calculating sizes..."
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 1.5 {
                try? await Task.sleep(for: .milliseconds(Int((1.5 - elapsed) * 1000)))
            }
            scanProgress = 1.0

            for r in results where r.autoSelect {
                selectedItems.formUnion(r.items.map(\.url))
            }
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let items = results.flatMap(\.items).filter { selectedItems.contains($0.url) }
        Task {
            let result = await appState.cleaningEngine.clean(items: items, mode: .dryRun)
            freedSize = result.freedBytes
            isDone = true
        }
    }

    private func reset() {
        results = []; selectedItems = []; isDone = false; freedSize = 0; scanComplete = false
    }
}
