import SwiftUI
import WatchdogCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showCompare = false
    private let columns = [GridItem(.adaptive(minimum: 145), alignment: .leading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                collection
                if let property = store.savedProperties.first {
                    VStack(alignment: .leading, spacing: 12) {
                        WDSectionHeader("Pick up where you left off", subtitle: "A property in your collection")
                        Button { Task { await store.select(property) } } label: {
                            WDPropertyRow(property: property)
                        }
                        .buttonStyle(.plain)
                    }
                }
                WDCard {
                    VStack(alignment: .leading, spacing: 10) {
                        WDSectionHeader("Make your next move")
                        FeatureActionRow(title: "Find a property", message: "Start with an address, town, or parcel.", symbol: "magnifyingglass") { store.selectedTab = .explore }
                        Divider()
                        FeatureActionRow(title: "Explore a town", message: "Compare the municipal context.", symbol: "map") { store.selectedTab = .atlas }
                        Divider()
                        FeatureActionRow(title: "See places side by side", message: compareMessage, symbol: "square.split.2x1") {
                            if store.comparisonProperties.isEmpty { store.selectedTab = .saved }
                            else { showCompare = true }
                        }
                    }
                }
                guide
            }
            .padding(20)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background(WDTheme.canvas)
        .navigationTitle("My Watchdog")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCompare) { CompareView() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("YOUR HOME, IN CONTEXT", systemImage: "house")
                    .font(.caption.weight(.semibold)).tracking(1.2)
                Spacer()
                Image(systemName: "sparkle").foregroundStyle(WDTheme.lime)
            }
            Text("A clearer view\nof home.")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("Understand the record. Explore the neighborhood. Keep the places that matter close.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button { store.selectedTab = .explore } label: {
                Label("Search a property", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 18)
                    .background(WDTheme.lime, in: Capsule())
                    .foregroundStyle(Color(red: 0.06, green: 0.20, blue: 0.16))
            }
            .buttonStyle(.plain)
            if store.mode == .sample {
                Label("Exploring with sample data", systemImage: "sparkles.rectangle.stack")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.06, green: 0.20, blue: 0.16), in: RoundedRectangle(cornerRadius: 28))
    }

    private var collection: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    WDSectionHeader("Your collection")
                    Spacer()
                    Button("View all") { store.selectedTab = .saved }.font(.subheadline.weight(.semibold))
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    WDMetric("Saved properties", value: String(store.savedProperties.count), detail: "Kept on this device")
                    WDMetric("Towns represented", value: String(Set(store.savedProperties.map { $0.town }.filter { !$0.isEmpty }).count))
                    WDMetric("Saved searches", value: String(store.savedSearches.count), detail: "Run again at any time")
                    WDMetric("Ready to compare", value: String(store.comparisonProperties.count), detail: "Up to four properties")
                }
                if store.savedProperties.isEmpty {
                    Text("Tap the bookmark on a property to start a collection of homes you own, love, or want to understand.")
                        .font(.subheadline).foregroundStyle(WDTheme.muted)
                }
            }
        }
    }

    private var compareMessage: String {
        store.comparisonProperties.isEmpty ? "Add properties to compare from their records." : "\(store.comparisonProperties.count) selected in your comparison."
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 14) {
            WDSectionHeader("Feel at home with the data", subtitle: "A few useful distinctions")
            WDCard {
                VStack(alignment: .leading, spacing: 18) {
                    HomeExplainer(title: "Assessment ≠ asking price", text: "An assessment is recorded for local taxation. A listing price is an asking price, and a sale price records a past transaction. They answer different questions.")
                    Divider()
                    HomeExplainer(title: "Every number has a date", text: "Tax year, assessment year, and sale date can differ. Open Sources on a property record to see what is available and where it came from.")
                    Divider()
                    HomeExplainer(title: "A town is more than an average", text: "Municipal ratios and reported assessments help you understand context. They do not predict the condition, selling price, or tax outcome of an individual home.")
                }
            }
        }
    }
}

private struct HomeExplainer: View {
    let title: String
    let text: String

    var body: some View {
        DisclosureGroup {
            Text(text).font(.subheadline).foregroundStyle(WDTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        } label: {
            Text(title).font(.headline).foregroundStyle(WDTheme.ink)
                .frame(minHeight: 32, alignment: .leading)
        }
    }
}

// The tab identifier remains stable for existing on-device navigation state.
struct WorkspaceView: View {
    var body: some View { HomeView() }
}
