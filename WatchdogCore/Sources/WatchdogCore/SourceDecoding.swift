import Foundation

/// Flexible source decoding without coercing null, blank, invalid or nonfinite numbers into zero.
enum JSONValue: Codable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let x): try box.encode(x)
        case .array(let x): try box.encode(x)
        case .string(let x): try box.encode(x)
        case .number(let x): try box.encode(x)
        case .bool(let x): try box.encode(x)
        case .null: try box.encodeNil()
        }
    }
    var object: [String: JSONValue]? { if case .object(let x) = self { return x }; return nil }
    var array: [JSONValue]? { if case .array(let x) = self { return x }; return nil }
    var string: String? {
        switch self { case .string(let x): return x.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let x) where x.isFinite: return x.rounded() == x ? String(format: "%.0f", x) : String(x)
        default: return nil }
    }
    var number: Double? {
        let result: Double?
        switch self { case .number(let x): result = x
        case .string(let x): result = Double(x.trimmingCharacters(in: .whitespacesAndNewlines))
        default: result = nil }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    var integer: Int? { number.flatMap { $0 >= Double(Int.min) && $0 < Double(Int.max) && $0.rounded() == $0 ? Int($0) : nil } }
    var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    subscript(_ key: String) -> JSONValue? { object?[key] }
}

enum ParcelDecoder {
    static func decode(_ feature: JSONValue, observedAt: Date) -> PropertyRecord? {
        guard let a = feature["attributes"]?.object, let id = a["PAMS_PIN"]?.string, !id.isEmpty else { return nil }
        let source = SourceReference(id: "nj-parcel", title: "NJ Office of GIS · MOD-IV", url: "https://njgin.nj.gov/njgin/edata/parcels/", detail: "Official statewide parcel/MOD-IV public source. Tax is the source's last-year billed amount, not a current bill. The feed does not supply assessment or tax year, interior condition, living area, listing status or a property-location ZIP. Parcel boundaries are approximate, not survey or legal boundaries. Retrieved date is not the record's effective date.")
        var record = PropertyRecord(id: id, address: a["PROP_LOC"]?.string ?? "", town: a["MUN_NAME"]?.string ?? "",
            county: a["COUNTY"]?.string ?? "", block: a["PCLBLOCK"]?.string ?? "", lot: a["PCLLOT"]?.string ?? "",
            qualifier: a["PCLQCODE"]?.string ?? "", assessment: nonnegative(a["NET_VALUE"]),
            landValue: nonnegative(a["LAND_VAL"]), improvementValue: nonnegative(a["IMPRVT_VAL"]),
            taxAmount: nonnegative(a["LAST_YR_TX"]), salePrice: positive(a["SALE_PRICE"]),
            saleDate: SourceDate.deedDate(a["DEED_DATE"]?.string), yearBuilt: a["YR_CONSTR"]?.integer.flatMap { (1600...2200).contains($0) ? $0 : nil },
            acres: positive(a["CALC_ACRE"]), propertyClass: a["PROP_CLASS"]?.string ?? "", updatedAt: observedAt,
            sources: [source], buildingDescription: a["BLDG_DESC"]?.string, landDescription: a["LAND_DESC"]?.string,
            sourcePublishedAt: positive(a["PCL_PBDATE"]).map { Date(timeIntervalSince1970: $0 / 1000) })
        if let x = feature["centroid"]?["x"]?.number, let y = feature["centroid"]?["y"]?.number,
           WatchdogPropertyService.isNewJerseyRegion(latitude: y, longitude: x) {
            record.latitude = y; record.longitude = x
        }
        if let rings = feature["geometry"]?["rings"]?.array {
            record.parcelRings = rings.compactMap { ring -> [GeoPoint]? in
                guard let points = ring.array else { return nil }
                let converted = points.compactMap { point -> GeoPoint? in
                    guard let pair = point.array, pair.count >= 2, let x = pair[0].number, let y = pair[1].number,
                          WatchdogPropertyService.isNewJerseyRegion(latitude: y, longitude: x) else { return nil }
                    return GeoPoint(latitude: y, longitude: x)
                }
                return converted.count >= 3 ? converted : nil
            }
        }
        if let date = record.saleDate, let price = record.salePrice {
            record.sales = [SaleRecord(id: id + ":" + date, date: date, price: price, usable: false,
                note: "Latest deed in the parcel source. Arm's-length usability has not been verified. Book \(a["DEED_BOOK"]?.string ?? "unavailable"), page \(a["DEED_PAGE"]?.string ?? "unavailable").")]
        }
        return record
    }
    private static func nonnegative(_ value: JSONValue?) -> Double? { value?.number.flatMap { $0 >= 0 ? $0 : nil } }
    private static func positive(_ value: JSONValue?) -> Double? { value?.number.flatMap { $0 > 0 ? $0 : nil } }
}

public enum SourceDate {
    /// NJ MOD-IV DEED_DATE is YYMMDD; accept explicit YYYYMMDD and ISO dates, too.
    public static func deedDate(_ input: String?) -> String? {
        guard let input else { return nil }
        let digits = input.filter(\.isNumber)
        let year: Int, month: Int, day: Int
        if digits.count == 6 {
            let parts = Array(digits)
            guard let y = Int(String(parts[0..<2])), let m = Int(String(parts[2..<4])), let d = Int(String(parts[4..<6])) else { return nil }
            // MOD-IV's two-digit year convention is ambiguous around the pivot; no fetch-year inference.
            year = y > 40 ? 1900 + y : 2000 + y; month = m; day = d
        } else if digits.count == 8 {
            let parts = Array(digits)
            guard let y = Int(String(parts[0..<4])), let m = Int(String(parts[4..<6])), let d = Int(String(parts[6..<8])) else { return nil }
            year = y; month = m; day = d
        } else { return nil }
        guard (1800...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value)
    }
}
