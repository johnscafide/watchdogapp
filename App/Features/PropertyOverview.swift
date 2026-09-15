import SwiftUI
import WatchdogCore

struct PropertyOverview: View {
    let property: PropertyRecord
    private let columns = [GridItem(.adaptive(minimum: 145), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WDCard {
                VStack(alignment: .leading, spacing: 20) {
                    WDSectionHeader("The numbers", subtitle: "As reported by the available public sources")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        WDMetric("Total assessment", value: WDTheme.money(property.assessment), detail: "Assessment year: \(RecordFormat.year(property.assessmentYear))")
                        WDMetric("Annual property tax", value: WDTheme.money(property.taxAmount), detail: "Tax year: \(RecordFormat.year(property.taxYear))")
                        WDMetric("Land assessment", value: WDTheme.money(property.landValue))
                        WDMetric("Improvement assessment", value: WDTheme.money(property.improvementValue))
                    }
                }
            }
            WDCard {
                VStack(alignment: .leading, spacing: 10) {
                    WDSectionHeader("Know the property")
                    RecordFact(title: "Living area", value: RecordFormat.number(property.livingArea, suffix: " sq ft"))
                    RecordFact(title: "Lot size", value: RecordFormat.number(property.acres, suffix: " acres"))
                    RecordFact(title: "Year built", value: RecordFormat.year(property.yearBuilt))
                    RecordFact(title: "Property class", value: property.propertyClass.isEmpty ? "Not reported" : property.propertyClass)
                    if let description = property.buildingDescription, !description.isEmpty {
                        RecordFact(title: "Building description", value: description)
                    }
                    if let description = property.landDescription, !description.isEmpty {
                        RecordFact(title: "Land description", value: description)
                    }
                    Divider().overlay(WDTheme.line)
                    RecordFact(title: "County", value: property.county.isEmpty ? "Not reported" : property.county)
                    RecordFact(title: "Block / lot", value: blockLot)
                    if !property.qualifier.isEmpty { RecordFact(title: "Qualifier", value: property.qualifier) }
                    Text("Parcel ID: \(property.id)").font(.caption).foregroundStyle(WDTheme.muted).textSelection(.enabled)
                }
            }
            WDCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Understand the assessment", systemImage: "info.circle")
                        .font(.headline).foregroundStyle(WDTheme.ink)
                    Text("An assessment is the value recorded for local taxation. It is different from a listing price, an appraisal, or what a buyer may pay.")
                        .font(.subheadline).foregroundStyle(WDTheme.muted)
                    if let ratio = property.municipalRatio, ratio.isFinite, ratio > 0 {
                        Divider()
                        RecordFact(title: "Municipal equalization ratio", value: WDTheme.percent(ratio))
                        RecordFact(title: "Ratio year", value: RecordFormat.year(property.ratioYear))
                        if let implied = property.impliedValue, implied.isFinite {
                            RecordFact(title: "Ratio-adjusted assessment", value: WDTheme.money(implied))
                            Text("Calculated as assessment ÷ municipal equalization ratio. This calculation is a reference point; it is not a property-specific market estimate or evidence that taxes are incorrect.")
                                .font(.caption).foregroundStyle(WDTheme.muted)
                        }
                    }
                    Text("Check the source year and contact the municipal assessor for questions about the official record.")
                        .font(.caption).foregroundStyle(WDTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var blockLot: String {
        if property.block.isEmpty && property.lot.isEmpty { return "Not reported" }
        return "\(property.block.isEmpty ? "—" : property.block) / \(property.lot.isEmpty ? "—" : property.lot)"
    }
}
