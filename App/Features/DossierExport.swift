import SwiftUI
import UIKit
import WatchdogCore

struct ExportedDossier: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
enum DossierExport {
    static func text(for property: PropertyRecord) -> String {
        var lines = [
            "WATCHDOG · PROPERTY RECORD",
            property.isSample ? "ILLUSTRATIVE SAMPLE — not a real-property report" : "Public property record",
            "",
            property.displayAddress,
            "\(property.town), NJ \(property.postalCode)",
            "County: \(property.county)",
            "Parcel ID: \(property.id)",
            "Block: \(property.block) · Lot: \(property.lot)",
            "",
            "REPORTED VALUES",
            "Assessment: \(WDTheme.money(property.assessment))",
            "Assessment year: \(RecordFormat.year(property.assessmentYear))",
            "Land assessment: \(WDTheme.money(property.landValue))",
            "Improvement assessment: \(WDTheme.money(property.improvementValue))",
            "Annual property tax: \(WDTheme.money(property.taxAmount))",
            "Tax year: \(RecordFormat.year(property.taxYear))",
            "Living area: \(RecordFormat.number(property.livingArea, suffix: " sq ft"))",
            "Lot size: \(RecordFormat.number(property.acres, suffix: " acres"))",
            "Year built: \(RecordFormat.year(property.yearBuilt))",
            "Property class: \(property.propertyClass.isEmpty ? "Not reported" : property.propertyClass)",
            "Watchdog Score: \(property.watchdogScore.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "Not available")",
            "The Watchdog Score, powered by the ROBUST Framework."
        ]
        if let ratio = property.municipalRatio, ratio.isFinite, ratio > 0 {
            lines += ["Municipal equalization ratio: \(WDTheme.percent(ratio))", "Ratio year: \(RecordFormat.year(property.ratioYear))"]
            if let implied = property.impliedValue {
                lines.append("Ratio-adjusted assessment: \(WDTheme.money(implied)); assessment divided by the municipal ratio, not a property-specific market estimate")
            }
        }
        if property.watchdogScore != nil {
            lines += ["", "SCORE EVIDENCE", "Model: \(property.scoreModel ?? "Not supplied")"]
            if let observed = property.scoreObservedAt {
                lines.append("Score observed: \(observed.formatted(date: .abbreviated, time: .omitted))")
            }
            if let coverage = property.scoreEvidenceCoverage {
                lines.append("Evidence coverage: \(WDTheme.percent(coverage / 100))")
            }
            for component in property.scoreComponents {
                lines.append("\(component.title): \(RecordFormat.number(component.score)); model weight \(WDTheme.percent(component.weight))")
            }
            lines.append("A Watchdog-derived indicator, not an appraisal or a government finding.")
        }
        if !property.history.isEmpty {
            lines += ["", "ASSESSMENT HISTORY"]
            for point in property.history.sorted(by: { $0.year < $1.year }) {
                lines.append("\(point.year): \(WDTheme.money(point.assessment)); tax \(WDTheme.money(point.tax))")
            }
        }
        if !property.sales.isEmpty {
            lines += ["", "RECORDED SALES"]
            for sale in property.sales.sorted(by: { $0.date > $1.date }) {
                lines.append("\(RecordFormat.date(sale.date)): \(WDTheme.money(sale.price)); \(sale.usable ? "marked usable" : "not marked usable") by source. \(sale.note)")
            }
        } else if let price = property.salePrice {
            lines += ["", "LAST REPORTED SALE", "\(RecordFormat.date(property.saleDate)): \(WDTheme.money(price))"]
        }
        lines += ["", "SOURCES"]
        if property.sources.isEmpty { lines.append("No source links were supplied with this record.") }
        for source in property.sources {
            lines += [source.title, source.detail]
            if RecordFormat.webURL(source.url) != nil { lines.append(source.url) }
        }
        if let published = property.sourcePublishedAt {
            lines.append("Property source published: \(published.formatted(date: .abbreviated, time: .omitted))")
        }
        lines += [
            "",
            "Retrieved: \(property.updatedAt.formatted(date: .abbreviated, time: .shortened))",
            "Report created: \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            "",
            "An assessment is a recorded value for taxation, not an appraisal or a market estimate. Historical transfers are not active listings. Missing values are not estimated. Assessment and tax years may differ. Confirm current figures with the municipality and review original sources before relying on this summary.",
            "Personal notes are excluded from this report.",
            "Watchdog · https://www.watchdogindex.com"
        ]
        return lines.joined(separator: "\n")
    }

    static func pdf(for property: PropertyRecord) throws -> ExportedDossier {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WatchdogReports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeID = property.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let url = directory.appendingPathComponent("Watchdog-\(safeID.prefix(60))-\(UUID().uuidString.prefix(8)).pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Watchdog — \(property.displayAddress)",
            kCGPDFContextCreator as String: "Watchdog for iOS"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        try renderer.writePDF(to: url) { context in
            let regular = UIFont.systemFont(ofSize: 11)
            let heading = UIFont.systemFont(ofSize: 11, weight: .bold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 3
            let forest = UIColor(red: 0.06, green: 0.20, blue: 0.16, alpha: 1)
            var cursor: CGFloat = 90
            var page = 0

            func beginPage() {
                context.beginPage()
                page += 1
                cursor = 90
                forest.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 612, height: 58))
                ("Watchdog" as NSString).draw(at: CGPoint(x: 42, y: 18), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: UIColor.white
                ])
                ("PROPERTY RECORD" as NSString).draw(at: CGPoint(x: 425, y: 25), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.white
                ])
                ("Watchdog · \(page)" as NSString).draw(at: CGPoint(x: 42, y: 755), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray
                ])
            }

            beginPage()
            // Wrap long source notes into individual words first so even unusually long
            // metadata can continue onto another page without clipping a paragraph.
            for paragraphText in text(for: property).components(separatedBy: "\n") {
                if paragraphText.isEmpty { cursor += 9; continue }
                let isHeading = paragraphText == paragraphText.uppercased() && paragraphText.count < 85
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: isHeading ? heading : regular,
                    .foregroundColor: forest,
                    .paragraphStyle: paragraph
                ]
                var chunks: [String] = []
                var chunk = ""
                for word in paragraphText.split(separator: " ", omittingEmptySubsequences: false) {
                    let candidate = chunk.isEmpty ? String(word) : chunk + " " + word
                    let height = (candidate as NSString).boundingRect(with: CGSize(width: 528, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
                    if height > 170 && !chunk.isEmpty {
                        chunks.append(chunk)
                        chunk = String(word)
                    } else { chunk = candidate }
                }
                if !chunk.isEmpty { chunks.append(chunk) }
                for segment in chunks {
                    let height = ceil((segment as NSString).boundingRect(with: CGSize(width: 528, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
                    if cursor + height > 726 { beginPage() }
                    (segment as NSString).draw(in: CGRect(x: 42, y: cursor, width: 528, height: height + 2), withAttributes: attributes)
                    cursor += height + 5
                }
            }
        }
        return ExportedDossier(url: url)
    }
}

struct DossierShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
