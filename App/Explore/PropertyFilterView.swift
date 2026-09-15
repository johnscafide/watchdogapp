import SwiftUI
import WatchdogCore

struct PropertyFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minimum: String
    @State private var maximum: String
    @State private var residentialOnly: Bool
    @State private var requireScore: Bool
    @State private var minimumScore: Double
    @FocusState private var focusedField: String?
    let apply: (PropertyFilters) -> Void

    init(filters: PropertyFilters, apply: @escaping (PropertyFilters) -> Void) {
        _minimum = State(initialValue: filters.minAssessment.map { String(format: "%.0f", $0) } ?? "")
        _maximum = State(initialValue: filters.maxAssessment.map { String(format: "%.0f", $0) } ?? "")
        _residentialOnly = State(initialValue: filters.residentialOnly)
        _requireScore = State(initialValue: filters.minScore != nil)
        let score = filters.minScore ?? 70
        _minimumScore = State(initialValue: score.isFinite ? min(100, max(0, score)) : 70)
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WDSectionHeader("A little more specific.", subtitle: "Filter the records returned by your current search.")
                    assessmentCard
                    propertyTypeCard
                    scoreCard
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.red)
                            .accessibilityLabel("Filter error: \(validationMessage)")
                    }
                    WDSourceLabel("Assessed value is the amount used for taxation. It is not a listing price or a market valuation. Records with missing values are excluded when a corresponding filter is active.")
                }
                .padding(22)
            }
            .background(WDTheme.canvas)
            .navigationTitle("Refine your search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("explorer.filters.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", action: reset).accessibilityIdentifier("explorer.filters.reset")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                WDPrimaryButton("Apply filters", symbol: "checkmark") { commit() }
                    .accessibilityIdentifier("explorer.filters.apply")
                    .disabled(validationMessage != nil)
                    .opacity(validationMessage == nil ? 1 : 0.45)
                    .padding(20)
                    .background(WDTheme.canvas)
            }
        }
        .tint(WDTheme.accent)
        .presentationDragIndicator(.visible)
    }

    private var assessmentCard: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("Assessed value", systemImage: "dollarsign.circle")
                    .font(.headline).foregroundStyle(WDTheme.ink)
                amountField("Minimum assessment", placeholder: "No minimum", identifier: "minimum", value: $minimum)
                amountField("Maximum assessment", placeholder: "No maximum", identifier: "maximum", value: $maximum)
            }
        }
    }

    private func amountField(_ title: String, placeholder: String, identifier: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(WDTheme.muted)
            HStack(spacing: 8) {
                Text("$").foregroundStyle(WDTheme.muted)
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: title)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(WDTheme.ink)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("explorer.filters.\(identifier)")
            }
            .padding(14)
            .background(WDTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var propertyTypeCard: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Residential properties only", isOn: $residentialOnly)
                    .accessibilityIdentifier("explorer.filters.residential")
                    .font(.headline).foregroundStyle(WDTheme.ink)
                Text("Uses the residential classification in the public record.")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            }
        }
    }

    private var scoreCard: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Minimum Watchdog Score", isOn: $requireScore)
                    .accessibilityIdentifier("explorer.filters.requireScore")
                    .font(.headline).foregroundStyle(WDTheme.ink)
                if requireScore {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Int(minimumScore).formatted()).font(.largeTitle.weight(.semibold)).monospacedDigit()
                        Text("and above").font(.subheadline).foregroundStyle(WDTheme.muted)
                    }
                    .foregroundStyle(WDTheme.ink)
                    Slider(value: $minimumScore, in: 0...100, step: 1)
                        .accessibilityLabel("Minimum Watchdog Score")
                        .accessibilityValue(Int(minimumScore).formatted())
                        .accessibilityIdentifier("explorer.filters.minimumScore")
                }
                Text("Only records with a published Watchdog Score will match this filter. Scores are unavailable for some properties.")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            }
        }
    }

    private var validationMessage: String? {
        if !minimum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(minimum) == nil {
            return "Enter a valid, nonnegative minimum assessment."
        }
        if !maximum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(maximum) == nil {
            return "Enter a valid, nonnegative maximum assessment."
        }
        if let min = amount(minimum), let max = amount(maximum), min > max {
            return "The maximum assessment must be at least the minimum."
        }
        return nil
    }

    private func amount(_ input: String) -> Double? {
        let clean = input.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(clean), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func reset() {
        minimum = ""
        maximum = ""
        residentialOnly = false
        requireScore = false
        minimumScore = 70
    }

    private func commit() {
        guard validationMessage == nil else { return }
        var filters = PropertyFilters()
        filters.minAssessment = amount(minimum)
        filters.maxAssessment = amount(maximum)
        filters.residentialOnly = residentialOnly
        filters.minScore = requireScore ? minimumScore : nil
        apply(filters)
        dismiss()
    }
}
