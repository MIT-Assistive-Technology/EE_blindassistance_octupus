import OctopiCore
import SwiftUI

/// Settings use the same stacked layout as every other screen (Form rows, headers and pickers do not
/// pass Apple's Dynamic Type and contrast audits reliably).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(text: "Settings")

                SectionHeader("Left-behind alerts")
                Text("Sensitivity: how far you walk from a still beacon before Octopi warns you")
                    .font(.headline)
                ChoiceRow(title: "Low: fewer alerts", isSelected: model.settings.leftBehindSensitivity == .low) { model.settings.leftBehindSensitivity = .low }
                ChoiceRow(title: "Normal", isSelected: model.settings.leftBehindSensitivity == .normal) { model.settings.leftBehindSensitivity = .normal }
                ChoiceRow(title: "High: alert sooner", isSelected: model.settings.leftBehindSensitivity == .high) { model.settings.leftBehindSensitivity = .high }
                AdjustRow(label: "Snooze for \(model.settings.snoozeMinutes) minutes",
                          decrease: { model.settings.snoozeMinutes = max(1, model.settings.snoozeMinutes - 1) },
                          increase: { model.settings.snoozeMinutes = min(60, model.settings.snoozeMinutes + 1) })

                SectionHeader("Guidance")
                ToggleRow(title: "Speak guidance aloud when VoiceOver is off", isOn: $model.settings.speakGuidance)
                ToggleRow(title: "Also vibrate the phone when the band is connected", isOn: $model.settings.mirrorHapticsToPhone)
                Text("Distances").font(.headline)
                ChoiceRow(title: "Metres", isSelected: model.settings.useMetric) { model.settings.useMetric = true }
                ChoiceRow(title: "Feet", isSelected: !model.settings.useMetric) { model.settings.useMetric = false }

                SectionHeader("Band")
                Text(model.bandStatusText).font(.title3)
                if !model.isSimulating {
                    Button("Connect band") { model.connectBand() }.buttonStyle(.secondary)
                    Button("Forget band") { model.forgetBand() }.buttonStyle(.destructive)
                        .accessibilityHint("The band will need to be paired again.")
                }
                let target = model.beacons.first { $0.serial == model.settings.simpleModeBeaconSerial }
                Text("Simple mode beacon: \(target?.name ?? "none"). Choose it from My beacons.").font(.title3)

                SectionHeader("Developer")
                #if DEBUG
                ToggleRow(title: "Simulate band, beacons and walking", isOn: $model.isSimulating)
                #endif
                if model.isSimulating {
                    NavigationLink(value: Route.simulator) { Text("Simulator controls") }
                        .buttonStyle(.row)
                        .accessibilityIdentifier("settings.simulator")
                }
                NavigationLink(value: Route.diagnostics) { Text("Diagnostics") }
                    .buttonStyle(.row)
                    .accessibilityIdentifier("settings.diagnostics")
            }
            .padding(20)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A toggle that scales with Dynamic Type and reads as one element.
struct ToggleRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).font(.title3) }
            .padding(.vertical, 8)
    }
}

/// A value with Shorter/Longer buttons. VoiceOver can also swipe up/down on the label to adjust.
struct AdjustRow: View {
    var label: String
    var decrease: () -> Void
    var increase: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.title3)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: increase()
                    case .decrement: decrease()
                    @unknown default: break
                    }
                }
            HStack(spacing: 12) {
                Button("Shorter") { decrease() }.buttonStyle(.secondary)
                Button("Longer") { increase() }.buttonStyle(.secondary)
            }
        }
    }
}

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.diagnostics
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHeading(text: "Diagnostics")
                SectionHeader("Dead reckoning")
                InfoRow(label: "Steps since anchor", value: "\(d.stepCount)")
                InfoRow(label: "Distance since anchor", value: String(format: "%.1f m", d.distanceSinceAnchor))
                InfoRow(label: "Position east, north", value: String(format: "%.1f, %.1f m", d.position.east, d.position.north))
                InfoRow(label: "Heading", value: d.compassBearing.map { "\(Int($0))°" } ?? "unknown")
                InfoRow(label: "Moving", value: d.isMoving ? "yes" : "no")
                InfoRow(label: "Drift estimate", value: String(format: "%.1f m", d.driftEstimate))
                SectionHeader("Anchor")
                InfoRow(label: "Status", value: model.anchorStatusText)
                InfoRow(label: "GPS degraded", value: d.gpsDegraded ? "yes, likely indoors" : "no")
                InfoRow(label: "Last decision", value: d.lastAnchorDecision ?? "none yet")
                SectionHeader("Beacons")
                if model.beacons.isEmpty { Text("None paired").font(.title3) }
                ForEach(model.beacons) { beacon in
                    InfoRow(label: beacon.name, value: "RSSI \(beacon.lastRSSI.map { String(Int($0)) } ?? "–"), \(model.session.detector.state(of: beacon.id).map { "\($0)" } ?? "untracked")")
                }
                SectionHeader("Announcements")
                ForEach(Array(model.announcements.suffix(15).reversed().enumerated()), id: \.offset) { _, item in
                    Text(item.text).font(.body)
                }
            }
            .padding(20)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SimulatorControlsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sim = model.simulator
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeading(text: "Simulator")
                SectionHeader("Walking")
                Button(sim.isWalking ? "Stop walking" : "Start walking") { sim.toggleWalking(); model.bump() }
                    .buttonStyle(.secondary).accessibilityIdentifier("sim.walk")
                Button("Turn left 90°") { sim.turn(byDegrees: 90) }.buttonStyle(.secondary).accessibilityIdentifier("sim.left")
                Button("Turn right 90°") { sim.turn(byDegrees: -90) }.buttonStyle(.secondary).accessibilityIdentifier("sim.right")
                Button("Turn around") { sim.turn(byDegrees: 180) }.buttonStyle(.secondary).accessibilityIdentifier("sim.around")
                Button("Send a good GPS fix") { sim.sendGoodFix() }.buttonStyle(.secondary).accessibilityIdentifier("sim.gps")
                SectionHeader("Band buttons")
                Button("Single press (drop pin)") { sim.pressBandButton(.single) }.buttonStyle(.secondary).accessibilityIdentifier("sim.band.single")
                Button("Double press (find latest)") { sim.pressBandButton(.double) }.buttonStyle(.secondary)
                Button("Long press (stop or snooze)") { sim.pressBandButton(.long) }.buttonStyle(.secondary)
                SectionHeader("Beacons")
                ForEach(sim.beacons) { beacon in
                    Button(beacon.carried ? "Leave \(beacon.name) here" : "Pick up \(beacon.name)") {
                        if beacon.carried { sim.dropBeacon(beacon.id) } else { sim.pickUpBeacon(beacon.id) }
                        model.bump()
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("sim.beacon.\(beacon.name)")
                }
                SectionHeader("Band log")
                ForEach(Array(sim.band.log.reversed().enumerated()), id: \.offset) { _, line in Text(line).font(.body) }
            }
            .padding(20)
        }
        .navigationTitle("Simulator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
