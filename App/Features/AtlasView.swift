import SwiftUI
import Charts
import WatchdogCore

struct AtlasView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var county = "All counties"
    @State private var sort: TownSort = .name
    @State private var selectedIDs = Set<String>()
    @State private var showComparison = false
    @State private var selectionLimit = false

    private var selectedTowns: [Municipality] {
        store.municipalities.filter { selectedIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var counties: [String] {
        Array(Set(store.municipalities.map(\.county))).filter { !$0.isEmpty }.sorted()
    }

    private var visibleTowns: [Municipality] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = store.municipalities.filter { town in
            (county == "All counties" || town.county == county) &&
            (text.isEmpty || town.name.localizedCaseInsensitiveContains(text) || town.county.localizedCaseInsensitiveContains(text))
        }
        return matches.sorted { lhs, rhs in
            if sort == .ratio, lhs.ratio != rhs.ratio {
                return (lhs.ratio ?? .infinity) < (rhs.ratio ?? .infinity)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                introduction
                if store.mode == .sample { RecordDataLabel(isSample: true) }
                if let error = store.municipalityError { errorCard(error) }
                if store.isLoadingMunicipalities && store.municipalities.isEmpty {
                    ProgressView("Finding the municipal context…")
                        .frame(maxWidth: .infinity).padding(.vertical, 64)
                } else if store.municipalities.isEmpty && store.municipalityError == nil {
                    WDCard {
                        WDEmptyState(title: "No towns returned", message: "The municipal directory did not return records. Pull down to try again.", symbol: "building.2")
                    }
                } else if !store.municipalities.isEmpty {
                    controls
                    if visibleTowns.isEmpty {
                        WDCard {
                            VStack(spacing: 12) {
                                WDEmptyState(title: "Try a different town", message: "No towns match this name and county. Clear the filters to see the directory.", symbol: "magnifyingglass")
                                Button("Clear filters") { query = ""; county = "All counties" }
                                    .buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                    } else {
                        Text("\(visibleTowns.count) \(visibleTowns.count == 1 ? "municipality" : "municipalities") · select up to four")
                            .font(.caption).foregroundStyle(WDTheme.muted)
                        ForEach(visibleTowns) { town in
                            TownDirectoryCard(town: town, selected: selectedIDs.contains(town.id),
                                              select: { toggle(town) },
                                              search: { Task { await store.search(town.name) } })
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background(WDTheme.canvas)
        .navigationTitle("Towns")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search a town or county")
        .safeAreaInset(edge: .bottom) { selectionBar }
        .refreshable { await store.loadMunicipalities() }
        .task(id: store.mode) {
            selectedIDs.removeAll()
            county = "All counties"
            await store.loadMunicipalities()
        }
        .sheet(isPresented: $showComparison) {
            TownComparisonView(towns: selectedTowns) { town in
                showComparison = false
                Task { await store.search(town.name) }
            }
        }
        .alert("Compare up to four towns", isPresented: $selectionLimit) {
            Button("OK", role: .cancel) { }
        } message: { Text("Deselect a town before adding another to the comparison.") }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("NEW JERSEY, IN PERSPECTIVE", systemImage: "building.2")
                .font(.caption.weight(.semibold)).tracking(1)
                .foregroundStyle(WDTheme.accent)
            Text("Get to know\nthe bigger picture.")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .foregroundStyle(WDTheme.ink)
            Text("Explore municipal assessment ratios, follow the sources, and put your property research in context.")
                .font(.subheadline).foregroundStyle(WDTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("What does a municipal ratio tell me?") {
                Text("The certified ratio describes the municipality’s assessment level relative to true value for the published year. It is not a property-tax rate, a ranking of towns, or an estimate of what an individual home will sell for. A lower ratio alone does not mean lower taxes.")
                    .font(.subheadline).foregroundStyle(WDTheme.muted)
                    .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.medium))
            .padding(18)
            .background(WDTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .padding(.bottom, 6)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { countyPicker; Spacer(); sortPicker }
            VStack(alignment: .leading, spacing: 8) { countyPicker; sortPicker }
        }
    }

    private var countyPicker: some View {
        Menu {
            Picker("County", selection: $county) {
                Text("All counties").tag("All counties")
                ForEach(counties, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Label(county, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }
    }

    private var sortPicker: some View {
        Menu {
            Picker("Sort towns", selection: $sort) {
                ForEach(TownSort.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }
    }

    @ViewBuilder private var selectionBar: some View {
        if !selectedTowns.isEmpty {
            VStack(spacing: 10) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(selectedTowns) { town in
                            Button { selectedIDs.remove(town.id) } label: {
                                Label(town.name, systemImage: "xmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(WDTheme.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(town.name) from town comparison")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 18) {
                    Button("Clear") { selectedIDs.removeAll() }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    WDPrimaryButton("Compare \(selectedTowns.count) \(selectedTowns.count == 1 ? "town" : "towns")", symbol: "square.split.2x1") {
                        showComparison = true
                    }
                    .accessibilityIdentifier("towns.compare")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func errorCard(_ error: String) -> some View {
        WDCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Towns couldn’t refresh", systemImage: "wifi.exclamationmark").font(.headline)
                Text(error).font(.subheadline).foregroundStyle(WDTheme.muted)
                if !store.municipalities.isEmpty {
                    Text("Previously loaded records are shown below.").font(.caption).foregroundStyle(WDTheme.muted)
                }
                Button("Try again") { Task { await store.loadMunicipalities() } }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(store.isLoadingMunicipalities)
            }
        }
    }

    private func toggle(_ town: Municipality) {
        if selectedIDs.contains(town.id) { selectedIDs.remove(town.id) }
        else if selectedIDs.count < 4 { selectedIDs.insert(town.id) }
        else { selectionLimit = true }
    }
}

private enum TownSort: String, CaseIterable, Identifiable {
    case name = "Town name"
    case ratio = "Ratio: low to high"
    var id: String { rawValue }
}

private struct TownDirectoryCard: View {
    let town: Municipality
    let selected: Bool
    let select: () -> Void
    let search: () -> Void

    var body: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(town.name).font(.system(.title2, design: .serif, weight: .medium))
                                .foregroundStyle(WDTheme.ink)
                            Text(town.county + " County").font(.subheadline).foregroundStyle(WDTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2).foregroundStyle(WDTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(town.name), \(town.county) County")
                .accessibilityValue(selected ? "Selected for comparison" : "Not selected")
                .accessibilityHint("Double tap to \(selected ? "remove from" : "add to") town comparison")
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    WDMetric("Certified ratio", value: WDTheme.percent(town.ratio), detail: "Published year: \(RecordFormat.year(town.year))")
                    if town.isSample { Label("Sample", systemImage: "flask").font(.caption).foregroundStyle(WDTheme.muted) }
                }
                HStack(spacing: 18) {
                    Button(action: search) {
                        Label("Find properties", systemImage: "magnifyingglass").frame(minHeight: 44)
                    }
                    if let source = town.sources.first(where: { $0.id == "chapter123" }), let url = RecordFormat.webURL(source.url) {
                        Link(destination: url) {
                            Label("Source", systemImage: "arrow.up.right.square").frame(minHeight: 44)
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(selected ? WDTheme.accent : .clear, lineWidth: 2))
    }
}

private struct TownComparisonView: View {
    let towns: [Municipality]
    let search: (Municipality) -> Void
    @Environment(\.dismiss) private var dismiss

    private var reportedRatios: [Municipality] {
        towns.filter { town in
            guard let ratio = town.ratio else { return false }
            return ratio.isFinite && ratio > 0
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Every town has\nits own context.")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .foregroundStyle(WDTheme.ink)
                    if towns.contains(where: \.isSample) { RecordDataLabel(isSample: true) }
                    if towns.count == 1 {
                        Text("Select another town in the directory to compare the reported ratios.")
                            .font(.subheadline).foregroundStyle(WDTheme.muted)
                    }
                    if !reportedRatios.isEmpty { ratioChart }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(towns) { town in
                                TownComparisonCard(town: town) { search(town) }.frame(width: 290)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollClipDisabled()
                    WDCard {
                        VStack(alignment: .leading, spacing: 12) {
                            WDSectionHeader("Context, without a ranking")
                            Text("Municipal ratios describe assessment levels for their published years. They do not describe the amount of tax a homeowner pays or rank a town’s quality. Compare matching years and open the sources before applying a figure to an individual property.")
                            Text("A dash means the source did not report that metric. Only available data is shown; figures are never filled in from another town.")
                        }
                        .font(.subheadline).foregroundStyle(WDTheme.muted)
                    }
                }
                .padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }
            .background(WDTheme.canvas)
            .navigationTitle("Compare towns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(WDTheme.accent)
    }

    private var ratioChart: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 18) {
                WDSectionHeader("Certified municipal ratios", subtitle: "Municipal assessment levels · source years on each card")
                Chart(reportedRatios) { town in
                    BarMark(x: .value("Ratio", town.ratio ?? 0), y: .value("Town", town.id))
                        .foregroundStyle(WDTheme.accent).cornerRadius(5)
                        .accessibilityLabel("\(town.name), published year \(RecordFormat.year(town.year))")
                        .accessibilityValue(WDTheme.percent(town.ratio))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let id = value.as(String.self), let town = towns.first(where: { $0.id == id }) {
                                Text(town.name).font(.caption2).lineLimit(2).frame(maxWidth: 100)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let ratio = value.as(Double.self) { Text(WDTheme.percent(ratio)) }
                        }
                    }
                }
                .frame(height: CGFloat(reportedRatios.count) * 62 + 36)
                Text("\(reportedRatios.count) of \(towns.count) selected towns have a reported ratio.")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            }
        }
    }
}

private struct TownComparisonCard: View {
    let town: Municipality
    let search: () -> Void

    var body: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "building.2").font(.title2).foregroundStyle(WDTheme.accent)
                Text(town.name).font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(WDTheme.ink).frame(minHeight: 58, alignment: .topLeading)
                Text(town.county + " County").font(.subheadline).foregroundStyle(WDTheme.muted)
                Divider()
                WDMetric("Certified ratio", value: WDTheme.percent(town.ratio), detail: "Published year: \(RecordFormat.year(town.year))")
                if town.effectiveTaxRate != nil { WDMetric("Effective tax rate", value: WDTheme.percent(town.effectiveTaxRate)) }
                if town.medianAssessment != nil { WDMetric("Median assessment", value: WDTheme.money(town.medianAssessment)) }
                if let size = town.sampleSize { RecordFact(title: "Reported sample size", value: size.formatted()) }
                Divider()
                ForEach(town.sources) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        if let url = RecordFormat.webURL(source.url) {
                            Link(destination: url) {
                                Label(source.title, systemImage: "arrow.up.right.square").frame(minHeight: 44)
                            }
                            .font(.subheadline.weight(.medium))
                        } else { Text(source.title).font(.subheadline.weight(.medium)) }
                        Text(source.detail).font(.caption).foregroundStyle(WDTheme.muted)
                    }
                }
                if town.sources.isEmpty {
                    Text("Source links were not provided for this record.").font(.caption).foregroundStyle(WDTheme.muted)
                }
                Button(action: search) { Label("Find properties", systemImage: "magnifyingglass") }
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }
}
