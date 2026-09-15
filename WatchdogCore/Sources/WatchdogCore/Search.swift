import Foundation

public struct PropertyFilters: Codable, Equatable, Sendable {
    public var minAssessment: Double?
    public var maxAssessment: Double?
    public var minScore: Double?
    public var residentialOnly: Bool
    public init(minAssessment: Double? = nil, maxAssessment: Double? = nil,
                minScore: Double? = nil, residentialOnly: Bool = false) {
        self.minAssessment = minAssessment; self.maxAssessment = maxAssessment
        self.minScore = minScore; self.residentialOnly = residentialOnly
    }
    public var isActive: Bool { minAssessment != nil || maxAssessment != nil || minScore != nil || residentialOnly }
    public func matches(_ property: PropertyRecord) -> Bool {
        if residentialOnly && property.propertyClass != "2" { return false }
        if let min = minAssessment, property.assessment.map({ $0.isFinite && $0 >= min }) != true { return false }
        if let max = maxAssessment, property.assessment.map({ $0.isFinite && $0 <= max }) != true { return false }
        if let min = minScore, property.watchdogScore.map({ $0.isFinite && $0 >= min }) != true { return false }
        return true
    }
}

public enum PropertySort: String, CaseIterable, Identifiable, Sendable {
    case relevance, assessmentLow, assessmentHigh, scoreHigh
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .relevance: return "Best match"
        case .assessmentLow: return "Assessment: low to high"
        case .assessmentHigh: return "Assessment: high to low"
        case .scoreHigh: return "Watchdog Score"
        }
    }
    public func apply(to properties: [PropertyRecord]) -> [PropertyRecord] {
        guard self != .relevance else { return properties }
        return properties.enumerated().sorted { a, b in
            let lhs = self == .scoreHigh ? a.element.watchdogScore : a.element.assessment
            let rhs = self == .scoreHigh ? b.element.watchdogScore : b.element.assessment
            let left = lhs.flatMap { $0.isFinite ? $0 : nil }, right = rhs.flatMap { $0.isFinite ? $0 : nil }
            switch (left, right) {
            case let (x?, y?) where x != y: return self == .assessmentLow ? x < y : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// Builds only fixed-column, escaped literal predicates. User text is never SQL syntax.
public enum ParcelSearchQuery {
    public static func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).uppercased()
    }
    static func literal(_ input: String) -> String { input.replacingOccurrences(of: "'", with: "''") }
    public static func predicate(for input: String) throws -> String {
        let query = normalized(input)
        guard query.count >= 2, query.count <= 180 else { throw PropertyServiceError.invalidQuery }
        guard !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PropertyServiceError.invalidQuery
        }
        if query.range(of: "^\\d{4}_[A-Z0-9.]+_[A-Z0-9.]+(?:_[A-Z0-9.]*)?$", options: .regularExpression) != nil {
            return "PAMS_PIN = '\(literal(query))'"
        }
        // Explicit block/lot syntax: "block 12 lot 3, Haddonfield".
        let regex = try NSRegularExpression(pattern: "^BLOCK\\s+([0-9.]+)\\s+LOT\\s+([0-9.]+)(?:,?\\s+(.+))?$")
        let nsQuery = query as NSString
        if let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: nsQuery.length)) {
            var result = "PCLBLOCK = '\(literal(nsQuery.substring(with: match.range(at: 1))))' AND PCLLOT = '\(literal(nsQuery.substring(with: match.range(at: 2))))'"
            if match.range(at: 3).location != NSNotFound {
                result += " AND UPPER(MUN_NAME) LIKE '\(literal(nsQuery.substring(with: match.range(at: 3))))%'"
            }
            return result
        }
        // Strip only an explicit trailing state name; NEW and JERSEY are meaningful
        // in municipalities such as New Brunswick and Jersey City.
        let addressQuery = query.replacingOccurrences(of: ",\\s*NEW JERSEY(?:\\s+\\d{5}(?:-\\d{4})?)?$", with: "", options: .regularExpression)
        let tokens = addressQuery.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty && $0 != "NJ" }
        guard !tokens.isEmpty, tokens.count <= 16 else { throw PropertyServiceError.invalidQuery }
        let aliases = ["STREET": "ST", "AVENUE": "AVE", "ROAD": "RD", "DRIVE": "DR", "COURT": "CT", "LANE": "LN", "BOULEVARD": "BLVD", "TOWNSHIP": "TWP", "BOROUGH": "BORO"]
        return tokens.map { token in
            let safe = literal(token)
            var clauses = ["UPPER(PROP_LOC) LIKE '%\(safe)%'", "UPPER(MUN_NAME) LIKE '%\(safe)%'"]
            if let abbreviation = aliases[token] { clauses.append("UPPER(PROP_LOC) LIKE '%\(abbreviation)%'"); clauses.append("UPPER(MUN_NAME) LIKE '%\(abbreviation)%'") }
            return "(" + clauses.joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
    }
}
