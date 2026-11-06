import OctopiCore
import SwiftUI

/// The live guidance screen. One big status, one big Stop. Everything else arrives by voice and haptics.
struct NavigateView: View {
    @Environment(AppModel.self) private var model
    @AccessibilityFocusState private var focusedOnStatus: Bool

    var body: some View {
        VStack(spacing: 24) {
            if let status = model.navigation {
                VStack(spacing: 12) {
                    Text(status.placeName).font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(status.phase.spoken).font(.title3).foregroundStyle(Color.detailText)
                    Text(headline(status)).font(.largeTitle.weight(.heavy)).minimumScaleFactor(0.6)
                    Text(detail(status)).font(.title2)
                    Text(status.confidence.spoken).font(.body).foregroundStyle(Color.detailText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.spokenSummary)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityFocused($focusedOnStatus)
                .accessibilityIdentifier("navigate.status")
            }
            Spacer()
            if model.navigation?.phase == .arrived {
                Button("Done") { model.stopNavigation() }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("navigate.done")
            } else {
                Button("Stop guiding") { model.stopNavigation() }
                    .buttonStyle(.destructive)
                    .accessibilityHint("Ends navigation and returns to the home screen.")
                    .accessibilityIdentifier("navigate.stop")
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .accessibilityAction(.magicTap) { model.stopNavigation() }
        .accessibilityAction(.escape) { model.stopNavigation() }
        .onAppear { focusedOnStatus = true }
    }

    private func headline(_ status: NavigationStatus) -> String {
        guard let cue = status.cue else { return "Starting" }
        switch cue.kind {
        case .go(let direction): return direction.spoken
        case .needHeading: return "Take a few steps"
        case .proximity(let estimate): return estimate.zone.spoken.capitalized
        case .arrived: return "Arrived"
        case .lost: return "Lost the path"
        }
    }

    private func detail(_ status: NavigationStatus) -> String {
        guard let cue = status.cue else { return "" }
        if case .proximity(let estimate) = cue.kind {
            return estimate.trend == .approaching ? "Signal getting stronger" : estimate.trend == .receding ? "Signal getting weaker" : ""
        }
        if let remaining = cue.distanceRemaining, cue.kind != .arrived { return GuidanceNarrator.spokenDistance(remaining, metric: model.settings.useMetric) + " to go" }
        return ""
    }
}
