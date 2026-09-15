import SwiftUI
import UIKit
import WatchdogCore

@MainActor
struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AppStorage("watchdog.recentSearches") private var recentSearchData = Data()
    @State private var showingFilters = false
    @State private var showingMap = true
    @FocusState private var searchFocused: Bool
    @State private var nearbyLocation = NearbyLocation()
    @State private var mapFocus: SearchLocation?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 800 && !dynamicTypeSize.isAccessibilitySize
            Group {
                if wide {
                    HStack(spacing: 0) {
                        sidebar(wide: true)
                            .frame(width: min(420, geometry.size.width * 0.40))
                        Divider().overlay(WDTheme.line)
                        propertyMap
                    }
                } else {
                    phoneLayout(height: geometry.size.height)
                }
            }
            .background(WDTheme.canvas)
        }
        .sheet(isPresented: $showingFilters) {
            PropertyFilterView(filters: store.filters) { store.filters = $0 }
        }
        .alert("Location search", isPresented: Binding(
            get: { nearbyLocation.errorMessage != nil },
            set: { if !$0 { nearbyLocation.errorMessage = nil } }
        )) {
            if nearbyLocation.shouldOfferSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("OK", role: .cancel) { nearbyLocation.errorMessage = nil }
        } message: { Text(nearbyLocation.errorMessage ?? "") }
        .onChange(of: nearbyLocation.location) { _, location in
            guard let location else { return }
            searchFocused = false
            showingMap = true
            mapFocus = location
            Task { await store.searchNearby(latitude: location.latitude, longitude: location.longitude) }
        }
        .onChange(of: store.query) { _, _ in
            if !store.isAreaSearch {
                nearbyLocation.cancel(clearLocation: true)
                mapFocus = nil
            }
        }
        .onChange(of: store.mode) { _, _ in
            nearbyLocation.cancel(clearLocation: true)
            mapFocus = nil
        }
        .onDisappear { nearbyLocation.cancel() }
        .task(id: store.query) {
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await store.searchIfNeeded()
        }
    }

    private func sidebar(wide: Bool) -> some View {
        VStack(spacing: 0) {
            searchHeader(wide: wide)
            Divider().overlay(WDTheme.line)
            resultsPanel
        }
    }

    private func phoneLayout(height: CGFloat) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    searchHeader(wide: false)
                    if showingMap && !searchFocused {
                        propertyMap
                            .frame(height: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    resultsStack
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.retrySearch() }
            } else {
                VStack(spacing: 0) {
                    searchHeader(wide: false)
                    if showingMap && !searchFocused {
                        propertyMap
                            .frame(height: min(290, max(175, height * 0.35)))
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    resultsPanel
                }
            }
        }
    }

    private func searchHeader(wide: Bool) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Find your place.")
                        .font(.system(wide ? .largeTitle : .title, design: .serif, weight: .medium))
                        .foregroundStyle(WDTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if wide {
                        Text("A clearer picture of every property.")
                            .font(.subheadline).foregroundStyle(WDTheme.muted)
                    }
                }
                Spacer(minLength: 0)
                if !wide {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showingMap.toggle() }
                        searchFocused = false
                    } label: {
                        Image(systemName: showingMap ? "list.bullet" : "map")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WDTheme.ink)
                            .frame(width: 46, height: 46)
                            .background(WDTheme.surface, in: Circle())
                            .overlay(Circle().stroke(WDTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingMap ? "Show full results list" : "Show map and results")
                    .accessibilityIdentifier("explorer.toggleMap")
                }
            }
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").foregroundStyle(WDTheme.accent).accessibilityHidden(true)
                TextField("Address, town, or block + lot", text: $store.query)
                    .font(.body)
                    .foregroundStyle(WDTheme.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { submitQuery() }
                    .accessibilityLabel("Search New Jersey property records")
                    .accessibilityHint("Enter an address, municipality, or block and lot")
                    .accessibilityIdentifier("explorer.searchField")
                if !store.query.isEmpty {
                    Button { store.query = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(WDTheme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("explorer.clearSearch")
                }
            }
            .padding(.leading, 16).padding(.trailing, store.query.isEmpty ? 16 : 4)
            .frame(minHeight: 56)
            .background(WDTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(searchFocused ? WDTheme.accent : WDTheme.line, lineWidth: searchFocused ? 1.5 : 1))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { dataStatus; Spacer(minLength: 0); nearMeButton }
                VStack(alignment: .leading, spacing: 2) { dataStatus; nearMeButton }
            }
        }
        .padding(wide ? 24 : 18)
    }

    private var dataStatus: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: store.mode == .sample ? "flask.fill" : "checkmark.seal")
            Text(store.mode == .sample ? "Sample data · Explore the experience" : "New Jersey public property records")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(WDTheme.muted)
        .accessibilityElement(children: .combine)
    }

    private var nearMeButton: some View {
        Button { nearbyLocation.request() } label: {
            HStack(spacing: 5) {
                if nearbyLocation.isRequesting { ProgressView().controlSize(.small) }
                else { Image(systemName: "location") }
                Text("Near me")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(WDTheme.accent)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(nearbyLocation.isRequesting || store.isLoading)
        .accessibilityLabel("Search properties near my location")
        .accessibilityIdentifier("explorer.nearMe")
    }

    private var propertyMap: some View {
        ExploreMap(properties: store.filteredResults,
                   contextID: "\(store.mode.rawValue):\(store.query)",
                   isLoading: store.isLoading,
                   isSample: store.mode == .sample,
                   focus: mapFocus,
                   open: openProperty,
                   searchArea: { coordinate in
                       searchFocused = false
                       nearbyLocation.cancel(clearLocation: true)
                       mapFocus = SearchLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                       Task { await store.searchNearby(latitude: coordinate.latitude, longitude: coordinate.longitude) }
                   })
    }

    private var resultsPanel: some View {
        ScrollView { resultsStack }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.retrySearch() }
    }

    private var resultsStack: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
                if searchFocused { searchSuggestions }
                resultsToolbar
                resultContent
                if !store.filteredResults.isEmpty && store.errorMessage == nil {
                    WDSourceLabel("Public records are not active sale listings. Values and coverage depend on the source and year.")
                        .padding(.horizontal, 3)
                }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var resultsToolbar: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    countLabel
                    Spacer(minLength: 4)
                    resultActions
                }
                VStack(alignment: .leading, spacing: 4) { countLabel; resultActions }
            }
            if store.filters.isActive {
                Button("Clear active filters") { store.filters = PropertyFilters() }
                    .font(.caption.weight(.semibold)).foregroundStyle(WDTheme.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
            if store.isAreaSearch {
                Text("Records within 1.5 km of the searched map center")
                    .font(.caption).foregroundStyle(WDTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var countLabel: some View {
        HStack(spacing: 7) {
            if store.isLoading { ProgressView().controlSize(.small) }
            Text(store.isLoading ? "Searching records" : "\(store.filteredResults.count) records")
                .font(.headline).foregroundStyle(WDTheme.ink)
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("explorer.resultCount")
    }

    private var resultActions: some View {
        @Bindable var store = store
        return HStack(spacing: 5) {
            Menu {
                Picker("Sort records", selection: $store.sort) {
                    ForEach(PropertySort.allCases) { sort in Text(sort.title).tag(sort) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Sort records: \(store.sort.title)")
            .accessibilityIdentifier("explorer.sort")
            Button { showingFilters = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Filters").font(.subheadline.weight(.medium))
                    if store.filters.isActive {
                        Circle().fill(WDTheme.accent).frame(width: 6, height: 6)
                    }
                }
                .frame(minHeight: 44).padding(.horizontal, 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.filters.isActive ? "Filters, active" : "Filters")
            .accessibilityIdentifier("explorer.filters")
            if !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { store.saveSearch(); rememberQuery(store.query) } label: {
                    Image(systemName: isQuerySaved ? "bookmark.fill" : "bookmark")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isQuerySaved ? "Search saved" : "Save this search")
                .accessibilityIdentifier("explorer.saveSearch")
                .disabled(isQuerySaved)
            }
        }
        .foregroundStyle(WDTheme.accent)
    }

    @ViewBuilder private var resultContent: some View {
        if let error = store.errorMessage {
            WDCard {
                WDEmptyState(title: "Records couldn’t load", message: error, symbol: "wifi.exclamationmark")
                WDPrimaryButton("Try again", symbol: "arrow.clockwise") { Task { await store.retrySearch() } }
                    .accessibilityIdentifier("explorer.retrySearch")
            }
        } else if store.isLoading && store.results.isEmpty {
            ForEach(0..<3) { _ in RecordSkeleton() }
        } else if store.filteredResults.isEmpty && !store.isLoading {
            WDEmptyState(title: store.filters.isActive ? "Give your search more room" : "Let’s find a property",
                         message: store.filters.isActive
                            ? "No returned records match these filters. Broaden the assessment range or remove a filter."
                            : "Try a street address or municipality. You can also move the map and search near its center.",
                         symbol: "magnifyingglass")
            if store.filters.isActive {
                WDPrimaryButton("Clear filters", symbol: "slider.horizontal.3") { store.filters = PropertyFilters() }
            } else { starterSearches }
        } else {
            ForEach(store.filteredResults) { property in
                Button { openProperty(property) } label: { WDPropertyRow(property: property) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens assessment, tax, sales history, and sources")
                    .accessibilityIdentifier("explorer.record.\(property.id)")
                    .contextMenu {
                        Button(store.isSaved(property) ? "Remove from saved" : "Save property",
                               systemImage: store.isSaved(property) ? "bookmark.slash" : "bookmark") {
                            store.toggleSaved(property)
                        }
                        Button(store.comparisonIDs.contains(property.id) ? "Remove from comparison" : "Add to comparison",
                               systemImage: "square.on.square") { store.toggleComparison(property) }
                            .disabled(!store.comparisonIDs.contains(property.id) && store.comparisonIDs.count >= 4)
                    }
            }
        }
    }

    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 9) {
            if store.query.isEmpty {
                if !store.savedSearches.isEmpty {
                    suggestionHeading("Saved searches")
                    ForEach(Array(store.savedSearches.prefix(4))) { search in
                        suggestion(search.query, symbol: "bookmark") { chooseQuery(search.query) }
                    }
                }
                if !recentQueries.isEmpty {
                    HStack {
                        suggestionHeading("Recent searches")
                        Spacer()
                        Button("Clear") { recentSearchData = Data() }
                            .font(.caption).foregroundStyle(WDTheme.accent).frame(minWidth: 44, minHeight: 44)
                    }
                    ForEach(Array(recentQueries.prefix(4)), id: \.self) { query in
                        suggestion(query, symbol: "clock") { chooseQuery(query) }
                    }
                }
                starterSearches
                Text("Parcel search: block 12 lot 3, Haddonfield")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            } else if !store.isLoading && store.errorMessage == nil {
                let completions = Array(store.results.prefix(4))
                if !completions.isEmpty {
                    suggestionHeading("Matching records")
                    ForEach(completions) { property in
                        suggestion("\(property.displayAddress), \(property.town)", symbol: "mappin") {
                            openProperty(property)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 5)
    }

    private var starterSearches: some View {
        VStack(alignment: .leading, spacing: 4) {
            suggestionHeading("Explore New Jersey")
            ForEach(["Haddonfield", "Cherry Hill", "Princeton"], id: \.self) { town in
                suggestion(town, symbol: "building.2") { chooseQuery(town) }
            }
        }
    }

    private func suggestionHeading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(WDTheme.muted)
            .textCase(.uppercase).tracking(0.5).accessibilityAddTraits(.isHeader)
    }

    private func suggestion(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(WDTheme.accent)
                Text(title).multilineTextAlignment(.leading).foregroundStyle(WDTheme.ink)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(WDTheme.muted)
            }
            .font(.subheadline).padding(.vertical, 10).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isQuerySaved: Bool {
        store.savedSearches.contains { $0.query.caseInsensitiveCompare(store.query.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    private var recentQueries: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchData)) ?? []
    }

    private func rememberQuery(_ query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var recent = recentQueries.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        recent.insert(clean, at: 0)
        recentSearchData = (try? JSONEncoder().encode(Array(recent.prefix(8)))) ?? Data()
    }

    private func submitQuery() {
        rememberQuery(store.query)
        searchFocused = false
    }

    private func chooseQuery(_ value: String) {
        store.query = value
        submitQuery()
    }

    private func openProperty(_ property: PropertyRecord) {
        rememberQuery(store.query)
        searchFocused = false
        Task { await store.select(property) }
    }
}

private struct RecordSkeleton: View {
    var body: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 15) {
                RoundedRectangle(cornerRadius: 5).frame(width: 190, height: 17)
                RoundedRectangle(cornerRadius: 4).frame(width: 130, height: 12)
                HStack(spacing: 28) {
                    RoundedRectangle(cornerRadius: 6).frame(height: 37)
                    RoundedRectangle(cornerRadius: 6).frame(height: 37)
                }
            }
            .foregroundStyle(WDTheme.line.opacity(0.65))
        }
        .accessibilityHidden(true)
    }
}
