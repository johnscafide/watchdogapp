import SwiftUI
import Charts
import WatchdogCore

struct CompareView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var metric: ComparisonMetric = .assessment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Put the record\nin perspective.")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .foregroundStyle(WDTheme.ink)
                    if store.comparisonProperties.isEmpty {
                        WDCard {
                            WDEmptyState(title: "Your comparison is clear", message: "Open a property and tap Compare to add it here. You can compare up to four records.", symbol: "square.split.2x1")
                        }
                    } else {
                        if store.comparisonProperties.count == 1 {
                            Text("Add another property from Explore or Saved to see the records side by side.")
                                .font(.subheadline).foregroundStyle(WDTheme.muted)
                        }
                        if store.mode == .sample { RecordDataLabel(isSample: true) }
                        comparisonCards
                        if store.comparisonProperties.count > 1 { chart }
                        WDCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Compare like with like", systemImage: "info.circle").font(.headline)
                                Text("Assessments and taxes can relate to different years and municipal systems. Review the year on each record. A difference in assessment does not establish a difference in market value or an error in the tax record.")
                                    .font(.subheadline).foregroundStyle(WDTheme.muted)
                                Text("— means the source did not report a value.")
                                    .font(.caption).foregroundStyle(WDTheme.muted)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .background(WDTheme.canvas)
            .navigationTitle("Compare properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !store.comparisonProperties.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            for property in store.comparisonProperties { store.toggleComparison(property) }
                        }
                    }
                }
            }
        }
        .tint(WDTheme.accent)
    }

    private var comparisonCards: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.comparisonProperties) { property in
                    ComparisonPropertyCard(property: property) { store.toggleComparison(property) }
                        .frame(width: 280)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.visible)
        .scrollClipDisabled()
        .accessibilityLabel("Property comparison cards. Scroll horizontally to see more properties.")
    }

    private var chart: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 18) {
                WDSectionHeader("Reported amounts", subtitle: "No values are estimated")
                Picker("Comparison metric", selection: $metric) {
                    ForEach(ComparisonMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                let values = store.comparisonProperties.filter { property in
                    guard let value = metric.value(for: property) else { return false }
                    return value.isFinite && value >= 0
                }
                if values.isEmpty {
                    Text("This amount is not reported for the selected properties.")
                        .font(.subheadline).foregroundStyle(WDTheme.muted)
                } else {
                    Chart(values) { property in
                        BarMark(x: .value(metric.rawValue, metric.value(for: property) ?? 0), y: .value("Property", property.id))
                            .foregroundStyle(WDTheme.accent)
                            .cornerRadius(5)
                            .accessibilityLabel("\(property.displayAddress), \(metric.rawValue)")
                            .accessibilityValue(WDTheme.money(metric.value(for: property)))
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let id = value.as(String.self), let property = values.first(where: { $0.id == id }) {
                                    Text(property.displayAddress).font(.caption2).lineLimit(2).frame(maxWidth: 100)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) { Text(WDTheme.compactMoney(amount)) }
                            }
                        }
                    }
                    .frame(height: CGFloat(values.count) * 65 + 32)
                    Text("Showing \(values.count) of \(store.comparisonProperties.count) records with a reported amount. Figures can be from different years; see the cards above.")
                        .font(.caption).foregroundStyle(WDTheme.muted)
                }
            }
        }
    }
}

private enum ComparisonMetric: String, CaseIterable, Identifiable {
    case assessment = "Assessment"
    case tax = "Annual tax"
    var id: String { rawValue }

    func value(for property: PropertyRecord) -> Double? {
        switch self {
        case .assessment: return property.assessment
        case .tax: return property.taxAmount
        }
    }
}

private struct ComparisonPropertyCard: View {
    let property: PropertyRecord
    let remove: () -> Void

    var body: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "house").font(.title3).foregroundStyle(WDTheme.accent)
                    Spacer()
                    Button(action: remove) { Image(systemName: "xmark.circle.fill").font(.title3) }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove \(property.displayAddress) from comparison")
                }
                Text(property.displayAddress).font(.system(.title2, design: .serif, weight: .medium))
                    .frame(minHeight: 62, alignment: .topLeading)
                Text(property.town).font(.subheadline).foregroundStyle(WDTheme.muted)
                Divider()
                WDMetric("Assessment", value: WDTheme.money(property.assessment), detail: "Year: \(RecordFormat.year(property.assessmentYear))")
                WDMetric("Annual tax", value: WDTheme.money(property.taxAmount), detail: "Year: \(RecordFormat.year(property.taxYear))")
                Divider()
                RecordFact(title: "Living area", value: RecordFormat.number(property.livingArea, suffix: " sq ft"))
                RecordFact(title: "Lot", value: RecordFormat.number(property.acres, suffix: " ac"))
                RecordFact(title: "Built", value: RecordFormat.year(property.yearBuilt))
                RecordFact(title: "Last sale", value: WDTheme.money(property.salePrice))
                Text("Sale date: \(RecordFormat.date(property.saleDate))").font(.caption).foregroundStyle(WDTheme.muted)
                WDScoreBadge(score: property.watchdogScore)
                if let source = property.sources.first, let url = RecordFormat.webURL(source.url) {
                    Link(destination: url) { Label("Source", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
