import SwiftUI
import MacCleanKit

struct ModuleContainerView: View {
    let title: String
    let subtitle: String
    let theme: ModuleTheme
    let emptyMessage: String
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    let isScanning: Bool
    let scanProgress: Double
    let scanPhase: String
    let scanComplete: Bool
    let isDone: Bool
    let freedSize: UInt64
    let onScan: () -> Void
    let onClean: () -> Void
    let onReset: () -> Void

    init(
        title: String,
        subtitle: String,
        theme: ModuleTheme,
        emptyMessage: String = "No items found",
        results: [ScanResult],
        selectedItems: Binding<Set<URL>>,
        isScanning: Bool,
        scanProgress: Double = 0.5,
        scanPhase: String = "Scanning...",
        scanComplete: Bool = false,
        isDone: Bool,
        freedSize: UInt64,
        onScan: @escaping () -> Void,
        onClean: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.emptyMessage = emptyMessage
        self.results = results
        self._selectedItems = selectedItems
        self.isScanning = isScanning
        self.scanProgress = scanProgress
        self.scanPhase = scanPhase
        self.scanComplete = scanComplete
        self.isDone = isDone
        self.freedSize = freedSize
        self.onScan = onScan
        self.onClean = onClean
        self.onReset = onReset
    }

    private var totalSelected: UInt64 {
        results.flatMap(\.items)
            .filter { selectedItems.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        Group {
            if isDone {
                doneView
            } else if !results.isEmpty {
                resultsView
            } else if isScanning {
                scanningView
            } else if scanComplete {
                emptyResultsView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            ScanButton(title: "Scan", subtitle: title, theme: theme, action: onScan)
            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 0) {
            Spacer()
            ScanProgressRing(progress: scanProgress, phase: scanPhase, theme: theme)
            Spacer()
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.9))
            Text(emptyMessage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Scan complete — nothing to clean up")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Button("Done") { onReset() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack {
                SizeDisplay(size: totalSelected, label: "selected")
                    .foregroundStyle(.white)
                Spacer()
                Button("Clean") { onClean() }
                    .buttonStyle(SuperEllipseButtonStyle(
                        gradient: theme.buttonGradient,
                        size: CGSize(width: 110, height: 40)
                    ))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            FileListView(results: results, selectedItems: $selectedItems)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
            SizeDisplay(size: freedSize, label: "cleaned up")
                .foregroundStyle(.white)
            Button("Done") { onReset() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
            Spacer()
        }
    }
}
