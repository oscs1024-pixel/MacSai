import SwiftUI
import MacCleanKit

struct PrivacyView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var isDone = false
    @State private var freedSize: UInt64 = 0
    @State private var timeFilter: PrivacyModule.TimeFilter = .allTime

    var body: some View {
        ModuleContainerView(
            title: "Privacy",
            subtitle: "Clean browser data, history, cookies, and system traces",
            theme: .protection,
            emptyMessage: "No privacy traces found",
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

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        Task {
            let scanStart = Date()

            scanPhase = "Scanning Safari data..."
            scanProgress = 0.15
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Scanning Chrome data..."
            scanProgress = 0.35

            let module = PrivacyModule(timeFilter: timeFilter)
            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = "Scanning Firefox data..."
            scanProgress = 0.55

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = "Checking system traces..."
            scanProgress = 0.75

            results = await scanTask

            scanPhase = "Analyzing results..."
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
            }
            scanProgress = 1.0

            for r in results { selectedItems.formUnion(r.items.map(\.url)) }
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
