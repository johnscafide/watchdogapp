import SwiftUI
import MapKit
import WatchdogCore

struct ExploreMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let properties: [PropertyRecord]
    let contextID: String
    let isLoading: Bool
    let isSample: Bool
    let focus: SearchLocation?
    let open: (PropertyRecord) -> Void
    let searchArea: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .region(Self.initialRegion)
    @State private var visibleCenter = Self.initialRegion.center
    @State private var hasMoved = false
    @State private var lastFittedContext: String?

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.897, longitude: -75.033),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.06)
    )

    private var mapped: [PropertyRecord] { Array(properties.filter { $0.coordinate != nil }.prefix(100)) }
    private var missingCoordinates: Int { properties.filter { $0.coordinate == nil }.count }

    var body: some View {
        Map(position: $position) {
            ForEach(mapped) { property in
                if let coordinate = property.coordinate {
                    Annotation(property.displayAddress, coordinate: coordinate, anchor: .bottom) {
                        Button { open(property) } label: {
                            PropertyMapPin(value: WDTheme.compactMoney(property.assessment))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(property.displayAddress), assessed value \(WDTheme.money(property.assessment))")
                        .accessibilityHint("Opens the property record")
                        .accessibilityIdentifier("explorer.map.record.\(property.id)")
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleCenter = context.region.center
            if position.positionedByUser { hasMoved = true }
        }
        .onChange(of: properties.map(\.id), initial: true) { _, _ in fitForNewSearch() }
        .onChange(of: focus, initial: true) { _, location in
            guard let location else { return }
            // Searching after a pan keeps the person's zoom level. A newly mounted map
            // still restores the selected center even when the service returned no pins.
            if abs(visibleCenter.latitude - location.latitude) < 0.000_001,
               abs(visibleCenter.longitude - location.longitude) < 0.000_001 {
                lastFittedContext = contextID
                hasMoved = false
                return
            }
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.035)
            )
            lastFittedContext = contextID
            hasMoved = false
            visibleCenter = region.center
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { position = .region(region) }
        }
        .overlay(alignment: .top) { searchAreaButton.padding(.top, 14) }
        .overlay(alignment: .bottomLeading) { mapCaption.padding(.leading, 12).padding(.bottom, 24) }
        .accessibilityLabel(isSample ? "Sample property map" : "Property assessment map")
        .accessibilityIdentifier("explorer.map")
    }

    private var searchAreaButton: some View {
        Button {
            hasMoved = false
            searchArea(visibleCenter)
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(WDTheme.ink) }
                else { Image(systemName: "arrow.clockwise") }
                Text(hasMoved ? "Search this area" : "Search near map center")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WDTheme.ink)
            .padding(.horizontal, 17)
            .frame(minHeight: 46)
            .background(WDTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(WDTheme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityHint("Finds available records near the map center. It does not search the entire visible region.")
        .accessibilityIdentifier("explorer.searchArea")
    }

    private var mapCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isSample ? "SAMPLE · ASSESSED VALUES" : "ASSESSED VALUES")
                .font(.caption2.weight(.bold)).tracking(0.7)
            if missingCoordinates > 0 {
                Text("\(missingCoordinates) record\(missingCoordinates == 1 ? "" : "s") without map coordinates")
                    .font(.caption2)
            }
            if mapped.count < properties.count - missingCoordinates {
                Text("First \(mapped.count) mapped records shown").font(.caption2)
            }
        }
        .foregroundStyle(WDTheme.ink)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(WDTheme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private func fitForNewSearch() {
        guard focus == nil, lastFittedContext != contextID, !mapped.isEmpty else { return }
        let coordinates = mapped.compactMap(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(180, max((maxLat - minLat) * 1.4, 0.012)),
                                   longitudeDelta: min(360, max((maxLon - minLon) * 1.4, 0.016)))
        )
        lastFittedContext = contextID
        hasMoved = false
        visibleCenter = region.center
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { position = .region(region) }
    }
}

#Preview("Explore map · Sample records") {
    ExploreMap(properties: SampleData.properties, contextID: "preview", isLoading: false,
               isSample: true, focus: nil, open: { _ in }, searchArea: { _ in })
}

private struct PropertyMapPin: View {
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(WDTheme.canvas)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(WDTheme.ink, in: Capsule())
                .overlay(Capsule().stroke(WDTheme.surface, lineWidth: 2))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            Circle().fill(WDTheme.ink).frame(width: 6, height: 6).padding(.top, 2)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}
