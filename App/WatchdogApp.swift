import SwiftUI
import WatchdogCore

@main struct WatchdogApp: App {
    @State private var store: AppStore
    private let appPreferences: UserDefaults

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--sample-data") {
            let defaults = UserDefaults(suiteName: "com.watchdogindex.consumer.uitests")!
            appPreferences = defaults
            if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                defaults.removePersistentDomain(forName: "com.watchdogindex.consumer.uitests")
            }
            defaults.set("sample", forKey: "dataMode")
            defaults.set(true, forKey: "onboardingComplete")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("watchdog-ui-test-library.json")
            let newStore = AppStore(preferences: defaults, libraryURL: url)
            if ProcessInfo.processInfo.arguments.contains("--reset-library") { newStore.clearLocalData() }
            _store = State(initialValue: newStore)
        } else {
            appPreferences = .standard
            _store = State(initialValue: AppStore())
        }
        #else
        appPreferences = .standard
        _store = State(initialValue: AppStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchdogRootView()
                .environment(store)
                .defaultAppStorage(appPreferences)
                .preferredColorScheme(store.preferredColorScheme)
                .tint(WDTheme.accent)
        }
    }
}

struct WatchdogRootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingSettings = false
    @State private var showingComparison = false

    var body: some View {
        @Bindable var store = store
        Group {
            if sizeClass == .regular { tabletNavigation }
            else { phoneNavigation }
        }
        .background(WDTheme.canvas)
        .sheet(item: $store.selectedProperty) { property in
            NavigationStack {
                PropertyDetailView(property: store.selectedProperty ?? property)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.isLoadingDetail {
                            HStack(spacing: 8) { ProgressView(); Text("Refreshing public records…").font(.caption) }
                                .frame(maxWidth: .infinity).padding(10).background(WDTheme.surface)
                        } else if let error = store.detailError {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(error).font(.caption)
                                Button("Retry refresh") { Task { await store.refreshSelected() } }
                                    .font(.caption.weight(.semibold)).frame(minHeight: 36)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(WDTheme.canvas)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { store.selectedProperty = nil }.accessibilityIdentifier("dossier.done")
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingComparison) { CompareView() }
        .fullScreenCover(isPresented: Binding(
            get: { !store.hasCompletedOnboarding },
            set: { if !$0 { store.completeOnboarding() } }
        )) { WelcomeView() }
        .onOpenURL { url in
            // Search links are public text only. No arbitrary redirect or credential handling.
            guard url.scheme == "watchdog", url.host == "search",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let query = components.queryItems?.first(where: { $0.name == "q" })?.value,
                  !query.isEmpty, query.count <= 200 else { return }
            Task { await store.search(query) }
        }
    }

    private var phoneNavigation: some View {
        @Bindable var store = store
        return TabView(selection: $store.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    destination(tab)
                        .navigationTitle("Watchdog")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { globalToolbar }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
    }

    private var tabletNavigation: some View {
        NavigationSplitView {
            GeometryReader { geometry in
                ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    WatchdogEmblem().fill(WDTheme.accent, style: FillStyle(eoFill: true)).frame(width: 38, height: 38)
                    Text("Watchdog").font(.title2.bold())
                }.padding(.top, 22)
                VStack(spacing: 6) {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            store.selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .font(.body.weight(store.selectedTab == tab ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 14)
                                .background(store.selectedTab == tab ? WDTheme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little more clarity.\nA lot more confidence.")
                        .font(.system(.title3, design: .serif)).foregroundStyle(WDTheme.ink)
                    Text("New Jersey property research").font(.caption).foregroundStyle(WDTheme.muted)
                }
                Button { showingSettings = true } label: {
                    Label("Settings & your library", systemImage: "gearshape").frame(minHeight: 44)
                }.font(.subheadline)
            }
            .padding(20).frame(minHeight: geometry.size.height)
                }
                .background(WDTheme.canvas)
            }
            .navigationSplitViewColumnWidth(min: 215, ideal: 245, max: 285)
        } detail: {
            NavigationStack {
                destination(store.selectedTab)
                    .navigationTitle(store.selectedTab == .explore ? "Watchdog" : store.selectedTab.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { globalToolbar }
            }
        }
    }

    @ViewBuilder private func destination(_ tab: AppTab) -> some View {
        switch tab {
        case .explore: ExploreView()
        case .workspace: WorkspaceView()
        case .saved: SavedView()
        case .atlas: AtlasView()
        }
    }

    @ToolbarContentBuilder private var globalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !store.comparisonIDs.isEmpty {
                Button { showingComparison = true } label: {
                    Label("Compare \(store.comparisonIDs.count)", systemImage: "rectangle.on.rectangle")
                }.accessibilityIdentifier("global.compare")
            }
            Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Settings").accessibilityIdentifier("global.settings")
        }
    }
}
