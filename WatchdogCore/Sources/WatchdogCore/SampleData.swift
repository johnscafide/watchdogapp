import Foundation

/// Entirely fictional research fixtures. Never a fallback for a failed live request.
public enum SampleData {
    public static let observedAt = Date(timeIntervalSince1970: 1_783_036_800)
    public static let source = SourceReference(
        id: "sample", title: "Illustrative sample data", url: "https://www.watchdogindex.com/",
        detail: "Fictional addresses, parcel identifiers, figures and map locations created to demonstrate the app. They describe no real property and cannot be used as research evidence."
    )

    public static let properties: [PropertyRecord] = [
        make(1, "24 Lantern Lane", "Haddonfield", "Camden", "08033", 39.8986, -75.0355, 542_000, 15_320, 1928, 2_140, 0.23, 0.6842),
        make(2, "8 Orchard Walk", "Haddonfield", "Camden", "08033", 39.9015, -75.0312, 468_500, 13_260, 1942, 1_840, 0.19, 0.6842),
        make(3, "16 Linden Mews", "Haddonfield", "Camden", "08033", 39.8958, -75.0285, 687_200, 19_380, 1915, 2_750, 0.31, 0.6842),
        make(4, "42 Meadow Court", "Cherry Hill", "Camden", "08034", 39.9252, -75.0025, 326_800, 12_190, 1966, 2_080, 0.28, 0.5574),
        make(5, "6 Birch Terrace", "Cherry Hill", "Camden", "08003", 39.9071, -74.9697, 289_000, 10_780, 1973, 1_790, 0.22, 0.5574),
        make(6, "19 Garden Row", "Princeton", "Mercer", "08540", 40.3518, -74.6592, 812_000, 18_630, 1936, 2_340, 0.34, 0.7231),
        make(7, "3 Willow Passage", "Princeton", "Mercer", "08540", 40.3542, -74.6528, 634_500, 14_560, 1982, 1_960, 0.21, 0.7231),
        make(8, "28 Fern Crescent", "Montclair", "Essex", "07042", 40.8194, -74.2148, 734_000, 22_150, 1910, 2_620, 0.27, 0.6138),
        make(9, "11 Harbor Mews", "Jersey City", "Hudson", "07302", 40.7221, -74.0469, 591_000, 12_450, 2008, 1_280, nil, 0.7486),
        make(10, "7 Dune Walk", "Cape May", "Cape May", "08204", 38.9367, -74.9191, 758_000, 7_240, 1904, 1_680, 0.14, 0.6382),
        // A deliberately incomplete record exercises honest missing-data states.
        PropertyRecord(id: "sample-11", address: "31 Fieldstone Way", town: "Haddonfield", county: "Camden",
            block: "12", lot: "11", latitude: 39.9030, longitude: -75.0256,
            propertyClass: "1", updatedAt: observedAt, isSample: true, sources: [source])
    ]

    public static let municipalities: [Municipality] = [
        town("sample-haddonfield", "Haddonfield", "Camden", 0.6842, 0.0194, 524_000, 4_102),
        town("sample-cherry-hill", "Cherry Hill", "Camden", 0.5574, 0.0241, 310_800, 18_540),
        town("sample-princeton", "Princeton", "Mercer", 0.7231, 0.0178, 738_000, 6_820),
        town("sample-montclair", "Montclair", "Essex", 0.6138, 0.0226, 669_300, 8_614),
        town("sample-jersey-city", "Jersey City", "Hudson", 0.7486, 0.0198, 542_700, 28_963),
        town("sample-cape-may", "Cape May", "Cape May", 0.6382, 0.0082, 719_800, 2_650)
    ]

    private static func town(_ id: String, _ name: String, _ county: String, _ ratio: Double,
                             _ rate: Double, _ median: Double, _ size: Int) -> Municipality {
        Municipality(id: id, name: name, county: county, ratio: ratio, effectiveTaxRate: rate,
                     medianAssessment: median, sampleSize: size, year: 2026, isSample: true, sources: [source])
    }

