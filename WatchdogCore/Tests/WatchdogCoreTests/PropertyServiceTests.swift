import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import WatchdogCore

final class PropertyServiceTests: XCTestCase {
    func testPublicSearchDecodesRecordAndCanonicalScoreWithoutOwnerProjection() async throws {
        let transport = MockTransport { request in
            request.url!.path.hasSuffix("/query") ? StubResponse(Fixtures.parcels) : StubResponse(Fixtures.score)
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("12 Test St, Haddonfield")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, Fixtures.pin)
        XCTAssertEqual(row.assessment, 420_000)
        XCTAssertEqual(row.taxAmount, 12_456.78)
        XCTAssertEqual(row.watchdogScore, 72.5)
        XCTAssertEqual(row.scoreModel, "ROBUST-v1")
        XCTAssertEqual(row.scoreComponents.count, 6)
        XCTAssertEqual(row.scoreEvidenceCoverage, 81)
        XCTAssertNotNil(row.scoreObservedAt)
        XCTAssertNil(row.taxYear)
        XCTAssertNil(row.assessmentYear)
        XCTAssertNil(row.livingArea)
        XCTAssertEqual(row.postalCode, "") // ZIP5 describes owner mailing data in this feed.
        XCTAssertFalse(row.isSample)
        XCTAssertTrue(row.history.isEmpty)
        XCTAssertEqual(row.sales.first?.date, "2023-12-01")
        XCTAssertFalse(try XCTUnwrap(row.sales.first).usable)
        let requests = await transport.snapshot()
        XCTAssertEqual(requests.count, 2)
        let parcelRequest = try XCTUnwrap(requests.first)
        let fields = try XCTUnwrap(Fixtures.query(parcelRequest, "outFields"))
        XCTAssertFalse(fields.contains("OWNER"))
        XCTAssertFalse(fields.contains("ZIP5"))
        XCTAssertFalse(fields.contains("*"))
        XCTAssertEqual(Fixtures.query(parcelRequest, "resultRecordCount"), "200")
        let scoreRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(scoreRequest.httpMethod, "POST")
        XCTAssertTrue(scoreRequest.value(forHTTPHeaderField: "apikey")?.hasPrefix("sb_publishable_") == true)
        XCTAssertNil(scoreRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testScoreIsUnavailableForUnknownModelAndInvalidNumber() async throws {
        for score in [
            #"[{"pams_pin":"0417_12_3","watchdog_score":78,"model_version":"experimental"}]"#,
            #"[{"pams_pin":"0417_12_3","watchdog_score":101,"model_version":"ROBUST-v1"}]"#,
            #"[{"pams_pin":"0417_12_3","watchdog_score":null,"model_version":"ROBUST-v1"}]"#,
            #"[{"pams_pin":"9999_12_3","watchdog_score":88,"model_version":"ROBUST-v1"}]"#
        ] {
            let transport = MockTransport { request in
                request.url!.path.hasSuffix("/query") ? StubResponse(Fixtures.parcels) : StubResponse(score)
            }
            let rows = try await WatchdogPropertyService(transport: transport).search("Haddonfield")
            XCTAssertNil(rows.first?.watchdogScore)
        }
    }

    func testScoreOutagePreservesPublicParcelAndDoesNotBecomeSample() async throws {
        let transport = MockTransport { request in
            request.url!.path.hasSuffix("/query") ? StubResponse(Fixtures.parcels) : StubResponse("{}", status: 503)
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("Haddonfield")
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.watchdogScore)
        XCTAssertEqual(rows.first?.isSample, false)
    }

    func testHTTPAndArcGISErrorsRemainErrors() async throws {
        for (response, expected) in [
            (StubResponse("{}", status: 429), PropertyServiceError.httpStatus(429)),
            (StubResponse(#"{"error":{"code":400,"message":"Bad query"}}"#), .sourceFailure(400)),
            (StubResponse("not json"), .invalidResponse),
            (StubResponse("{}"), .invalidResponse)
        ] {
            let transport = MockTransport { _ in response }
            do {
                _ = try await WatchdogPropertyService(transport: transport).search("Haddonfield")
                XCTFail("Expected \(expected)")
            } catch { XCTAssertEqual(error as? PropertyServiceError, expected) }
        }
    }

    func testTimeoutAndCancellationAreDistinct() async throws {
        let timeout = MockTransport { _ in throw URLError(.timedOut) }
        do {
            _ = try await WatchdogPropertyService(transport: timeout).search("Haddonfield")
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? PropertyServiceError, .timeout) }
        let cancelled = MockTransport { request in
            if request.url!.path.hasSuffix("/query") { return StubResponse(Fixtures.parcels) }
            throw URLError(.cancelled)
        }
        do {
            _ = try await WatchdogPropertyService(transport: cancelled).search("Haddonfield")
            XCTFail("Cancellation must not be swallowed by optional score enrichment")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testDetailAttachesGeometryAndRatioWithoutGuessingEffectiveYears() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("/query") { return StubResponse(Fixtures.parcels) }
            if request.url!.path.hasSuffix("chapter123-provider") { return StubResponse(Fixtures.ratio) }
            return StubResponse(Fixtures.score)
        }
        let property = PropertyRecord(id: Fixtures.pin, address: "12 Test St")
        let row = try await WatchdogPropertyService(transport: transport).detail(for: property)
        XCTAssertEqual(row.ratioYear, 2026)
        XCTAssertNil(row.assessmentYear)
        XCTAssertNil(row.taxYear)
        XCTAssertEqual(try XCTUnwrap(row.municipalRatio), 0.6842, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(row.impliedValue), 420_000 / 0.6842, accuracy: 0.001)
        XCTAssertEqual(row.parcelRings.count, 1)
        let requests = await transport.snapshot()
        let parcel = try XCTUnwrap(requests.first { $0.url!.path.hasSuffix("/query") })
        XCTAssertEqual(Fixtures.query(parcel, "returnGeometry"), "true")
    }

    func testDetailRejectsMismatchedScoreAndRatioIdentities() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("/query") { return StubResponse(Fixtures.parcels) }
            if request.url!.path.hasSuffix("chapter123-provider") {
                return StubResponse(Fixtures.ratio.replacingOccurrences(of: "0417", with: "9999"))
            }
            return StubResponse(Fixtures.score.replacingOccurrences(of: "0417_12_3", with: "9999_12_3"))
        }
        let row = try await WatchdogPropertyService(transport: transport).detail(for: PropertyRecord(id: Fixtures.pin, address: "Test"))
        XCTAssertNil(row.watchdogScore)
        XCTAssertNil(row.municipalRatio)
        XCTAssertTrue(row.sources.contains { $0.id == "score-availability" })
        XCTAssertTrue(row.sources.contains { $0.id == "ratio-availability" })
    }

    func testLiveDetailNeverSubmitsSampleParcel() async throws {
        let transport = MockTransport { _ in StubResponse(Fixtures.parcels) }
        do {
            _ = try await WatchdogPropertyService(transport: transport).detail(for: SampleData.properties[0])
            XCTFail("Sample data must remain isolated")
        } catch { XCTAssertEqual(error as? PropertyServiceError, .propertyNotFound) }
        let requests = await transport.snapshot()
        XCTAssertTrue(requests.isEmpty)
    }

    func testGeocoderTownCentroidCannotBecomeAnAddressMatch() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("/query") { return StubResponse(#"{"features":[]}"#) }
            return StubResponse(#"{"candidates":[{"score":100,"location":{"x":-75.035,"y":39.898},"attributes":{"Addr_type":"Locality"}}]}"#)
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("Unknown Street")
        XCTAssertTrue(rows.isEmpty)
        let requests = await transport.snapshot()
        XCTAssertEqual(requests.count, 2)
    }

    func testAddressFallbackUsesSmallSpatialSearch() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("/query") {
                return Fixtures.query(request, "geometry") == nil ? StubResponse(#"{"features":[]}"#) : StubResponse(Fixtures.parcels)
            }
            if request.url!.path.hasSuffix("findAddressCandidates") {
                return StubResponse(#"{"candidates":[{"score":99,"location":{"x":-75.035,"y":39.898},"attributes":{"Addr_type":"PointAddress"}}]}"#)
            }
            return StubResponse("[]")
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("12 Test Street")
        XCTAssertEqual(rows.count, 1)
        let requests = await transport.snapshot()
        let spatial = try XCTUnwrap(requests.first { Fixtures.query($0, "geometry") != nil })
        XCTAssertEqual(Fixtures.query(spatial, "distance"), "20.0")
    }

    func testNearbyBoundsRadiusAndRejectsInvalidCoordinatesBeforeNetworking() async throws {
        let transport = MockTransport { request in
            request.url!.path.hasSuffix("/query") ? StubResponse(Fixtures.parcels) : StubResponse("[]")
        }
        let service = WatchdogPropertyService(transport: transport)
        do {
            _ = try await service.nearby(latitude: .nan, longitude: -75, radiusMeters: 100)
            XCTFail("Expected invalid location")
        } catch { XCTAssertEqual(error as? PropertyServiceError, .invalidLocation) }
        _ = try await service.nearby(latitude: 39.898, longitude: -75.035, radiusMeters: 100_000)
        let requests = await transport.snapshot()
        XCTAssertEqual(Fixtures.query(try XCTUnwrap(requests.first), "distance"), "10000.0")
    }

    func testDuplicateParcelsDeduplicateAndCarryTruncationNotice() async throws {
        let transport = MockTransport { request in
            request.url!.path.hasSuffix("/query")
                ? StubResponse("{\"features\":[\(Fixtures.feature),\(Fixtures.feature)],\"exceededTransferLimit\":true}") : StubResponse("[]")
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("Haddonfield")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].sources.contains { $0.id == "result-limit" })
    }

    func testScoresAreBatchedAtOneHundred() async throws {
        let features = (0..<101).map { Fixtures.feature.replacingOccurrences(of: Fixtures.pin, with: "0417_12_\($0)") }.joined(separator: ",")
        let transport = MockTransport { request in
            request.url!.path.hasSuffix("/query") ? StubResponse("{\"features\":[\(features)]}") : StubResponse("[]")
        }
        let rows = try await WatchdogPropertyService(transport: transport).search("Haddonfield")
        XCTAssertEqual(rows.count, 101)
        let requests = await transport.snapshot().filter { $0.httpMethod == "POST" }
        let sizes = try requests.map { request -> Int in
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: [String]]
            return try XCTUnwrap(body?["p_pins"]).count
        }
        XCTAssertEqual(sizes, [100, 1])
    }
}
