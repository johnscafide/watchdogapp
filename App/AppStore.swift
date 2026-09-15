import Foundation
import Observation
import SwiftUI
import WatchdogCore

enum AppTab: String, CaseIterable, Identifiable {
    case explore, workspace, saved, atlas
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explore: return "Explore"
        case .workspace: return "My Watchdog"
        case .saved: return "Saved"
        case .atlas: return "Towns"
        }
    }
    var symbol: String {
        switch self {
        case .explore: return "map"
        case .workspace: return "house"
        case .saved: return "bookmark"
        case .atlas: return "building.2"
        }
    }
}

struct DeviceLibrary: Codable {
    var properties: [PropertyRecord] = []
    var searches: [SavedSearch] = []
    var notes: [String: String] = [:]
}

struct LibraryArchive: Codable {
    var formatVersion = 1
    var live = DeviceLibrary()
    var sample = DeviceLibrary()
}

/// Shared by every native scene. All observable mutations stay on the main actor.
/// Live and sample libraries are physically separate in the archive to prevent data mixing.
@MainActor @Observable final class AppStore {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            lastNearbyCenter = nil
            lastRequestedQuery = nil
            searchGeneration = UUID()
            isLoading = false
            results = []
            errorMessage = nil
        }
    }
    var results: [PropertyRecord] = []
    var isLoading = false
    var isLoadingDetail = false
    var isLoadingMunicipalities = false
    var errorMessage: String?
    var detailError: String?
    var municipalityError: String?
    var storageError: String?
    private(set) var mode: DataMode
    var selectedProperty: PropertyRecord?
    var selectedTab: AppTab = .explore
    var comparisonIDs = Set<String>()
    var municipalities: [Municipality] = []
    var filters = PropertyFilters()
    var sort: PropertySort = .relevance
    var hasCompletedOnboarding: Bool
    var appearance: String { didSet { preferences.set(appearance, forKey: "appearance") } }

    private var archive: LibraryArchive
    private var searchGeneration = UUID()
    private var detailGeneration = UUID()
    private var municipalityGeneration = UUID()
    private var comparedRecords: [String: PropertyRecord] = [:]
    private var lastNearbyCenter: (latitude: Double, longitude: Double)?
    private var lastRequestedQuery: String?
    private var completedSearch = false
    private var preservingUnreadableArchive = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let libraryURL: URL
    @ObservationIgnored private let liveService: any PropertyService
    @ObservationIgnored private let sampleService: any PropertyService

    var savedProperties: [PropertyRecord] {
        get { mode == .live ? archive.live.properties : archive.sample.properties }
        set {
            if mode == .live { archive.live.properties = newValue }
            else { archive.sample.properties = newValue }
            persist()
        }
    }
    var savedSearches: [SavedSearch] {
        get { mode == .live ? archive.live.searches : archive.sample.searches }
        set {
            if mode == .live { archive.live.searches = newValue }
            else { archive.sample.searches = newValue }
            persist()
        }
    }
    var notes: [String: String] {
        mode == .live ? archive.live.notes : archive.sample.notes
    }
    var filteredResults: [PropertyRecord] { sort.apply(to: results.filter(filters.matches)) }
    var isAreaSearch: Bool { lastNearbyCenter != nil }
    var comparisonProperties: [PropertyRecord] {
        comparisonIDs.compactMap { comparedRecords[$0] }.sorted { $0.address < $1.address }
    }
    var preferredColorScheme: ColorScheme? {
        appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }
    private var service: any PropertyService { mode == .live ? liveService : sampleService }

    init(
        preferences: UserDefaults = .standard,
        libraryURL: URL? = nil,
        liveService: any PropertyService = WatchdogPropertyService(),
        sampleService: any PropertyService = SamplePropertyService()
    ) {
        self.preferences = preferences
        self.liveService = liveService
        self.sampleService = sampleService
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Watchdog", isDirectory: true)
        self.libraryURL = libraryURL ?? directory.appendingPathComponent("library-v1.json")
        #if DEBUG
        mode = DataMode(rawValue: preferences.string(forKey: "dataMode") ?? "live") ?? .live
        #else
        mode = .live
        #endif
        hasCompletedOnboarding = preferences.bool(forKey: "onboardingComplete")
        appearance = preferences.string(forKey: "appearance") ?? "system"
        archive = LibraryArchive()
        if FileManager.default.fileExists(atPath: self.libraryURL.path) {
            do {
                let data = try Data(contentsOf: self.libraryURL)
                let decoded = try JSONDecoder().decode(LibraryArchive.self, from: data)
                guard decoded.formatVersion == 1 else { throw LibraryError.unsupportedVersion }
                archive = decoded
            } catch {
                preservingUnreadableArchive = true
                storageError = "Your saved library could not be opened. The original file has been preserved. Export a backup before making changes."
            }
        }
    }

    func search() async {
        lastNearbyCenter = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastRequestedQuery = text
        completedSearch = false
        let generation = UUID()
        searchGeneration = generation
        isLoading = true
        errorMessage = nil
        // Remove old hits immediately so failed searches never masquerade as current results.
        results = []
        let currentService = service
        do {
            let records: [PropertyRecord]
            if text.isEmpty {
                records = try await currentService.nearby(latitude: 39.897, longitude: -75.033, radiusMeters: 1500)
            } else {
                records = try await currentService.search(text)
            }
            try Task.checkCancellation()
            guard searchGeneration == generation else { return }
            results = unique(records)
            completedSearch = true
            isLoading = false
        } catch {
            guard searchGeneration == generation else { return }
            isLoading = false
            if !(error is CancellationError), !Task.isCancelled { errorMessage = userFacing(error) }
        }
    }

    /// Avoids re-running the same request on view re-entry or a late debounce task.
    func searchIfNeeded() async {
        guard lastNearbyCenter == nil else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lastRequestedQuery != text || (!isLoading && !completedSearch && errorMessage == nil) else { return }
        await search()
    }

    func search(_ value: String) async {
        selectedTab = .explore
        query = value
        // Explorer debounces query changes; this immediate call also supports saved-search actions.
        await search()
    }

    func searchNearby(latitude: Double, longitude: Double) async {
        query = ""
        lastNearbyCenter = (latitude, longitude)
        let generation = UUID()
        searchGeneration = generation
        isLoading = true
        errorMessage = nil
        results = []
        do {
            let records = try await service.nearby(latitude: latitude, longitude: longitude, radiusMeters: 1500)
            try Task.checkCancellation()
            guard searchGeneration == generation else { return }
            results = unique(records)
            isLoading = false
        } catch {
            guard searchGeneration == generation else { return }
            isLoading = false
            if !(error is CancellationError), !Task.isCancelled { errorMessage = userFacing(error) }
        }
    }

    func retrySearch() async {
        if let center = lastNearbyCenter {
            await searchNearby(latitude: center.latitude, longitude: center.longitude)
        } else {
            await search()
        }
    }

    func select(_ property: PropertyRecord) async {
        selectedProperty = property
        await refreshSelected()
    }

    func refreshSelected() async {
        guard let property = selectedProperty else { return }
        let generation = UUID()
        detailGeneration = generation
        isLoadingDetail = true
        detailError = nil
        do {
            let detail = try await service.detail(for: property)
            try Task.checkCancellation()
            guard generation == detailGeneration, selectedProperty?.id == property.id else { return }
            selectedProperty = detail
            if let index = results.firstIndex(where: { $0.id == detail.id }) { results[index] = detail }
            if let index = savedProperties.firstIndex(where: { $0.id == detail.id }) {
                var saved = savedProperties
                saved[index] = detail
                savedProperties = saved
            }
            if comparisonIDs.contains(detail.id) { comparedRecords[detail.id] = detail }
            isLoadingDetail = false
        } catch {
            guard generation == detailGeneration else { return }
            isLoadingDetail = false
            if !(error is CancellationError), !Task.isCancelled {
                detailError = "The saved record is available. Additional details could not be refreshed. " + userFacing(error)
            }
        }
    }

    func loadMunicipalities() async {
        let generation = UUID()
        municipalityGeneration = generation
        isLoadingMunicipalities = true
        municipalityError = nil
        do {
            let rows = try await service.municipalities()
            try Task.checkCancellation()
            guard generation == municipalityGeneration else { return }
            municipalities = rows
            isLoadingMunicipalities = false
        } catch {
            guard generation == municipalityGeneration else { return }
            isLoadingMunicipalities = false
            if !(error is CancellationError), !Task.isCancelled { municipalityError = userFacing(error) }
        }
    }

    func setMode(_ value: DataMode) async {
        guard mode != value else { return }
        searchGeneration = UUID()
        detailGeneration = UUID()
        municipalityGeneration = UUID()
        mode = value
        preferences.set(value.rawValue, forKey: "dataMode")
        query = ""
        lastNearbyCenter = nil
        lastRequestedQuery = nil
        selectedProperty = nil
        comparisonIDs = []
        comparedRecords = [:]
        results = []
        municipalities = []
        filters = PropertyFilters()
        detailError = nil
        municipalityError = nil
        isLoadingDetail = false
        isLoadingMunicipalities = false
        await search()
    }

    func isSaved(_ property: PropertyRecord) -> Bool { savedProperties.contains { $0.id == property.id } }

    func toggleSaved(_ property: PropertyRecord) {
        guard property.isSample == (mode == .sample) else { return }
        var values = savedProperties
        if let index = values.firstIndex(where: { $0.id == property.id }) { values.remove(at: index) }
        else { values.insert(property, at: 0) }
        savedProperties = values
    }

    func toggleComparison(_ property: PropertyRecord) {
        guard property.isSample == (mode == .sample) else { return }
        if comparisonIDs.contains(property.id) {
            comparisonIDs.remove(property.id)
            comparedRecords.removeValue(forKey: property.id)
        } else if comparisonIDs.count < 4 {
            comparisonIDs.insert(property.id)
            comparedRecords[property.id] = property
        }
    }

    func saveSearch() {
        guard !isAreaSearch else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var values = savedSearches
        values.removeAll { $0.query.localizedCaseInsensitiveCompare(text) == .orderedSame }
        values.insert(SavedSearch(id: UUID().uuidString, query: text, createdAt: Date()), at: 0)
        savedSearches = Array(values.prefix(40))
    }

    func deleteSavedSearch(_ search: SavedSearch) { savedSearches = savedSearches.filter { $0.id != search.id } }

    func updateNote(for id: String, text: String) {
        let bounded = String(text.prefix(20_000))
        if mode == .live { archive.live.notes[id] = bounded.isEmpty ? nil : bounded }
        else { archive.sample.notes[id] = bounded.isEmpty ? nil : bounded }
        persist()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        preferences.set(true, forKey: "onboardingComplete")
    }

    func clearLocalData() {
        archive = LibraryArchive()
        comparisonIDs = []
        comparedRecords = [:]
        storageError = nil
        preservingUnreadableArchive = false
        preferences.removeObject(forKey: "watchdog.recentSearches")
        persist()
    }

    func exportLibrary() throws -> Data {
        // Preserve a damaged archive for support/recovery rather than exporting an empty replacement.
        if preservingUnreadableArchive, FileManager.default.fileExists(atPath: libraryURL.path) {
            return try Data(contentsOf: libraryURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    func importLibrary(_ data: Data) throws {
        guard data.count <= 20_000_000 else { throw LibraryError.tooLarge }
        let imported = try JSONDecoder().decode(LibraryArchive.self, from: data)
        guard imported.formatVersion == 1 else { throw LibraryError.unsupportedVersion }
        guard imported.live.properties.allSatisfy({ !$0.isSample }),
              imported.sample.properties.allSatisfy({ $0.isSample }) else { throw LibraryError.mixedData }
        // Merge by stable parcel ID. Local notes win on conflicts, preserving work on this device.
        archive.live = merge(local: archive.live, incoming: imported.live)
        archive.sample = merge(local: archive.sample, incoming: imported.sample)
        storageError = nil
        preservingUnreadableArchive = false
        persist()
        if storageError != nil { throw LibraryError.writeFailed }
    }

    private func merge(local: DeviceLibrary, incoming: DeviceLibrary) -> DeviceLibrary {
        var merged = local
        merged.properties = unique(local.properties + incoming.properties)
        var seen = Set(local.searches.map { $0.query.lowercased() })
        merged.searches += incoming.searches.filter { seen.insert($0.query.lowercased()).inserted }
        merged.searches = Array(merged.searches.prefix(40))
        merged.notes.merge(incoming.notes) { local, _ in local }
        return merged
    }

    private func unique(_ records: [PropertyRecord]) -> [PropertyRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }
    }

    private func persist() {
        // Do not overwrite an unreadable original on incidental UI edits.
        guard !preservingUnreadableArchive else { return }
        do {
            try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(archive)
            try data.write(to: libraryURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            storageError = nil
        } catch {
            storageError = "Changes are in memory but could not be saved on this device. Export your library to keep a copy."
        }
    }

    private func userFacing(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return "You’re offline. Saved property records and notes are still available."
            case .timedOut: return "The property service took too long. Please try again."
            default: return "The property service is unavailable. Please try again shortly."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "This request could not be completed. Please try again."
    }
}

enum LibraryError: LocalizedError {
    case unsupportedVersion, tooLarge, mixedData, writeFailed
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This backup uses an unsupported library format."
        case .tooLarge: return "Choose a Watchdog backup smaller than 20 MB."
        case .mixedData: return "This backup mixes sample and public records and could not be imported."
        case .writeFailed: return "The imported library could not be saved. Free device space and try again."
        }
    }
}
