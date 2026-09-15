import SwiftUI
import UniformTypeIdentifiers
import WatchdogCore

struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: LibraryDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var confirmingClear = false
    @State private var message: String?
    @State private var changingMode = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack(spacing: 14) {
                    WatchdogEmblem().fill(WDTheme.accent, style: FillStyle(eoFill: true)).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your research. Your space.").font(.headline)
                        Text("Free to explore. No account needed.").font(.subheadline).foregroundStyle(WDTheme.muted)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                Picker("Appearance", selection: $store.appearance) {
                    Text("Match device").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } header: { Text("Make yourself at home") }

            Section {
                LabeledContent("Saved properties", value: "\(store.savedProperties.count)")
                LabeledContent("Saved searches", value: "\(store.savedSearches.count)")
                Button {
                    do {
                        exportDocument = LibraryDocument(data: try store.exportLibrary())
                        showingExporter = true
                    } catch { message = error.localizedDescription }
                } label: { Label("Export library backup", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("settings.export")
                Button { showingImporter = true } label: { Label("Import library backup", systemImage: "square.and.arrow.down") }
                Button(role: .destructive) { confirmingClear = true } label: { Text("Clear all data on this device") }
                if let error = store.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
            } header: { Text("Your device library") } footer: {
                Text("Saved properties, searches, and notes stay in this app’s protected device storage. Backups include your private notes. Export to Files to move research between iPhone and iPad. Cloud account sync is not enabled.")
            }

            Section {
                NavigationLink { ResearchGuideView() } label: { Label("Understanding the numbers", systemImage: "book.closed") }
                Link(destination: URL(string: "https://www.watchdogindex.com/data-methodology")!) {
                    Label("Watchdog methodology", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.watchdogindex.com/privacy")!) { Text("Privacy policy") }
                Link(destination: URL(string: "https://www.watchdogindex.com/terms")!) { Text("Terms of use") }
            } header: { Text("Clarity comes first") }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Watchdog Pro").font(.title2.weight(.semibold))
                    Text("A separate space for professional property tools.")
                        .font(.subheadline).foregroundStyle(WDTheme.muted)
                    Label("iPhone & iPad app coming soon", systemImage: "iphone.and.ipad")
                        .font(.caption.weight(.semibold))
                    if AppConfiguration.showsProWebsiteLink {
                        Link(destination: URL(string: "https://www.watchdogindex.com/pro")!) {
                            Label("Explore Pro on the website", systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                }.padding(.vertical, 8)
            }

            #if DEBUG
            Section {
                Picker("Data source", selection: Binding(get: { store.mode }, set: { newMode in
                    changingMode = true
                    Task { await store.setMode(newMode); changingMode = false }
                })) {
                    ForEach(DataMode.allCases, id: \.self) { value in Text(value.label).tag(value) }
                }.disabled(changingMode).accessibilityIdentifier("settings.dataMode")
                if changingMode { ProgressView("Changing data source…") }
            } header: { Text("Development") } footer: { Text("Sample records are fictional and stored separately. Live requests never fall back to samples. This switch appears only in Debug builds.") }
            #endif
            Section {
                LabeledContent("Version", value: "1.0 (1)")
                Text("Built for iPhone and iPad with SwiftUI and Apple Maps.")
                    .font(.footnote).foregroundStyle(WDTheme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(WDTheme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "Watchdog-library") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let size = attributes[.size] as? NSNumber, size.intValue > 20_000_000 { throw LibraryError.tooLarge }
                try store.importLibrary(Data(contentsOf: url))
                message = "Your research has been imported. Existing notes on this device were preserved."
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Clear your device library?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear properties, searches, and notes", role: .destructive) { store.clearLocalData() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes both the public-record library and sample library from this device. Export a backup first if you want to keep your notes.") }
        .alert("Watchdog", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

enum AppConfiguration {
    /// Configure for your App Store distribution/region after reviewing current Apple rules.
    /// This consumer binary never unlocks paid digital features or starts a checkout itself.
    static let showsProWebsiteLink = true
}

struct ResearchGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A clearer view\nof every number.")
                    .font(.system(.largeTitle, design: .serif)).foregroundStyle(WDTheme.ink)
                explanation("Assessment", symbol: "building.columns", text: "The value recorded by the municipality for tax purposes. It may differ substantially from what the property would sell for.")
                explanation("Recorded tax", symbol: "doc.text", text: "The billed tax amount supplied in the public assessment file. It is not a quote for this year’s bill. If the source does not provide a tax year, Watchdog says so.")
                explanation("Equalized assessment", symbol: "equal.circle", text: "Assessment divided by the published municipal ratio. This describes the value implied by an assessment; it is not a market valuation or an appraisal. The ratio’s year matters.")
                explanation("Recorded sales", symbol: "clock", text: "A deed record describes a past transfer. Family transfers and other non-market transactions may not be suitable valuation evidence. A past sale does not mean the home is listed today.")
                explanation("Watchdog Score", symbol: "shield.lefthalf.filled", text: "The Watchdog Score, powered by the ROBUST Framework, is a research signal. Missing scores remain unavailable. Read the source and evidence coverage before interpreting a score.")
                explanation("Property boundaries", symbol: "map", text: "Parcel lines are supplied by the public GIS service. They are useful research references, not a legal survey.")
                explanation("A date is not just a date", symbol: "calendar", text: "Assessment year, tax year, ratio year, source publication date, and retrieval time describe different things. Refreshing a record does not make its underlying data newer.")
                Link("Read Watchdog’s data methodology", destination: URL(string: "https://www.watchdogindex.com/data-methodology")!)
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                Text("Verify consequential decisions with the original records and an appropriately qualified professional.")
                    .font(.footnote).foregroundStyle(WDTheme.muted)
            }.padding(24).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }.background(WDTheme.canvas).navigationTitle("Research guide").navigationBarTitleDisplayMode(.inline)
    }

    private func explanation(_ title: String, symbol: String, text: String) -> some View {
        WDCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(WDTheme.ink)
                Text(text).font(.body).foregroundStyle(WDTheme.muted).lineSpacing(3)
            }
        }
    }
}
