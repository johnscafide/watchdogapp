import SwiftUI
import WatchdogCore

enum RecordFormat {
    static func number(_ value: Double?, suffix: String = "") -> String {
        guard let value, value.isFinite else { return "Not reported" }
        return value.formatted(.number.precision(.fractionLength(0...2))) + suffix
    }

    static func year(_ value: Int?) -> String {
        value.map(String.init) ?? "Not reported"
    }

    static func date(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Not reported" }
        let day = String(value.prefix(10))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    static func sum(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        return valid.isEmpty ? nil : valid.reduce(0, +)
    }
}

struct RecordDataLabel: View {
    let isSample: Bool

    var body: some View {
        Label(isSample ? "Sample record · for exploring the app" : "Public record · verify with the source",
              systemImage: isSample ? "sparkles.rectangle.stack" : "checkmark.shield")
            .font(.caption.weight(.medium))
            .foregroundStyle(WDTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RecordFact: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).foregroundStyle(WDTheme.muted)
                    Text(value).foregroundStyle(WDTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title).foregroundStyle(WDTheme.muted)
                    Spacer(minLength: 12)
                    Text(value).multilineTextAlignment(.trailing).foregroundStyle(WDTheme.ink)
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

struct FeatureActionRow: View {
    let title: String
    let message: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .background(WDTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(WDTheme.ink)
                    Text(message).font(.subheadline).foregroundStyle(WDTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(WDTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
