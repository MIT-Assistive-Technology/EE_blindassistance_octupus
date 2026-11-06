import OctopiCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var droppingPin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.activeAlert != nil { AlertBanner() }
                ScreenHeading(text: "Octopi")
                statusCard
                Button {
                    droppingPin = true
                } label: {
                    Label("Drop a pin here", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.primary)
                .accessibilityHint("Saves this spot so you can find your way back to it.")
                .accessibilityIdentifier("home.dropPin")

                NavigationLink(value: Route.places) { Label("Find a place", systemImage: "figure.walk") }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Lists your saved pins and beacons; pick one to be guided back.")
                    .accessibilityIdentifier("home.find")
                NavigationLink(value: Route.beacons) { Label("My beacons", systemImage: "dot.radiowaves.left.and.right") }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Pair beacons and see which are in range.")
                    .accessibilityIdentifier("home.beacons")
                NavigationLink(value: Route.tutorial) { Label("Practice the buzzes", systemImage: "hand.tap") }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Feel each haptic pattern with its meaning.")
                NavigationLink(value: Route.settings) { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $droppingPin) { DropPinView() }
        .accessibilityAction(.magicTap) {
            model.dropPin()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.bandStatusText)
            Text(model.anchorStatusText)
            Text(model.places.isEmpty ? "No saved places yet" : "\(model.places.count) saved place\(model.places.count == 1 ? "" : "s")")
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status. \(model.bandStatusText). \(model.anchorStatusText). \(model.places.count) saved places.")
        .accessibilityIdentifier("home.status")
    }
}

struct AlertBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let alert = model.activeAlert {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(alert.name) may have been left behind")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Button("Find \(alert.name)") { model.findLeftBehindItem() }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("alert.find")
                HStack(spacing: 12) {
                    Button("Snooze") { model.snoozeAlert() }
                        .buttonStyle(.secondary)
                        .accessibilityHint("Stops the alert for \(model.settings.snoozeMinutes) minutes.")
                    Button("I have it") { model.dismissAlert() }
                        .buttonStyle(.secondary)
                        .accessibilityHint("Clears the alert. The place stays saved.")
                }
            }
            .padding(16)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.red, lineWidth: 3))
            .accessibilitySortPriority(10)
        }
    }
}
