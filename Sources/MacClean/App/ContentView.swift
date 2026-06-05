import SwiftUI
import MacCleanKit

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// Module views the user has visited at least once. Once a view is here it
    /// stays in the hierarchy (hidden via opacity, NOT destroyed) when the user
    /// switches tabs — so in-flight scans keep running and large result lists
    /// don't re-render on every switch (fixes the switch-back lag and the
    /// mid-scan "cancel"). Views are created lazily on first visit so we don't
    /// front-load every module's `.task` (app discovery, login items, …) at
    /// launch.
    @State private var visited: Set<SidebarItem> = []

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView(selection: $state.selectedSidebarItem)
                // The sidebar is the app's primary navigation and is always
                // shown, so the toolbar's collapse-sidebar button is just
                // dead weight (#21.4). Remove it.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack {
                if let item = appState.selectedSidebarItem {
                    GradientBackgroundView(theme: item.theme)
                        .ignoresSafeArea()
                }

                // Keep every visited module view alive across tab switches:
                // show the selected one, hide (don't tear down) the rest.
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    // Render if currently selected (so the first frame is never
                    // blank) or previously visited (kept alive in the background).
                    if visited.contains(item) || item == appState.selectedSidebarItem {
                        let isSelected = item == appState.selectedSidebarItem
                        moduleView(for: item)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                    }
                }

                if appState.selectedSidebarItem == nil {
                    Text("Select a module from the sidebar")
                        .foregroundStyle(.secondary)
                }

                // Centered title, drawn as plain content in the title bar
                // region. Not a ToolbarItem: macOS 26 wraps toolbar items in
                // a Liquid Glass capsule we don't want, and the unified
                // toolbar pins its own title to the leading edge (system
                // title hidden via TitleBarConfigurator; the window keeps
                // its real title for Mission Control/VoiceOver).
                VStack {
                    Text(MCConstants.appName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 16)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background(TitleBarConfigurator())
        // Title bar shows the app name only (centered); the version moved
        // to the sidebar footer next to the Settings button. The constant
        // is still checked against VERSION by CI (check-version-sync.sh).
        .navigationTitle(MCConstants.appName)
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
    }

    /// Hides the system-drawn window title once the view lands in a window.
    /// The title string itself stays set (Mission Control, App Exposé, and
    /// VoiceOver still read it); only the toolbar's leading-edge rendering
    /// is suppressed, replaced by the centered principal toolbar item above.
    private struct TitleBarConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { ConfiguringView() }

        // Re-assert on every SwiftUI update: navigationTitle changes make
        // AppKit re-show the system title (seen as a duplicated "Mac Sai"
        // next to the sidebar on macOS 26).
        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async { [weak nsView] in
                nsView?.window?.titleVisibility = .hidden
            }
        }

        private final class ConfiguringView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                DispatchQueue.main.async { [weak self] in
                    self?.window?.titleVisibility = .hidden
                }
            }
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
        case .settings:
            SettingsPageView()
        }
    }
}
