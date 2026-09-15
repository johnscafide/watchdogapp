import SwiftUI
import WatchdogCore

struct WDCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WDTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(WDTheme.line, lineWidth: 1))
    }
}

struct WDSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(WDTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(WDTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WDMetric: View {
    let title: String
    let value: String
    let detail: String?

    init(_ title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(WDTheme.muted)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(WDTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(WDTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WDScoreBadge: View {
    let score: Double?

    private var value: String {
        guard let score, score.isFinite, (0...100).contains(score) else { return "—" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text("SCORE").font(.caption2.weight(.bold)).tracking(0.7)
        }
        .foregroundStyle(WDTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WDTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value == "—" ? "Watchdog Score unavailable" : "Watchdog Score \(value)")
    }
}

/// Display-only content: callers supply a Button and their own context menu.
struct WDPropertyRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let property: PropertyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            addressLine
            Divider().overlay(WDTheme.line)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { figures }
                WDMetric("Watchdog Score", value: scoreText)
            } else {
                HStack(alignment: .top, spacing: 18) { figures }
            }
            footer
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WDTheme.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(WDTheme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var addressLine: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(property.displayAddress)
                    .font(.headline).foregroundStyle(WDTheme.ink)
                    .multilineTextAlignment(.leading)
                Text([property.town, property.postalCode].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(WDTheme.muted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { WDScoreBadge(score: property.watchdogScore) }
        }
    }

    @ViewBuilder private var figures: some View {
        WDMetric("Assessed value", value: WDTheme.compactMoney(property.assessment),
                 detail: property.assessmentYear.map { "Assessment year \($0)" })
        WDMetric("Annual tax", value: WDTheme.money(property.taxAmount),
                 detail: property.taxYear.map { "Tax year \($0)" })
    }

    private var scoreText: String {
        guard let score = property.watchdogScore, score.isFinite, (0...100).contains(score) else { return "Unavailable" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: property.isSample ? "flask" : "doc.text.magnifyingglass")
            Text(property.isSample ? "Sample property · Demonstration data" : "Public property record")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(WDTheme.muted)
    }
}

struct WDSourceLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption).foregroundStyle(WDTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct WDEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
                .foregroundStyle(WDTheme.accent)
                .frame(width: 72, height: 72)
                .background(WDTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(WDTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(.subheadline).foregroundStyle(WDTheme.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

struct WDPrimaryButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .foregroundStyle(WDTheme.canvas)
            .background(WDTheme.ink, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview("Property card · Light") {
    ScrollView {
        if let property = SampleData.properties.first {
            WDPropertyRow(property: property).padding()
        }
    }
    .background(WDTheme.canvas)
    .preferredColorScheme(.light)
}

#Preview("Property card · Accessible dark") {
    ScrollView {
        if let property = SampleData.properties.first {
            WDPropertyRow(property: property).padding()
        }
    }
    .background(WDTheme.canvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
