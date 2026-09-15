import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 10) {
                        WatchdogEmblem().fill(WDTheme.accent, style: FillStyle(eoFill: true)).frame(width: 38, height: 38)
                        Text("Watchdog").font(.title2.bold()).tracking(-0.5)
                        Spacer()
                        Text("FOR EVERY HOME").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(WDTheme.muted)
                    }
                    Spacer(minLength: 16)
                    illustration
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 16)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Every property\nhas a story.")
                            .font(.system(.largeTitle, design: .serif, weight: .regular))
                            .tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                        Text("Get the full picture.")
                            .font(.title2.weight(.semibold)).foregroundStyle(WDTheme.accent)
                        Text("Explore New Jersey homes, understand the assessment, and see the public records behind the numbers.")
                            .font(.body).foregroundStyle(WDTheme.muted).lineSpacing(4)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("Search freely", subtitle: "No account. No subscription.", symbol: "magnifyingglass")
                        benefit("See the evidence", subtitle: "Assessments, recorded sales, and sources.", symbol: "doc.text.magnifyingglass")
                        benefit("Make it yours", subtitle: "Save homes, compare, and keep private notes.", symbol: "bookmark")
                    }
                    Spacer(minLength: 8)
                    WDPrimaryButton("Start exploring", symbol: "arrow.right") { store.completeOnboarding() }
                        .accessibilityIdentifier("welcome.start")
                    Text("Public property research. Not a live listing service.")
                        .font(.caption).foregroundStyle(WDTheme.muted).frame(maxWidth: .infinity)
                }
                .padding(28)
                .frame(maxWidth: 570)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .background(WDTheme.canvas)
        }
        .interactiveDismissDisabled()
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { appeared = true }
        }
    }

    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32).fill(WDTheme.accent.opacity(0.07))
            NeighborhoodLines().stroke(WDTheme.accent.opacity(0.11), style: StrokeStyle(lineWidth: 1.5))
                .padding(8)
            HStack(alignment: .bottom, spacing: 24) {
                Image(systemName: "house").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(WDTheme.accent.opacity(0.5))
                VStack(spacing: 14) {
                    Label("A clearer view", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(WDTheme.surface, in: Capsule())
                    Image(systemName: "house.fill").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(WDTheme.accent)
                }
                Image(systemName: "tree.fill").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(WDTheme.accent.opacity(0.45))
            }.padding(28)
        }
        .frame(height: 200)
        .accessibilityHidden(true)
    }

    private func benefit(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(WDTheme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(WDTheme.muted)
            }
        }
    }
}

private struct NeighborhoodLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for offset in stride(from: -200.0, to: 900.0, by: 60) {
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset + 130, y: rect.height))
        }
        for offset in stride(from: 20.0, to: 300.0, by: 48) {
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: rect.width, y: offset - 35))
        }
        return path
    }
}
