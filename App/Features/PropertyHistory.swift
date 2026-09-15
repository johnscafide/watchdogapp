import SwiftUI
import Charts
import WatchdogCore

struct PropertyHistory: View {
    let property: PropertyRecord

    private var assessmentHistory: [AssessmentPoint] {
        property.history.filter { $0.assessment.isFinite && $0.assessment >= 0 }.sorted { $0.year < $1.year }
    }

    private var sales: [SaleRecord] {
        property.sales.filter { $0.price.isFinite && $0.price >= 0 }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WDCard {
                VStack(alignment: .leading, spacing: 18) {
                    WDSectionHeader("Assessment history", subtitle: "Only years present in the source are shown")
                    if assessmentHistory.isEmpty {
                        WDEmptyState(title: "History isn’t available", message: "This record does not include assessment history. The current reported assessment is in Overview.", symbol: "chart.bar.xaxis")
                    } else {
                        Chart(assessmentHistory) { point in
                            BarMark(x: .value("Year", String(point.year)), y: .value("Assessment", point.assessment))
                                .foregroundStyle(WDTheme.accent)
                                .cornerRadius(5)
                                .accessibilityLabel("\(point.year) assessment")
                                .accessibilityValue(WDTheme.money(point.assessment))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let number = value.as(Double.self) { Text(WDTheme.compactMoney(number)) }
                                }
                            }
                        }
                        .frame(height: 220)
                        ForEach(assessmentHistory.reversed()) { point in
                            HStack {
                                Text(String(point.year)).font(.subheadline.weight(.medium))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(WDTheme.money(point.assessment)).font(.subheadline.monospacedDigit())
                                    if let tax = point.tax {
                                        Text("Tax \(WDTheme.money(tax))").font(.caption).foregroundStyle(WDTheme.muted)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            WDCard {
                VStack(alignment: .leading, spacing: 18) {
                    WDSectionHeader("Recorded sales", subtitle: "Historical transfers, not active listings")
                    if sales.isEmpty {
                        if let price = property.salePrice {
                            RecordFact(title: "Last recorded sale", value: WDTheme.money(price))
                            RecordFact(title: "Recorded date", value: RecordFormat.date(property.saleDate))
                            Text("A full transfer history is not available in this source.").font(.caption).foregroundStyle(WDTheme.muted)
                        } else {
                            WDEmptyState(title: "No sales reported", message: "The available source does not include a recorded sale for this property.", symbol: "doc.text.magnifyingglass")
                        }
                    } else {
                        ForEach(sales) { sale in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(WDTheme.money(sale.price)).font(.title3.weight(.semibold).monospacedDigit())
                                    Spacer()
                                    Text(RecordFormat.date(sale.date)).font(.subheadline).foregroundStyle(WDTheme.muted)
                                }
                                Text(sale.usable ? "Source marks this sale as usable" : "Source does not mark this sale as usable")
                                    .font(.caption).foregroundStyle(WDTheme.muted)
                                if !sale.note.isEmpty { Text(sale.note).font(.caption).foregroundStyle(WDTheme.muted) }
                            }
                            .padding(.vertical, 7)
                            .accessibilityElement(children: .combine)
                        }
                        Text("Transfer prices may reflect family transfers, partial interests, or other conditions. Review the underlying record before using a sale as a comparison.")
                            .font(.caption).foregroundStyle(WDTheme.muted)
                    }
                }
            }
        }
    }
}
