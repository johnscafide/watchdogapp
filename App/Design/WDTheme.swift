import SwiftUI
import UIKit
import MapKit
import WatchdogCore

/// Semantic colors are centralized so every screen can be restyled here.
enum WDTheme {
    static let ink = adaptive(light: 0x153C32, dark: 0xE5F2EB)
    static let accent = adaptive(light: 0x285B48, dark: 0xB9E99B)
    static let canvas = adaptive(light: 0xF5F4ED, dark: 0x101C18)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B2B24)
    static let muted = adaptive(light: 0x64746B, dark: 0xADBEB2)
    static let line = adaptive(light: 0xDDE4DB, dark: 0x34483D)
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.43)

    static func money(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static func compactMoney(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "$" + (value / 1_000_000).formatted(.number.precision(.fractionLength(0...2))) + "M"
        }
        if magnitude >= 1_000 {
            return "$" + (value / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "K"
        }
        return money(value)
    }

    /// Values passed here are ratios (0.25 is 25%), never already scaled percentages.
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0...2)))
    }

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension PropertyRecord {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
