import XCTest
@testable import WatchdogCore

final class ModelAndSearchTests: XCTestCase {
    func testSearchNormalizesAddressAndEscapesApostrophes() throws {
        let query = try ParcelSearchQuery.predicate(for: "  12  O'Brien Street, Haddonfield NJ  ")
        XCTAssertTrue(query.contains("O''BRIEN"))
        XCTAssertTrue(query.contains("%ST%"))
        XCTAssertFalse(query.contains("OWNER"))
        XCTAssertTrue(query.contains(" AND "))
        XCTAssertEqual(ParcelSearchQuery.normalized("  Main\nStreet "), "MAIN STREET")
        XCTAssertTrue(try ParcelSearchQuery.predicate(for: "Jersey City").contains("%JERSEY%"))
        XCTAssertTrue(try ParcelSearchQuery.predicate(for: "New Brunswick").contains("%NEW%"))
        XCTAssertEqual(try ParcelSearchQuery.predicate(for: "Jersey City, New Jersey"),
                       try ParcelSearchQuery.predicate(for: "Jersey City"))
    }

    func testParcelIDAndBlockLotAreExactQueries() throws {
        XCTAssertEqual(try ParcelSearchQuery.predicate(for: "0417_12_3"), "PAMS_PIN = '0417_12_3'")
        XCTAssertEqual(try ParcelSearchQuery.predicate(for: "block 12 lot 3, Haddonfield"),
                       "PCLBLOCK = '12' AND PCLLOT = '3' AND UPPER(MUN_NAME) LIKE 'HADDONFIELD%'")
        XCTAssertThrowsError(try ParcelSearchQuery.predicate(for: "a"))
        XCTAssertThrowsError(try ParcelSearchQuery.predicate(for: String(repeating: "a", count: 181)))
        XCTAssertThrowsError(try ParcelSearchQuery.predicate(for: "%_"))
    }

    func testUnknownValuesNeverPassActiveMetricFilters() {
        let unknown = PropertyRecord(id: "unknown", address: "Unknown", propertyClass: "2")
        XCTAssertTrue(PropertyFilters().matches(unknown))
        XCTAssertFalse(PropertyFilters(minAssessment: 0).matches(unknown))
        XCTAssertFalse(PropertyFilters(maxAssessment: 1_000_000).matches(unknown))
        XCTAssertFalse(PropertyFilters(minScore: 0).matches(unknown))
        XCTAssertTrue(PropertyFilters(residentialOnly: true).matches(unknown))
        XCTAssertFalse(PropertyFilters(residentialOnly: true).matches(PropertyRecord(id: "land", address: "Land", propertyClass: "1")))
    }

    func testStableSortKeepsUnknownAndNonfiniteValuesLast() {
        let records = [
            PropertyRecord(id: "unknown", address: "Unknown"),
            PropertyRecord(id: "high", address: "High", assessment: 900_000),
            PropertyRecord(id: "low1", address: "Low 1", assessment: 100_000),
            PropertyRecord(id: "nan", address: "Not a number", assessment: .nan),
            PropertyRecord(id: "low2", address: "Low 2", assessment: 100_000)
        ]
        XCTAssertEqual(PropertySort.assessmentLow.apply(to: records).map(\.id), ["low1", "low2", "high", "unknown", "nan"])
        XCTAssertEqual(PropertySort.assessmentHigh.apply(to: records).map(\.id), ["high", "low1", "low2", "unknown", "nan"])
        XCTAssertEqual(PropertySort.relevance.apply(to: records).map(\.id), records.map(\.id))
    }

    func testImpliedValueRequiresValidPositiveEvidence() {
        var record = PropertyRecord(id: "test", address: "Test", assessment: 400_000, municipalRatio: 0.8)
        XCTAssertEqual(record.impliedValue, 500_000)
        record.municipalRatio = 0
        XCTAssertNil(record.impliedValue)
        record.municipalRatio = .infinity
        XCTAssertNil(record.impliedValue)
        record.municipalRatio = 0.8
        record.assessment = -.infinity
        XCTAssertNil(record.impliedValue)
    }

    func testDeedDatesRespectSourceYearOrderAndRealCalendar() {
        XCTAssertEqual(SourceDate.deedDate("231201"), "2023-12-01")
        XCTAssertEqual(SourceDate.deedDate("060115"), "2006-01-15")
        XCTAssertEqual(SourceDate.deedDate("991231"), "1999-12-31")
        XCTAssertEqual(SourceDate.deedDate("20240229"), "2024-02-29")
        XCTAssertEqual(SourceDate.deedDate("2024-02-29"), "2024-02-29")
        XCTAssertNil(SourceDate.deedDate("20230229"))
        XCTAssertNil(SourceDate.deedDate("000000"))
        XCTAssertNil(SourceDate.deedDate("2024")) // A year alone cannot become a precise sale date.
    }

    func testDecoderPreservesNullsAndIgnoresMailingData() throws {
        let bytes = Data(#"{"attributes":{"PAMS_PIN":"0417_1_2","PROP_LOC":"","PCLBLOCK":"1","PCLLOT":"2","NET_VALUE":"","LAST_YR_TX":null,"LAND_VAL":"NaN","IMPRVT_VAL":-5,"SALE_PRICE":0,"YR_CONSTR":"0","ZIP5":"10001","OWNER_NAME":"PRIVATE"},"centroid":{"x":0,"y":0}}"#.utf8)
        let row = try XCTUnwrap(ParcelDecoder.decode(JSONDecoder().decode(JSONValue.self, from: bytes), observedAt: SampleData.observedAt))
        XCTAssertNil(row.assessment)
        XCTAssertNil(row.taxAmount)
        XCTAssertNil(row.landValue)
        XCTAssertNil(row.improvementValue)
        XCTAssertNil(row.salePrice)
        XCTAssertNil(row.yearBuilt)
        XCTAssertNil(row.latitude)
        XCTAssertEqual(row.postalCode, "")
        XCTAssertEqual(row.displayAddress, "Block 1, lot 2")
        let encoded = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE"))
        XCTAssertFalse(encoded.contains("10001"))
    }

    func testPropertyRecordRoundTripsForLocalPersistence() throws {
        let input = SampleData.properties[0]
        let output = try JSONDecoder().decode(PropertyRecord.self, from: JSONEncoder().encode(input))
        XCTAssertEqual(output, input)
    }

    func testSampleServiceSearchNearbyAndDetailStayInSampleMode() async throws {
        let service = SamplePropertyService()
        let rows = try await service.search("Haddonfield")
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.isSample && $0.town == "Haddonfield" })
        let found = try await service.search("24 Lantern")
        XCTAssertEqual(found.map(\.id), ["sample-1"])
        let nearby = try await service.nearby(latitude: 39.8986, longitude: -75.0355, radiusMeters: 200)
        XCTAssertEqual(nearby.first?.id, "sample-1")
        XCTAssertFalse(nearby.contains { $0.town == "Princeton" })
        let detail = try await service.detail(for: SampleData.properties[0])
        XCTAssertTrue(detail.isSample)
        XCTAssertFalse(detail.history.isEmpty)
        do {
            _ = try await service.detail(for: PropertyRecord(id: "sample-1", address: "Live"))
            XCTFail("A live record must not be turned into sample evidence")
        } catch { XCTAssertEqual(error as? PropertyServiceError, .propertyNotFound) }
    }
}
