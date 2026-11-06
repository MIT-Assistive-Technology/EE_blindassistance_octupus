import OctopiCore
import SwiftUI

struct HapticTutorialView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeading(text: "Practice the buzzes")
                Text(model.isSimulating ? "The simulated band logs each pattern; the phone vibrates if it can." : "Each button plays a pattern on your band and says what it means.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(HapticPattern.tutorialOrder) { pattern in
                    Button {
                        model.playTutorial(pattern)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.spokenName).font(.title2.weight(.semibold))
                            Text(pattern.feelDescription).font(.subheadline).foregroundStyle(Color.detailText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.row)
                    .accessibilityLabel("\(pattern.spokenName). \(pattern.feelDescription)")
                    .accessibilityHint("Plays this pattern.")
                    .accessibilityIdentifier("tutorial.\(pattern.rawValue)")
                }
                Button("Stop buzzing") { model.stopHaptics() }.buttonStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }
}
