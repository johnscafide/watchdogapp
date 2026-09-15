import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import WatchdogCore

struct StubResponse: Sendable {
    let status: Int
    let body: String
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
}

actor MockTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> StubResponse
    init(handler: @escaping @Sendable (URLRequest) throws -> StubResponse) { self.handler = handler }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let stub = try handler(request)
        return (Data(stub.body.utf8), HTTPURLResponse(url: request.url!, statusCode: stub.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
    func snapshot() -> [URLRequest] { requests }
}

enum Fixtures {
    static let pin = "0417_12_3"
    static let feature = #"{"attributes":{"PAMS_PIN":"0417_12_3","PROP_LOC":"12 TEST ST","MUN_NAME":"HADDONFIELD BORO","COUNTY":"CAMDEN","PCLBLOCK":"12","PCLLOT":"3","PROP_CLASS":"2","NET_VALUE":"420000","LAND_VAL":170000,"IMPRVT_VAL":250000,"LAST_YR_TX":"12456.78","SALE_PRICE":"550000","DEED_DATE":"231201","YR_CONSTR":"1920","CALC_ACRE":0.24,"PCL_PBDATE":1735689600000,"OWNER_NAME":"EXCLUDED","ZIP5":"99999"},"centroid":{"x":-75.035,"y":39.898},"geometry":{"rings":[[[-75.035,39.898],[-75.034,39.898],[-75.034,39.899],[-75.035,39.898]]]}}"#
    static let parcels = "{\"features\":[\(feature)]}"
    static let ratio = #"{"district":"0417","tax_year":2026,"data":{"ratio":68.42},"source_url":"https://www.nj.gov/treasury/taxation/pdf/lpt/chap123/2026CH123.pdf"}"#
    static let score = #"[{"pams_pin":"0417_12_3","watchdog_score":72.5,"model_version":"ROBUST-v1","observed_at":"2026-08-20T12:00:00Z","evidence_coverage":81,"burden_score":64,"recourse_score":90}]"#
    static func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
