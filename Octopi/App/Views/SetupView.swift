import OctopiCore
import SwiftUI

/// First-run flow: one step per screen, one idea per step.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @AccessibilityFocusState private var focusHeading: Bool

    private let steps = ["Welcome", "Permissions", "Your band", "Your beacons", "Practice the buzzes"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Step \(step + 1) of \(steps.count)").font(.subheadline).foregroundStyle(Color.detailText).frame(maxWidth: .infinity, alignment: .leading)
                ScreenHeading(text: steps[step]).accessibilityFocused($focusHeading)
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: band
                case 3: beacons
                default: practice
                }
                Spacer(minLength: 20)
                if step < steps.count - 1 {
                    Button("Next") { step += 1 }.buttonStyle(.primary).accessibilityIdentifier("setup.next")
                } else {
                    Button("Finish setup") { model.setupComplete = true }.buttonStyle(.primary).accessibilityIdentifier("setup.finish")
                }
                if step > 0 {
                    Button("Back") { step -= 1 }.buttonStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onChange(of: step) { focusHeading = true }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Octopi remembers where you have been and buzzes you back there.")
            Text("Drop a pin with the band button or the app. Clip a beacon to your keys or bag and Octopi notices if it gets left behind. Then it guides you back with buzzes: left, right, straight, and a special pattern when you arrive.")
            Text("Keep the phone in your pocket. Everything important is spoken and felt.")
        }
        .font(.title3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissions: some View {
        VStack(spacing: 12) {
            Text("Octopi needs three permissions. Each button asks the system once.").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
            Button("Motion: \(model.motion.authorizationDescription)") { model.requestMotionPermission() }
                .buttonStyle(.secondary).accessibilityHint("Counts steps and turns.")
            Button("Location: \(model.location.authorizationDescription)") { model.requestLocationPermission() }
                .buttonStyle(.secondary).accessibilityHint("Uses GPS as the starting point of each path.")
            Button("Bluetooth: \(model.isSimulating ? "Simulated" : model.bluetooth.stateDescription)") { model.connectBand() }
                .buttonStyle(.secondary).accessibilityHint("Talks to the band and listens for beacons.")
            Button("Open system Settings") { model.openSystemSettings() }.buttonStyle(.secondary)
                .accessibilityHint("If a permission was denied, turn it on there.")
        }
    }

    private var band: some View {
        VStack(spacing: 12) {
            Text(model.bandStatusText).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("setup.bandStatus")
            Text("Turn the band on and hold it near the phone. The band buzzes once when it connects.").frame(maxWidth: .infinity, alignment: .leading)
            Button("Connect my band") { model.connectBand() }.buttonStyle(.secondary).accessibilityIdentifier("setup.connectBand")
            Text("You can skip this and use the phone's own vibration.").font(.subheadline).foregroundStyle(Color.detailText).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var beacons: some View {
        VStack(spacing: 12) {
            Text("Clip beacons to things you do not want to lose. You can pair them now or later from My beacons.").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink(value: Route.beacons) { Text("Pair beacons") }.buttonStyle(.secondary)
        }
    }

    private var practice: some View {
        VStack(spacing: 12) {
            Text("Feel each buzz once so you know what it means.").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(HapticPattern.tutorialOrder) { pattern in
                Button("\(pattern.spokenName). \(pattern.feelDescription)") { model.playTutorial(pattern) }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Plays this pattern.")
            }
        }
    }
}
