import SwiftUI
import WatchdogCore

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedSection: SavedSection = .properties
    @State private var showCompare = false
    @State private var comparisonLimit = false
    @State private var clearSearches = false

    var body: some View {
        List {
            Section {
                Picker("Saved items", selection: $selectedSection) {
                    Text("Properties").tag(SavedSection.properties)
                    Text("Searches").tag(SavedSection.searches)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            if store.mode == .sample {
                Section {
                    RecordDataLabel(isSample: true).listRowBackground(WDTheme.surface)
                }
            }
            switch selectedSection {
            case .properties: propertiesSection
            case .searches: searchesSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WDTheme.canvas)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if !store.comparisonProperties.isEmpty {
                Button { showCompare = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.split.2x1")
                        Text("Compare \(store.comparisonProperties.count) \(store.comparisonProperties.count == 1 ? "property" : "properties")")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .padding(18)
                    .background(WDTheme.accent, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(WDTheme.canvas)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial)
                .accessibilityIdentifier("saved.compare")
            }
        }
        .sheet(isPresented: $showCompare) { CompareView() }
        .alert("Compare up to four properties", isPresented: $comparisonLimit) {
            Button("OK", role: .cancel) { }
        } message: { Text("Remove a selected property before adding another.") }
        .confirmationDialog("Clear all saved searches?", isPresented: $clearSearches, titleVisibility: .visible) {
            Button("Clear saved searches", role: .destructive) {
                for search in store.savedSearches { store.deleteSavedSearch(search) }
            }
        } message: { Text("This removes saved searches in the current data mode from this device.") }
    }

    @ViewBuilder private var propertiesSection: some View {
        Section {
            if store.savedProperties.isEmpty {
                VStack(spacing: 18) {
                    WDEmptyState(title: "Keep a place close", message: "Bookmark a property to return to its record, add notes, and compare it with other places.", symbol: "bookmark")
                    Button("Find a property") { store.selectedTab = .explore }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .listRowBackground(WDTheme.surface)
            } else {
                ForEach(store.savedProperties) { property in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { Task { await store.select(property) } } label: {
                            WDPropertyRow(property: property)
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Button {
                                toggleComparison(property)
                            } label: {
                                Label(store.comparisonIDs.contains(property.id) ? "In comparison" : "Compare",
                                      systemImage: store.comparisonIDs.contains(property.id) ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.subheadline.weight(.medium))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            if !(store.notes[property.id] ?? "").isEmpty {
                                Label("Note", systemImage: "note.text")
                                    .font(.caption).foregroundStyle(WDTheme.muted)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(WDTheme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Unsave", systemImage: "bookmark.slash", role: .destructive) { store.toggleSaved(property) }
                    }
                    .contextMenu {
                        Button("Open record", systemImage: "doc.text") { Task { await store.select(property) } }
                        Button(store.comparisonIDs.contains(property.id) ? "Remove from comparison" : "Add to comparison", systemImage: "square.split.2x1") { toggleComparison(property) }
                        ShareLink(item: DossierExport.text(for: property)) { Label("Share summary", systemImage: "square.and.arrow.up") }
                        Button("Remove from Saved", systemImage: "bookmark.slash", role: .destructive) { store.toggleSaved(property) }
                    }
                }
            }
        } header: {
            Text("\(store.savedProperties.count) \(store.savedProperties.count == 1 ? "property" : "properties")")
        } footer: {
            Text("Saved records and notes stay on this device. Export a library backup in Settings to keep a copy or move it to another device.")
        }
    }

    @ViewBuilder private var searchesSection: some View {
        Section {
            if store.savedSearches.isEmpty {
                VStack(spacing: 18) {
                    WDEmptyState(title: "A good search is worth keeping", message: "Save a search in Explore, then run it again here. Saved searches do not send notifications.", symbol: "magnifyingglass")
                    Button("Start searching") { store.selectedTab = .explore }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .listRowBackground(WDTheme.surface)
            } else {
                ForEach(store.savedSearches) { search in
                    Button { Task { await store.search(search.query) } } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass").foregroundStyle(WDTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(search.query).font(.headline).foregroundStyle(WDTheme.ink)
                                Text("Saved \(search.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(WDTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(WDTheme.muted)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(WDTheme.surface)
                    .accessibilityHint("Runs this search in Explore")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { store.deleteSavedSearch(search) }
                    }
                }
                Button("Clear saved searches", role: .destructive) { clearSearches = true }
                    .listRowBackground(WDTheme.surface)
            }
        } header: { Text("Run a search again") }
    }

    private func toggleComparison(_ property: PropertyRecord) {
        if store.comparisonIDs.count >= 4 && !store.comparisonIDs.contains(property.id) { comparisonLimit = true }
        else { store.toggleComparison(property) }
    }
}

private enum SavedSection { case properties, searches }
