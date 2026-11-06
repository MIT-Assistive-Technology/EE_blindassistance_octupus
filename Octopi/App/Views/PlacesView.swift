import OctopiCore
import SwiftUI

struct PlacesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeading(text: "Find a place")
                if model.places.isEmpty {
                    Text("No saved places yet. Drop a pin from the home screen, or pair a beacon.")
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Most recent first. Pick one to be guided back.")
                        .font(.body)
                        .foregroundStyle(Color.detailText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(model.places) { place in
                        NavigationLink(value: Route.place(place.id)) {
                            PlaceRowLabel(place: place)
                        }
                        .buttonStyle(.row)
                        .accessibilityLabel(PlaceRowLabel.spoken(place))
                        .accessibilityHint("Opens this place. Then choose Guide me there.")
                        .accessibilityIdentifier("place.\(place.name)")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Find a place")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaceRowLabel: View {
    var place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name).font(.title2.weight(.semibold))
            Text(Self.detail(place)).font(.subheadline).foregroundStyle(Color.detailText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func detail(_ place: Place) -> String {
        var parts: [String] = [place.isPhysical ? "Beacon" : "Pin"]
        parts.append(Self.when(place.createdAt))
        parts.append(place.confidence.spoken.lowercased())
        if place.path.length > 0 { parts.append(GuidanceNarrator.spokenDistance(place.path.length) + " away") }
        return parts.joined(separator: ", ")
    }

    static func spoken(_ place: Place) -> String { "\(place.name). \(detail(place))." }

    static func when(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PlaceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var placeID: UUID
    @State private var renaming = false
    @State private var confirmingDelete = false

    private var place: Place? { model.places.first { $0.id == placeID } }

    var body: some View {
        ScrollView {
            if let place {
                VStack(spacing: 14) {
                    ScreenHeading(text: place.name)
                    InfoRow(label: "What", value: place.isPhysical ? "Physical beacon" : "Pin")
                    InfoRow(label: "Saved", value: PlaceRowLabel.when(place.createdAt))
                    InfoRow(label: "Path", value: place.path.isEmpty ? "No path recorded" : "\(GuidanceNarrator.spokenDistance(place.path.length)), \(place.path.turnCount) turn\(place.path.turnCount == 1 ? "" : "s")")
                    InfoRow(label: "Confidence", value: place.confidence.level.rawValue.capitalized + (place.confidence.reasons.isEmpty ? "" : ". " + place.confidence.reasons.joined(separator: ". ")))
                    if place.mayBeOnAnotherFloor { InfoRow(label: "Note", value: "This place may be on another floor") }
                    if place.anchor == nil { InfoRow(label: "Note", value: "Saved without GPS. Start from where you were when you saved it.") }
                    Button { model.navigate(to: place) } label: { Label("Guide me there", systemImage: "figure.walk") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("place.guide")
                    Button("Rename") { renaming = true }.buttonStyle(.secondary)
                    Button("Delete") { confirmingDelete = true }.buttonStyle(.destructive)
                        .accessibilityHint("Asks you to confirm first.")
                }
                .padding(20)
            }
        }
        .navigationTitle(place?.name ?? "Place")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $renaming) {
            NavigationStack {
                NamePicker(title: "Rename", quickNames: ["My seat", "The car", "Front door", "My room", "Bathroom", "Camp"], onPick: { name in
                    if let place, let name { model.rename(place, to: name) }
                    renaming = false
                }, onCancel: { renaming = false })
            }
        }
        .confirmationDialog("Delete \(place?.name ?? "this place")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let place { model.delete(place); dismiss() }
            }
            Button("Keep", role: .cancel) {}
        }
    }
}
