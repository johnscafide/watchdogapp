import XCTest
import Foundation
@testable import WatchdogCore

final class MunicipalityTests: XCTestCase {
    func testManifestAndRatiosAreCombinedAndCachedWithoutInventedMetrics() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("town-manifest.json") {
                return StubResponse(#"{"pages":[{"district":"0417","name":"Haddonfield","county":"Camden"},{"district":"0000","name":"Missing Ratio","county":"Test"},{"district":"bad","name":"Invalid","county":"Test"}]}"#)
            }
            return StubResponse(#"{"tax_year":2026,"districts":{"0417":{"ratio":68.42}},"source_url":"https://www.nj.gov/ratios.pdf"}"#)
        }
        let service = WatchdogPropertyService(transport: transport)
        let rows = try await service.municipalities()
        XCTAssertEqual(rows.count, 2)
        let town = try XCTUnwrap(rows.first { $0.id == "0417" })
        XCTAssertEqual(try XCTUnwrap(town.ratio), 0.6842, accuracy: 0.00001)
        XCTAssertEqual(town.year, 2026)
        XCTAssertNil(town.score)
        XCTAssertNil(town.effectiveTaxRate)
        XCTAssertNil(town.medianAssessment)
        XCTAssertNil(town.sampleSize)
        XCTAssertNil(rows.first { $0.id == "0000" }?.ratio)
        let again = try await service.municipalities()
        XCTAssertEqual(again, rows)
        let requests = await transport.snapshot()
        XCTAssertEqual(requests.count, 2)
    }

    func testMunicipalityBatchesNeverExceedProviderFiveHundredLimit() async throws {
        let pages = (1000..<1501).map { #"{"district":"\#($0)","name":"Town \#($0)","county":"Test"}"# }.joined(separator: ",")
        let transport = MockTransport { request in
            if request.url!.path.hasSuffix("town-manifest.json") { return StubResponse("{\"pages\":[\(pages)]}") }
            return StubResponse(#"{"tax_year":2026,"districts":{}}"#)
        }
        let towns = try await WatchdogPropertyService(transport: transport).municipalities()
        XCTAssertEqual(towns.count, 501)
        let requests = await transport.snapshot().filter { $0.httpMethod == "POST" }
        let sizes = try requests.map { request -> Int in
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: [String]]
            return try XCTUnwrap(body?["districts"]).count
        }
        XCTAssertEqual(sizes, [500, 1])
    }
}
