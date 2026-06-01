import SwiftUI
import MacCleanKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @State private var launcher = MenuBarLauncher.shared
    @State private var refreshTick = 0

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSidebarItem)
        } detail: {
            ZStack {
                if let item = appState.selectedSidebarItem {
                    GradientBackgroundView(theme: item.theme)
                        .ignoresSafeArea()
                    moduleView(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select a module from the sidebar")
                        .foregroundStyle(.secondary)
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationTitle("Mac Clean")
        // Native macOS pattern: small grey second line under the title.
        // MCConstants.appVersion is checked against VERSION by CI
        // (scripts/check-version-sync.sh) — drifting between the two
        // fails the build.
        .navigationSubtitle("v\(MCConstants.appVersion)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                menuBarToggle
            }
        }
        .id(refreshTick)
    }

    private var menuBarToggle: some View {
        Toggle(isOn: $showMenuBarWidget) {
            Label("Menu Bar", systemImage: showMenuBarWidget
                  ? "menubar.dock.rectangle.badge.record"
                  : "menubar.dock.rectangle")
        }
        .toggleStyle(.button)
        .help(showMenuBarWidget
              ? "Menu bar widget is on — click to hide it"
              : "Menu bar widget is off — click to show it")
        .onChange(of: showMenuBarWidget) { _, newValue in
            launcher.setEnabled(newValue)
            refreshTick &+= 1
        }
    }

    @ViewBuilder
    private func moduleView(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan:
            SmartScanView()
        case .systemJunk:
            SystemJunkView()
        case .mailAttachments:
            MailAttachmentsView()
        case .trashBins:
            TrashBinsView()
        case .malwareRemoval:
            MalwareView()
        case .privacy:
            PrivacyView()
        case .optimization:
            OptimizationView()
        case .maintenance:
            MaintenanceView()
        case .uninstaller:
            UninstallerView()
        case .updater:
            UpdaterView()
        case .spaceLens:
            SpaceLensView()
        case .largeOldFiles:
            LargeOldFilesView()
        case .duplicates:
            DuplicatesView()
        case .shredder:
            ShredderView()
        }
    }
}
