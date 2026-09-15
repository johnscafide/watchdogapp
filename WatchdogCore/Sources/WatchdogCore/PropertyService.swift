import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol PropertyService: Sendable {
    func search(_ query: String) async throws -> [PropertyRecord]
    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [PropertyRecord]
    func detail(for property: PropertyRecord) async throws -> PropertyRecord
    func municipalities() async throws -> [Municipality]
}

public enum PropertyServiceError: Error, LocalizedError, Equatable, Sendable {
    case invalidQuery, invalidLocation, invalidConfiguration, invalidResponse, propertyNotFound
    case httpStatus(Int), sourceFailure(Int), networkUnavailable, timeout
    public var errorDescription: String? {
        switch self {
        case .invalidQuery: return "Enter an address, New Jersey town, parcel ID, or block and lot."
        case .invalidLocation: return "Choose a location in New Jersey to search nearby properties."
        case .invalidConfiguration: return "The public data connection is not configured correctly."
        case .invalidResponse: return "The source returned a record format Watchdog could not read. Try again later."
        case .propertyNotFound: return "This parcel is no longer in the current source. Try searching the address again."
        case .httpStatus(429): return "The public source is busy. Please wait a moment and try again."
        case .httpStatus: return "The public source is temporarily unavailable. Please try again."
        case .sourceFailure: return "The property source could not complete this lookup. Refine your search or try again."
        case .networkUnavailable: return "The public source could not be reached. Check your connection and try again."
        case .timeout: return "The public source took too long to respond. Please try again."
        }
    }
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PropertyServiceError.invalidResponse }
        return (data, http)
    }
}

public struct WatchdogServiceConfiguration: Sendable {
    public var parcelEndpoint: URL
    public var geocodeEndpoint: URL
    public var websiteBase: URL
    public var backendBase: URL
    /// Public client identifier already shipped by Watchdog's browser. Never put a secret key here.
    public var publishableKey: String
    public var requestTimeout: TimeInterval
    public init(
        parcelEndpoint: URL = URL(string: "https://services2.arcgis.com/XVOqAjTOJ5P6ngMu/ArcGIS/rest/services/Parcels_Composite_NJ_WM/FeatureServer/0/query")!,
        geocodeEndpoint: URL = URL(string: "https://geo.nj.gov/arcgis/rest/services/Tasks/NJ_Geocode/GeocodeServer/findAddressCandidates")!,
        websiteBase: URL = URL(string: "https://www.watchdogindex.com")!,
        backendBase: URL = URL(string: "https://uvkvaxljhhngydvlrzom.supabase.co")!,
        publishableKey: String = "sb_publishable_MYX59qCbK3d-21zDfJqkNw_fvmfnexa",
        requestTimeout: TimeInterval = 20
    ) {
        self.parcelEndpoint = parcelEndpoint; self.geocodeEndpoint = geocodeEndpoint
        self.websiteBase = websiteBase; self.backendBase = backendBase
        self.publishableKey = publishableKey; self.requestTimeout = requestTimeout
    }
}

