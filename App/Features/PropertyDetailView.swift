import SwiftUI
import MapKit
import WatchdogCore

struct PropertyDetailView: View {
    let property: PropertyRecord
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: DossierSection = .overview
    @State private var exportedFile: ExportedDossier?
    @State private var exportError: String?
    @State private var comparisonLimit = false

    private var record: PropertyRecord {
        if let selected = store.selectedProperty, selected.id == property.id { return selected }
        return property
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PropertyMapHero(property: record)
                    header
                    actions
                    sectionPicker
                    sectionContent
                    Text("Retrieved \(record.updatedAt.formatted(date: .abbreviated, time: .shortened)). Public records can lag changes to a property. Recorded sales are historical transactions, not current listings.")
                        .font(.caption).foregroundStyle(WDTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .background(WDTheme.canvas)
            .navigationTitle("Property record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Share PDF", systemImage: "doc.richtext") { exportPDF() }
                        ShareLink(item: DossierExport.text(for: record)) {
                            Label("Share text summary", systemImage: "text.alignleft")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share property record")
                }
            }
            .refreshable { await store.refreshSelected() }
            .sheet(item: $exportedFile) { file in
                DossierShareSheet(url: file.url)
                    .presentationDetents([.medium, .large])
            }
            .alert("Couldn’t create the PDF", isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "Try sharing the text summary instead.") }
            .alert("Compare up to four properties", isPresented: $comparisonLimit) {
                Button("OK", role: .cancel) { }
            } message: { Text("Remove a property from your comparison in Saved to add another.") }
        .tint(WDTheme.accent)
    }

    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Record section", selection: $section) {
                ForEach(DossierSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("dossier.section")
        } else {
            Picker("Record section", selection: $section) {
                ForEach(DossierSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dossier.section")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecordDataLabel(isSample: record.isSample)
            Text(record.displayAddress)
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .foregroundStyle(WDTheme.ink)
                .textSelection(.enabled)
            Text("\(record.town), NJ \(record.postalCode)")
                .font(.subheadline).foregroundStyle(WDTheme.muted)
            HStack(alignment: .center, spacing: 12) {
                WDScoreBadge(score: record.watchdogScore)
                Text(record.watchdogScore == nil
                     ? "A Watchdog Score is not available for this record."
                     : "The Watchdog Score, powered by the ROBUST Framework.")
                    .font(.caption).foregroundStyle(WDTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let observed = record.scoreObservedAt, record.watchdogScore != nil {
                Text("Score observed \(observed.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { saveButton; compareButton; directionsButton }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) { saveButton; compareButton }
                directionsButton
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var saveButton: some View {
        Button {
            store.toggleSaved(record)
        } label: {
            Label(store.isSaved(record) ? "Saved" : "Save", systemImage: store.isSaved(record) ? "bookmark.fill" : "bookmark")
        }
        .accessibilityIdentifier("dossier.save")
    }

    private var compareButton: some View {
        Button {
            if store.comparisonIDs.count >= 4 && !store.comparisonIDs.contains(record.id) {
                comparisonLimit = true
            } else { store.toggleComparison(record) }
        } label: {
            Label(store.comparisonIDs.contains(record.id) ? "Added" : "Compare", systemImage: "square.split.2x1")
        }
    }

    @ViewBuilder private var directionsButton: some View {
        if let coordinate = record.coordinate {
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                item.name = record.displayAddress
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .overview: PropertyOverview(property: record)
        case .history: PropertyHistory(property: record)
        case .sources: PropertySources(property: record)
        case .notes: PropertyNotes(property: record)
        }
    }

    private func exportPDF() {
        do { exportedFile = try DossierExport.pdf(for: record) }
        catch { exportError = "The report could not be saved. You can still share a text summary." }
    }
}

private enum DossierSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case history = "History"
    case sources = "Sources"
    case notes = "Notes"
    var id: String { rawValue }
}

private struct PropertyMapHero: View {
    let property: PropertyRecord

    var body: some View {
        Group {
            if let coordinate = property.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                ))) {
                    // Display the boundaries as lines: this preserves holes and separate
                    // rings without pretending an arbitrary ring order describes a fill.
                    ForEach(Array(property.parcelRings.enumerated()), id: \.offset) { _, ring in
                        if ring.count >= 3 {
                            MapPolyline(coordinates: ring.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .stroke(WDTheme.accent, lineWidth: 3)
                        }
                    }
                    Marker(property.displayAddress, coordinate: coordinate).tint(WDTheme.accent)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass(); MapScaleView() }
                .accessibilityLabel("Map location for \(property.displayAddress)")
                .overlay(alignment: .bottomLeading) {
                    Label(property.parcelRings.isEmpty ? "Reported location" : "Source parcel boundary · not a survey", systemImage: "map")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "map").font(.largeTitle)
                    Text("Location not reported").font(.headline)
                    Text("This source has no map coordinates.").font(.subheadline)
                }
                .foregroundStyle(WDTheme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WDTheme.surface)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}
