import SwiftUI
import WatchdogCore

struct PropertySources: View {
    let property: PropertyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WDSectionHeader("Follow the evidence", subtitle: "See where the record comes from and what it can tell you.")
            if property.watchdogScore != nil { scoreEvidence }
            if let published = property.sourcePublishedAt {
                WDSourceLabel("Property source published \(published.formatted(date: .abbreviated, time: .omitted)). This is separate from the assessment and tax years.")
            }
            if property.sources.isEmpty {
                WDCard {
                    WDEmptyState(title: "No source links supplied", message: "This record does not include a source URL. Verify the information with the municipal assessor.", symbol: "doc.text.magnifyingglass")
                }
            } else {
                ForEach(property.sources) { source in
                    WDCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(source.title, systemImage: "doc.text")
                                .font(.headline).foregroundStyle(WDTheme.ink)
                            Text(source.detail).font(.subheadline).foregroundStyle(WDTheme.muted)
                                .textSelection(.enabled)
                            if let url = RecordFormat.webURL(source.url) {
                                Link(destination: url) {
                                    Label("Open source", systemImage: "arrow.up.right.square")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(minHeight: 44)
                                }
                                Text(url.host ?? source.url).font(.caption).foregroundStyle(WDTheme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            WDCard {
                VStack(alignment: .leading, spacing: 12) {
                    WDSectionHeader("A little context helps")
                    Text("A missing value means it was not supplied by the available data. Watchdog does not fill gaps with guessed taxes, sale prices, or property characteristics.")
                    Text("Assessment year and tax year describe different records. Compare like years whenever possible, and confirm current amounts with the municipality.")
                    if property.isSample {
                        Text("You are viewing an illustrative sample. Sample records, charts, and figures are not evidence about a real property.").fontWeight(.medium)
                    }
                }
                .font(.subheadline).foregroundStyle(WDTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoreEvidence: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 16) {
                WDSectionHeader("Inside the Watchdog Score", subtitle: "Powered by the ROBUST Framework")
                HStack(alignment: .top, spacing: 16) {
                    WDScoreBadge(score: property.watchdogScore)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(property.scoreModel ?? "Model version not supplied").font(.subheadline.weight(.medium))
                        if let observed = property.scoreObservedAt {
                            Text("Observed \(observed.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(WDTheme.muted)
                        }
                        if let coverage = property.scoreEvidenceCoverage, coverage.isFinite {
                            Text("Evidence coverage: \(WDTheme.percent(coverage / 100))")
                                .font(.caption).foregroundStyle(WDTheme.muted)
                        }
                    }
                }
                if !property.scoreComponents.isEmpty {
                    Divider()
                    ForEach(property.scoreComponents) { component in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(component.title).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(component.score.map { RecordFormat.number($0) + " / 100" } ?? "Not reported")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(WDTheme.muted)
                            }
                            if let score = component.score, score.isFinite, (0...100).contains(score) {
                                ProgressView(value: score, total: 100).tint(WDTheme.accent)
                                    .accessibilityLabel(component.title)
                                    .accessibilityValue("\(RecordFormat.number(score)) out of 100")
                            }
                            Text("Model weight: \(WDTheme.percent(component.weight))")
                                .font(.caption2).foregroundStyle(WDTheme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("This is a Watchdog-derived indicator, not an appraisal or a government finding. Read the methodology with the observation date and available evidence.")
                    .font(.caption).foregroundStyle(WDTheme.muted)
            }
        }
    }
}

struct PropertyNotes: View {
    let property: PropertyRecord
    @Environment(AppStore.self) private var store
    @State private var note = ""
    @State private var isLoaded = false
    @FocusState private var editing: Bool

    var body: some View {
        WDCard {
            VStack(alignment: .leading, spacing: 16) {
                WDSectionHeader("Your notes", subtitle: "A place for questions, observations, and what to check next.")
                ZStack(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("What would you like to remember about this property?")
                            .foregroundStyle(WDTheme.muted)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $note)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .focused($editing)
                        .accessibilityLabel("Private property note")
                        .accessibilityIdentifier("dossier.note")
                }
                .font(.body)
                .padding(10)
                .background(WDTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                HStack(alignment: .top, spacing: 12) {
                    Label("Saved on this device. Notes are excluded from shared reports.", systemImage: "lock")
                        .font(.caption).foregroundStyle(WDTheme.muted)
                    Spacer(minLength: 0)
                    if editing { Button("Done") { editing = false }.font(.subheadline.weight(.semibold)) }
                }
                Text("\(note.count.formatted()) / 20,000 characters")
                    .font(.caption2).foregroundStyle(WDTheme.muted)
            }
        }
        .task(id: property.id) {
            isLoaded = false
            note = store.notes[property.id] ?? ""
            isLoaded = true
        }
        .onChange(of: note) { _, value in
            guard isLoaded else { return }
            let bounded = String(value.prefix(20_000))
            if note != bounded { note = bounded }
            store.updateNote(for: property.id, text: bounded)
        }
    }
}