/// Real public records. A source outage never switches this service to sample fixtures.
public actor WatchdogPropertyService: PropertyService {
    private let configuration: WatchdogServiceConfiguration
    private let transport: any HTTPTransport
    private var townCache: (Date, [Municipality])?
    public static let resultLimit = 200
    public static let parcelFields = [
        "PAMS_PIN", "PCL_MUN", "COUNTY", "MUN_NAME", "PROP_LOC", "PCLBLOCK", "PCLLOT", "PCLQCODE",
        "PROP_CLASS", "BLDG_DESC", "LAND_DESC", "CALC_ACRE", "YR_CONSTR", "LAND_VAL", "IMPRVT_VAL",
        "NET_VALUE", "LAST_YR_TX", "SALE_PRICE", "DEED_DATE", "DEED_BOOK", "DEED_PAGE", "PCL_PBDATE"
    ].joined(separator: ",")

    public init(configuration: WatchdogServiceConfiguration = .init(), transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration; self.transport = transport
    }

    public func search(_ query: String) async throws -> [PropertyRecord] {
        try Task.checkCancellation()
        let predicate = try ParcelSearchQuery.predicate(for: query)
        var rows = try await parcels(where: predicate)
        if rows.isEmpty {
            // A geocoder is used only as a fallback. Point/intersection lookup preserves all condo candidates.
            let location = try await geocode(query)
            if let location {
                rows = try await spatialQuery(latitude: location.latitude, longitude: location.longitude, distance: 20)
            }
        }
        return try await attachScores(to: rows)
    }

    public func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [PropertyRecord] {
        guard Self.isNewJerseyRegion(latitude: latitude, longitude: longitude), radiusMeters.isFinite, radiusMeters > 0 else {
            throw PropertyServiceError.invalidLocation
        }
        let rows = try await spatialQuery(latitude: latitude, longitude: longitude, distance: min(max(radiusMeters, 50), 10000))
        let ordered = rows.sorted {
            Self.distance($0, latitude, longitude) < Self.distance($1, latitude, longitude)
        }
        return try await attachScores(to: ordered)
    }

    public func detail(for property: PropertyRecord) async throws -> PropertyRecord {
        try Task.checkCancellation()
        // A sample parcel identifier is never submitted to a live service.
        guard !property.isSample, !property.id.isEmpty, property.id.count <= 40 else { throw PropertyServiceError.propertyNotFound }
        let records = try await parcels(where: "PAMS_PIN = '\(ParcelSearchQuery.literal(property.id))'", geometry: true)
        guard var result = records.first(where: { $0.id == property.id }) else { throw PropertyServiceError.propertyNotFound }
        async let score = optionalDocument(endpoint: configuration.backendBase.appendingPathComponent("rest/v1/rpc/get_public_property_watchdog_score_details"), body: ["p_pins": .array([.string(result.id)])], apiKey: true)
        async let ratio = chapterRatio(district: String(result.id.prefix(4)))
        let (scoreDocument, ratioDocument) = try await (score, ratio)
        if let row = scoreDocument?.array?.first(where: { $0["pams_pin"]?.string == result.id })?.object {
            Self.applyScore(row, to: &result)
        }
        if result.watchdogScore == nil {
            result.sources.append(SourceReference(id: "score-availability", title: "Watchdog Score availability", url: "https://www.watchdogindex.com/data-methodology", detail: "No canonical Watchdog Score was returned for this parcel. Missing evidence is not a score of zero."))
        }
        if let ratioDocument, ratioDocument["district"]?.string == String(result.id.prefix(4)),
           let row = ratioDocument["data"]?.object,
           let percentage = row["ratio"]?.number, percentage > 0, percentage <= 200 {
            result.municipalRatio = percentage / 100
            result.ratioYear = ratioDocument["tax_year"]?.integer
            result.sources.append(SourceReference(id: "chapter123", title: "NJ Division of Taxation · Chapter 123", url: ratioDocument["source_url"]?.string ?? "https://www.nj.gov/treasury/taxation/lpt/lptvalue.shtml", detail: "Certified municipal ratio for \(result.ratioYear.map(String.init) ?? "the source tax year"). Dividing assessment by this ratio gives assessment-implied value, not a market appraisal or sale prediction."))
        } else {
            result.sources.append(SourceReference(id: "ratio-availability", title: "Municipal ratio availability", url: "https://www.watchdogindex.com/data-methodology", detail: "The certified municipal ratio was unavailable during this lookup. No implied value has been estimated."))
        }
        return result
    }

    public func municipalities() async throws -> [Municipality] {
        try Task.checkCancellation()
        if let cache = townCache, Date().timeIntervalSince(cache.0) < 3600 { return cache.1 }
        let manifest = try await document(endpoint: configuration.websiteBase.appendingPathComponent("towns/town-manifest.json"))
        guard let pages = manifest["pages"]?.array else { throw PropertyServiceError.invalidResponse }
        var towns = pages.compactMap { item -> Municipality? in
            guard let row = item.object, let id = row["district"]?.string,
                  id.range(of: "^\\d{4}$", options: .regularExpression) != nil,
                  let name = row["name"]?.string, let county = row["county"]?.string else { return nil }
            return Municipality(id: id, name: name, county: county,
                sources: [SourceReference(id: "town-directory", title: "Watchdog municipal directory", url: "https://www.watchdogindex.com/town-compare", detail: "Municipal names and district identifiers from Watchdog's public town directory.")])
        }
        guard !towns.isEmpty else { throw PropertyServiceError.invalidResponse }
        let endpoint = configuration.backendBase.appendingPathComponent("functions/v1/chapter123-provider")
        var ratios: [String: JSONValue] = [:]
        var sourceURL = "https://www.nj.gov/treasury/taxation/lpt/lptvalue.shtml"
        var year: Int?
        // Provider contract is bounded to 500 districts. Keep the batches explicit.
        for offset in stride(from: 0, to: towns.count, by: 500) {
            let ids = towns[offset..<min(offset + 500, towns.count)].map { JSONValue.string($0.id) }
            let payload = try await document(endpoint: endpoint, body: ["districts": .array(ids)])
            guard let values = payload["districts"]?.object else { throw PropertyServiceError.invalidResponse }
            ratios.merge(values) { _, new in new }
            sourceURL = payload["source_url"]?.string ?? sourceURL; year = payload["tax_year"]?.integer
        }
        for index in towns.indices {
            if let percentage = ratios[towns[index].id]?["ratio"]?.number, percentage > 0, percentage <= 200 {
                towns[index].ratio = percentage / 100; towns[index].year = year
                towns[index].sources.append(SourceReference(id: "chapter123", title: "Certified Chapter 123 ratio", url: sourceURL, detail: "Published municipal assessment ratio for tax year \(year.map(String.init) ?? "unknown"). This is not an effective property-tax rate or a Watchdog Score."))
            }
        }
        towns.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        townCache = (Date(), towns)
        return towns
    }

    private func parcels(where predicate: String, geometry: Bool = false, extra: [String: String] = [:]) async throws -> [PropertyRecord] {
        var parameters = ["where": predicate, "outFields": Self.parcelFields, "returnGeometry": geometry ? "true" : "false",
                          "returnCentroid": "true", "outSR": "4326", "f": "json", "resultRecordCount": String(Self.resultLimit),
                          "orderByFields": "PROP_LOC ASC,PAMS_PIN ASC"]
        parameters.merge(extra) { _, new in new }
        let payload = try await document(endpoint: configuration.parcelEndpoint, query: parameters)
        guard let features = payload["features"]?.array else { throw PropertyServiceError.invalidResponse }
        let observed = Date()
        var seen: Set<String> = []
        return features.compactMap { feature in
            guard var record = ParcelDecoder.decode(feature, observedAt: observed), seen.insert(record.id).inserted else { return nil }
            if payload["exceededTransferLimit"]?.bool == true {
                record.sources.append(SourceReference(id: "result-limit", title: "Search result limit", url: "https://www.watchdogindex.com/", detail: "This search returned the first \(Self.resultLimit) matching parcels. Add a street, town, or block and lot to narrow the search."))
            }
            return record
        }
    }

    private func spatialQuery(latitude: Double, longitude: Double, distance: Double) async throws -> [PropertyRecord] {
        guard Self.isNewJerseyRegion(latitude: latitude, longitude: longitude) else { return [] }
        return try await parcels(where: "PAMS_PIN IS NOT NULL", extra: [
            "geometry": "\(longitude),\(latitude)", "geometryType": "esriGeometryPoint", "inSR": "4326",
            "spatialRel": "esriSpatialRelIntersects", "distance": String(distance), "units": "esriSRUnit_Meter"
        ])
    }

    private func geocode(_ text: String) async throws -> GeoPoint? {
        let payload = try await document(endpoint: configuration.geocodeEndpoint, query: [
            "SingleLine": text, "outFields": "Addr_type", "outSR": "4326", "maxLocations": "3", "f": "json"
        ])
        guard let candidates = payload["candidates"]?.array else { throw PropertyServiceError.invalidResponse }
        for row in candidates {
            guard let score = row["score"]?.number, score >= 90,
                  let x = row["location"]?["x"]?.number, let y = row["location"]?["y"]?.number,
                  Self.isNewJerseyRegion(latitude: y, longitude: x) else { continue }
            // Do not turn a town/ZIP geocoder centroid into an arbitrary address match.
            let type = row["attributes"]?["Addr_type"]?.string ?? ""
            guard ["PointAddress", "StreetAddress", "Subaddress", "StreetInt"].contains(type) else { continue }
            return GeoPoint(latitude: y, longitude: x)
        }
        return nil
    }

    private func chapterRatio(district: String) async throws -> JSONValue? {
        guard district.range(of: "^\\d{4}$", options: .regularExpression) != nil else { return nil }
        return try await optionalDocument(endpoint: configuration.backendBase.appendingPathComponent("functions/v1/chapter123-provider"), query: ["district": district])
    }

    private func attachScores(to properties: [PropertyRecord]) async throws -> [PropertyRecord] {
        guard !properties.isEmpty else { return properties }
        var results = properties
        let endpoint = configuration.backendBase.appendingPathComponent("rest/v1/rpc/get_public_property_watchdog_score_details")
        for offset in stride(from: 0, to: results.count, by: 100) {
            let end = min(offset + 100, results.count)
            let ids = results[offset..<end].map { JSONValue.string($0.id) }
            guard let payload = try await optionalDocument(endpoint: endpoint, body: ["p_pins": .array(ids)], apiKey: true),
                  let rows = payload.array else { continue }
            var byID: [String: [String: JSONValue]] = [:]
            for row in rows { if let object = row.object, let id = object["pams_pin"]?.string { byID[id] = object } }
            for index in offset..<end {
                if let score = byID[results[index].id] { Self.applyScore(score, to: &results[index]) }
            }
        }
        try Task.checkCancellation()
        return results
    }

    private static func applyScore(_ row: [String: JSONValue], to property: inout PropertyRecord) {
        guard row["model_version"]?.string == "ROBUST-v1", let score = row["watchdog_score"]?.number,
              score.isFinite, (0...100).contains(score) else { return }
        property.watchdogScore = score; property.scoreModel = "ROBUST-v1"
        property.scoreObservedAt = SourceDate.parseTimestamp(row["observed_at"]?.string)
        property.scoreEvidenceCoverage = row["evidence_coverage"]?.number.flatMap { (0...100).contains($0) ? $0 : nil }
        let descriptors: [(String, String, Double)] = [
            ("recourse", "Recourse", 0.10), ("overassessment", "Overassessment Position", 0.20),
            ("burden", "Burden", 0.30), ("uniformity", "Uniformity", 0.15),
            ("stability", "Stability", 0.15), ("trajectory", "Trajectory", 0.10)
        ]
        property.scoreComponents = descriptors.map { id, title, weight in
            ScoreComponent(id: id, title: title, score: row[id + "_score"]?.number.flatMap { (0...100).contains($0) ? $0 : nil }, weight: weight)
        }
        property.sources.removeAll { $0.id == "watchdog-score" }
        property.sources.append(SourceReference(id: "watchdog-score", title: "Watchdog Score · ROBUST-v1", url: "https://www.watchdogindex.com/data-methodology", detail: "Canonical Watchdog-derived score returned by the public score-details service. Read its components, coverage and observation date with the result. It is not an appraisal or a government finding."))
    }

    private func optionalDocument(endpoint: URL, query: [String: String] = [:], body: [String: JSONValue]? = nil, apiKey: Bool = false) async throws -> JSONValue? {
        do { return try await document(endpoint: endpoint, query: query, body: body, apiKey: apiKey) }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation(); return nil }
    }

    private func document(endpoint: URL, query: [String: String] = [:], body: [String: JSONValue]? = nil, apiKey: Bool = false) async throws -> JSONValue {
        try Task.checkCancellation()
        guard endpoint.scheme == "https", var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw PropertyServiceError.invalidConfiguration }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw PropertyServiceError.invalidConfiguration }
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("watchdog-native/1.0", forHTTPHeaderField: "X-Client-Info")
        if apiKey {
            guard configuration.publishableKey.hasPrefix("sb_publishable_") else { throw PropertyServiceError.invalidConfiguration }
            request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        }
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        do {
            let (bytes, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard (200...299).contains(response.statusCode) else { throw PropertyServiceError.httpStatus(response.statusCode) }
            guard bytes.count <= 15_000_000 else { throw PropertyServiceError.invalidResponse }
            data = bytes
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw PropertyServiceError.timeout }
            throw PropertyServiceError.networkUnavailable
        }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw PropertyServiceError.invalidResponse }
        if let error = value["error"] {
            throw PropertyServiceError.sourceFailure(error["code"]?.integer ?? 0)
        }
        return value
    }

    static func isNewJerseyRegion(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (38.8...41.4).contains(latitude) && (-75.7 ... -73.8).contains(longitude)
    }
    private static func distance(_ property: PropertyRecord, _ latitude: Double, _ longitude: Double) -> Double {
        guard let lat = property.latitude, let lon = property.longitude else { return .infinity }
        return pow(lat - latitude, 2) + pow((lon - longitude) * cos(latitude * .pi / 180), 2)
    }
}