    private static func make(_ index: Int, _ address: String, _ town: String, _ county: String,
                             _ zip: String, _ lat: Double, _ lon: Double, _ assessment: Double,
                             _ tax: Double, _ built: Int, _ area: Double, _ acres: Double?, _ ratio: Double) -> PropertyRecord {
        let id = "sample-\(index)"
        let previous = assessment * 0.94
        let history = [
            AssessmentPoint(id: id + "-2022", year: 2022, assessment: previous, tax: tax * 0.87),
            AssessmentPoint(id: id + "-2023", year: 2023, assessment: previous, tax: tax * 0.90),
            AssessmentPoint(id: id + "-2024", year: 2024, assessment: previous, tax: tax * 0.94),
            AssessmentPoint(id: id + "-2025", year: 2025, assessment: assessment, tax: tax * 0.97),
            AssessmentPoint(id: id + "-2026", year: 2026, assessment: assessment, tax: tax)
        ]
        let saleDate = "2021-06-15"
        let salePrice = (assessment / ratio * 0.81 / 1_000).rounded() * 1_000
        return PropertyRecord(id: id, address: address, town: town, county: county, postalCode: zip,
            block: "12", lot: String(index), latitude: lat, longitude: lon,
            assessment: assessment, landValue: assessment * 0.42, improvementValue: assessment * 0.58,
            taxAmount: tax, taxYear: 2026, assessmentYear: 2026, salePrice: salePrice, saleDate: saleDate,
            yearBuilt: built, livingArea: area, acres: acres, propertyClass: "2", municipalRatio: ratio,
            updatedAt: observedAt, isSample: true, history: history,
            sales: [SaleRecord(id: id + "-sale", date: saleDate, price: salePrice,
                note: "Fictional sample deed. This is not a recorded sale.")], sources: [source],
            buildingDescription: "Illustrative residential property", ratioYear: 2026)
    }
}

public struct SamplePropertyService: PropertyService {
    public init() {}

    public func search(_ query: String) async throws -> [PropertyRecord] {
        try Task.checkCancellation()
        let normalized = ParcelSearchQuery.normalized(query)
        if normalized.isEmpty { return SampleData.properties }
        guard normalized.count <= 180 else { throw PropertyServiceError.invalidQuery }
        let tokens = normalized.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-'" )).inverted)
            .filter { !$0.isEmpty && !["nj", "new", "jersey", "block", "lot"].contains($0) }
        guard !tokens.isEmpty else { return SampleData.properties }
        return SampleData.properties.filter { property in tokens.allSatisfy { property.searchText.contains($0) } }
    }

    public func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [PropertyRecord] {
        try Task.checkCancellation()
        guard WatchdogPropertyService.isNewJerseyRegion(latitude: latitude, longitude: longitude),
              radiusMeters.isFinite, radiusMeters > 0 else { throw PropertyServiceError.invalidLocation }
        let radius = min(max(radiusMeters, 50), 10_000)
        return SampleData.properties.compactMap { property -> (PropertyRecord, Double)? in
            guard let lat = property.latitude, let lon = property.longitude else { return nil }
            let dy = (lat - latitude) * .pi / 180, dx = (lon - longitude) * .pi / 180
            let a = pow(sin(dy / 2), 2) + cos(latitude * .pi / 180) * cos(lat * .pi / 180) * pow(sin(dx / 2), 2)
            let distance = 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
            return distance <= radius ? (property, distance) : nil
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    public func detail(for property: PropertyRecord) async throws -> PropertyRecord {
        try Task.checkCancellation()
        guard property.isSample, let found = SampleData.properties.first(where: { $0.id == property.id }) else {
            throw PropertyServiceError.propertyNotFound
        }
        return found
    }

    public func municipalities() async throws -> [Municipality] {
        try Task.checkCancellation()
        return SampleData.municipalities
    }
}
