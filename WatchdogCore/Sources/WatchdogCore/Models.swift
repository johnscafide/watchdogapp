import Foundation

public enum DataMode: String, CaseIterable, Codable, Sendable {
    case live, sample
    public var label: String { self == .live ? "Live public records" : "Sample experience" }
}

// Kept as a domain type for a future separate Watchdog Pro client. It grants no access.
public enum ProfessionalRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case homeowner, agent, investor, lender, taxProfessional, appraiser, insurance
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .homeowner: return "Homeowner"
        case .agent: return "Real estate agent"
        case .investor: return "Investor"
        case .lender: return "Lending professional"
        case .taxProfessional: return "Tax professional"
        case .appraiser: return "Appraiser"
        case .insurance: return "Insurance professional"
        }
    }
    public var subtitle: String {
        switch self {
        case .homeowner: return "Understand the homes that matter to you."
        case .agent: return "Bring property evidence to every conversation."
        case .investor: return "Research assessments and carrying costs."
        case .lender: return "Review property and tax context."
        case .taxProfessional: return "Organize assessment evidence."
        case .appraiser: return "Follow the record and its sources."
        case .insurance: return "Research property change context."
        }
    }
    public var symbol: String {
        switch self {
        case .homeowner: return "house"
        case .agent: return "key"
        case .investor: return "chart.line.uptrend.xyaxis"
        case .lender: return "building.columns"
        case .taxProfessional: return "doc.text.magnifyingglass"
        case .appraiser: return "ruler"
        case .insurance: return "shield"
        }
    }
}

public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public struct PropertyRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var address: String
    public var town: String
    public var county: String
    public var postalCode: String
    public var block: String
    public var lot: String
    public var qualifier: String
    public var latitude: Double?
    public var longitude: Double?
    public var assessment: Double?
    public var landValue: Double?
    public var improvementValue: Double?
    public var taxAmount: Double?
    public var taxYear: Int?
    public var assessmentYear: Int?
    public var salePrice: Double?
    public var saleDate: String?
    public var yearBuilt: Int?
    public var livingArea: Double?
    public var acres: Double?
    public var propertyClass: String
    public var watchdogScore: Double?
    public var municipalRatio: Double?
    /// Retrieval time, NOT the effective date of an assessment or tax bill.
    public var updatedAt: Date
    public var isSample: Bool
    public var history: [AssessmentPoint]
    public var sales: [SaleRecord]
    public var sources: [SourceReference]
    public var parcelRings: [[GeoPoint]]
    public var buildingDescription: String?
    public var landDescription: String?
    public var sourcePublishedAt: Date?
    public var ratioYear: Int?
    public var scoreModel: String?
    public var scoreObservedAt: Date?
    public var scoreEvidenceCoverage: Double?
    public var scoreComponents: [ScoreComponent]

    public init(id: String, address: String, town: String = "", county: String = "", postalCode: String = "",
                block: String = "", lot: String = "", qualifier: String = "", latitude: Double? = nil,
                longitude: Double? = nil, assessment: Double? = nil, landValue: Double? = nil,
                improvementValue: Double? = nil, taxAmount: Double? = nil, taxYear: Int? = nil,
                assessmentYear: Int? = nil, salePrice: Double? = nil, saleDate: String? = nil,
                yearBuilt: Int? = nil, livingArea: Double? = nil, acres: Double? = nil,
                propertyClass: String = "", watchdogScore: Double? = nil, municipalRatio: Double? = nil,
                updatedAt: Date = Date(), isSample: Bool = false, history: [AssessmentPoint] = [],
                sales: [SaleRecord] = [], sources: [SourceReference] = [], parcelRings: [[GeoPoint]] = [],
                buildingDescription: String? = nil, landDescription: String? = nil,
                sourcePublishedAt: Date? = nil, ratioYear: Int? = nil, scoreModel: String? = nil,
                scoreObservedAt: Date? = nil, scoreEvidenceCoverage: Double? = nil,
                scoreComponents: [ScoreComponent] = []) {
        self.id = id; self.address = address; self.town = town; self.county = county
        self.postalCode = postalCode; self.block = block; self.lot = lot; self.qualifier = qualifier
        self.latitude = latitude; self.longitude = longitude; self.assessment = assessment
        self.landValue = landValue; self.improvementValue = improvementValue; self.taxAmount = taxAmount
        self.taxYear = taxYear; self.assessmentYear = assessmentYear; self.salePrice = salePrice
        self.saleDate = saleDate; self.yearBuilt = yearBuilt; self.livingArea = livingArea; self.acres = acres
        self.propertyClass = propertyClass; self.watchdogScore = watchdogScore; self.municipalRatio = municipalRatio
        self.updatedAt = updatedAt; self.isSample = isSample; self.history = history; self.sales = sales; self.sources = sources
        self.parcelRings = parcelRings; self.buildingDescription = buildingDescription; self.landDescription = landDescription
        self.sourcePublishedAt = sourcePublishedAt; self.ratioYear = ratioYear; self.scoreModel = scoreModel
        self.scoreObservedAt = scoreObservedAt; self.scoreEvidenceCoverage = scoreEvidenceCoverage
        self.scoreComponents = scoreComponents
    }
    public var impliedValue: Double? {
        guard let value = assessment, value.isFinite, value > 0,
              let ratio = municipalRatio, ratio.isFinite, ratio > 0 else { return nil }
        let result = value / ratio
        return result.isFinite ? result : nil
    }
    public var displayAddress: String { address.isEmpty ? "Block \(block), lot \(lot)" : address }
    public var searchText: String {
        [address, town, county, postalCode, block, lot, qualifier, id].joined(separator: " ").lowercased()
    }
}

