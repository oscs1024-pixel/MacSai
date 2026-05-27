import SwiftUI
import MacCleanKit

struct MailAttachmentsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var isDone = false
    @State private var freedSize: UInt64 = 0

    private let module = MailAttachmentsModule()

    var body: some View {
        ModuleContainerView(
            title: "Mail Attachments",
            subtitle: "Find cached email attachments from Mail, Outlook, and Spark",
            theme: .cleanup,
            emptyMessage: "No attachments found",
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

            scanPhase = "Scanning Apple Mail..."
            scanProgress = 0.2
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Scanning Outlook..."
            scanProgress = 0.45

            async let scanTask = module.scan()
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = "Scanning Spark..."
            scanProgress = 0.7

            results = await scanTask

            scanPhase = "Analyzing attachments..."
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
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
