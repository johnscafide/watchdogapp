import XCTest
@testable import Watchdog
import WatchdogCore

@MainActor final class AppStoreTests: XCTestCase {
    private func makeStore(service: any PropertyService = StoreTestService()) -> (AppStore, URL) {
        let name = "watchdog-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json")
        return (AppStore(preferences: defaults, libraryURL: url, liveService: service, sampleService: service), url)
    }

    func testSavedPropertyAndPrivateNoteSurviveRestart() throws {
        let (store, url) = makeStore()
        let property = PropertyRecord(id: "0415_1_1", address: "A research record")
        store.toggleSaved(property)
        store.updateNote(for: property.id, text: "Verify the tax year with the township.")
        let reopened = AppStore(preferences: UserDefaults(suiteName: "watchdog-reopen-" + UUID().uuidString)!, libraryURL: url, liveService: StoreTestService())
        XCTAssertEqual(reopened.savedProperties.map(\.id), [property.id])
        XCTAssertEqual(reopened.notes[property.id], "Verify the tax year with the township.")
    }

    func testSampleAndLiveLibrariesStaySeparate() async {
        let (store, _) = makeStore()
        let live = PropertyRecord(id: "0415_1_1", address: "Public record")
        let sample = PropertyRecord(id: "sample-1", address: "Fictional record", isSample: true)
        store.toggleSaved(live)
        await store.setMode(.sample)
        XCTAssertTrue(store.savedProperties.isEmpty)
        store.toggleSaved(live)
        XCTAssertTrue(store.savedProperties.isEmpty)
        store.toggleSaved(sample)
        await store.setMode(.live)
        XCTAssertEqual(store.savedProperties.map(\.id), [live.id])
    }

    func testBackupMergePreservesLocalNoteAndRejectsMixedData() throws {
        let (store, _) = makeStore()
        let record = PropertyRecord(id: "0415_1_1", address: "Record")
        store.toggleSaved(record)
        store.updateNote(for: record.id, text: "Local work")
        var imported = LibraryArchive()
        imported.live.properties = [record, PropertyRecord(id: "0415_1_2", address: "Another")]
        imported.live.notes[record.id] = "Older work"
        try store.importLibrary(JSONEncoder().encode(imported))
        XCTAssertEqual(store.savedProperties.count, 2)
        XCTAssertEqual(store.notes[record.id], "Local work")
        imported.live.properties.append(PropertyRecord(id: "sample-1", address: "Sample", isSample: true))
        XCTAssertThrowsError(try store.importLibrary(JSONEncoder().encode(imported)))
        XCTAssertEqual(store.savedProperties.count, 2)
    }

    func testUnreadableArchiveIsPreservedUntilExplicitReset() throws {
        let (_, url) = makeStore()
        let damaged = Data("not-json".utf8)
        try damaged.write(to: url)
        let store = AppStore(preferences: UserDefaults(suiteName: "watchdog-recovery-" + UUID().uuidString)!, libraryURL: url, liveService: StoreTestService())
        XCTAssertNotNil(store.storageError)
        store.toggleSaved(PropertyRecord(id: "0415_1_1", address: "A record"))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        XCTAssertEqual(try store.exportLibrary(), damaged)
        store.clearLocalData()
        XCTAssertNil(store.storageError)
        XCTAssertNoThrow(try JSONDecoder().decode(LibraryArchive.self, from: Data(contentsOf: url)))
    }

    func testComparisonIsBoundedAndCanRemoveAtLimit() {
        let (store, _) = makeStore()
        let rows = (1...5).map { PropertyRecord(id: "0415_1_\($0)", address: "Record \($0)") }
        rows.forEach(store.toggleComparison)
        XCTAssertEqual(store.comparisonProperties.count, 4)
        store.toggleComparison(rows[0])
        store.toggleComparison(rows[4])
        XCTAssertEqual(Set(store.comparisonProperties.map(\.id)), Set(rows.dropFirst().map(\.id)))
    }

    func testLateResponseCannotReplaceNewSearch() async {
        let delayed = StoreTestService(delayFirst: true)
        let (store, _) = makeStore(service: delayed)
        let old = Task { await store.search("old") }
        await delayed.waitForOldRequest()
        await store.search("new")
        await delayed.releaseOldRequest()
        await old.value
        XCTAssertEqual(store.query, "new")
        XCTAssertEqual(store.results.first?.address, "new")
    }

    func testMapRetryRetainsAreaAndLateDebounceDoesNotOverride() async {
        let service = StoreTestService()
        let (store, _) = makeStore(service: service)
        await store.search("old address")
        await store.searchNearby(latitude: 40.1, longitude: -74.2)
        await store.searchIfNeeded()
        XCTAssertTrue(store.isAreaSearch)
        XCTAssertEqual(store.query, "")
        await store.retrySearch()
        let centers = await service.nearbyCenters
        XCTAssertEqual(centers.count, 2)
        XCTAssertEqual(centers.last?.0, 40.1)
        XCTAssertEqual(store.results.first?.address, "Area result")
    }

    func testFailureNeverDisplaysEarlierResultsOrSamples() async {
        let (store, _) = makeStore()
        await store.search("good")
        XCTAssertFalse(store.results.isEmpty)
        await store.search("fail")
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.mode, .live)
    }
}

private actor StoreTestService: PropertyService {
    private let delayFirst: Bool
    private var oldRequestStarted = false
    private var oldContinuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    var nearbyCenters: [(Double, Double)] = []
    init(delayFirst: Bool = false) { self.delayFirst = delayFirst }
    func search(_ query: String) async throws -> [PropertyRecord] {
        if query == "fail" { throw PropertyServiceError.networkUnavailable }
        if query == "old" && delayFirst {
            await withCheckedContinuation { continuation in
                oldContinuation = continuation
                oldRequestStarted = true
                observer?.resume(); observer = nil
            }
        }
        return [PropertyRecord(id: query, address: query)]
    }
    func waitForOldRequest() async {
        if oldRequestStarted { return }
        await withCheckedContinuation { observer = $0 }
    }
    func releaseOldRequest() { oldContinuation?.resume(); oldContinuation = nil }
    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [PropertyRecord] {
        nearbyCenters.append((latitude, longitude))
        return [PropertyRecord(id: "area", address: "Area result")]
    }
    func detail(for property: PropertyRecord) async throws -> PropertyRecord { property }
    func municipalities() async throws -> [Municipality] { [] }
}