public struct AssessmentPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var year: Int; public var assessment: Double; public var tax: Double?
    public init(id: String, year: Int, assessment: Double, tax: Double? = nil) {
        self.id = id; self.year = year; self.assessment = assessment; self.tax = tax
    }
}
public struct SaleRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var date: String; public var price: Double; public var usable: Bool; public var note: String
    public init(id: String, date: String, price: Double, usable: Bool = false, note: String = "") {
        self.id = id; self.date = date; self.price = price; self.usable = usable; self.note = note
    }
}
public struct SourceReference: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var title: String; public var url: String; public var detail: String
    public init(id: String, title: String, url: String, detail: String = "") {
        self.id = id; self.title = title; self.url = url; self.detail = detail
    }
}
public struct ScoreComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var title: String; public var score: Double?; public var weight: Double
    public init(id: String, title: String, score: Double? = nil, weight: Double) {
        self.id = id; self.title = title; self.score = score; self.weight = weight
    }
}
public struct Municipality: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var name: String; public var county: String; public var ratio: Double?
    public var effectiveTaxRate: Double?; public var medianAssessment: Double?; public var score: Double?
    public var sampleSize: Int?; public var year: Int?; public var isSample: Bool
    public var sources: [SourceReference]
    public init(id: String, name: String, county: String, ratio: Double? = nil,
                effectiveTaxRate: Double? = nil, medianAssessment: Double? = nil, score: Double? = nil,
                sampleSize: Int? = nil, year: Int? = nil, isSample: Bool = false, sources: [SourceReference] = []) {
        self.id = id; self.name = name; self.county = county; self.ratio = ratio
        self.effectiveTaxRate = effectiveTaxRate; self.medianAssessment = medianAssessment; self.score = score
        self.sampleSize = sampleSize; self.year = year; self.isSample = isSample; self.sources = sources
    }
}
public struct SavedSearch: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var query: String; public var createdAt: Date
    public init(id: String = UUID().uuidString, query: String, createdAt: Date = Date()) {
        self.id = id; self.query = query; self.createdAt = createdAt
    }
}
