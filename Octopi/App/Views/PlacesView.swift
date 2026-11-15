import OctopiCore
import SwiftUI
import UniformTypeIdentifiers

struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = PlaceFilter.all
    @State private var sort = PlaceSort.recent
    @State private var importing = false
    @State private var importMessage: String?
    @State private var exportURL: URL?

    private var results: [Place] { PlaceSearch.apply(model.places, query: query, filter: filter, sort: sort) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(text: "Find a place")
                if model.places.isEmpty {
                    Text("No saved places yet. Drop a pin from the home screen, pair a beacon, or import a pack.")
                        .font(.title3)
                } else {
                    searchControls
                    Text(PlaceSearch.spokenCount(results.count, query: query))
                        .font(.headline)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("places.count")
                    ForEach(results) { place in
                        NavigationLink(value: Route.place(place.id)) {
                            PlaceRowLabel(place: place)
                        }
                        .buttonStyle(.row)
                        .accessibilityLabel(PlaceRowLabel.spoken(place))
                        .accessibilityHint("Opens this place. Then choose Guide me there.")
                        .accessibilityIdentifier("place.\(place.name)")
                    }
                }
                SectionHeader("Packs")
                Text("A pack is a file of places you can share, for example a building mapped by an orientation specialist.")
                Button { importing = true } label: { Label("Import a pack", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Opens the file picker. Pick an Octopi pack file.")
                    .accessibilityIdentifier("places.import")
                if let exportURL {
                    ShareLink(item: exportURL, subject: Text("Octopi places"), message: Text("My Octopi places pack")) {
                        Label("Share my places as a pack", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.secondary)
                    .accessibilityHint("Shares a pack file with all your saved places.")
                    .accessibilityIdentifier("places.share")
                }
                if let importMessage {
                    Text(importMessage)
                        .font(.title3)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("places.importMessage")
                }
            }
            .padding(20)
        }
        .navigationTitle("Find a place")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case .success(let url): importMessage = model.importPack(from: url)
            case .failure: importMessage = "No file was imported."
            }
            exportURL = model.exportPackURL()
        }
        .onAppear { exportURL = model.exportPackURL() }
        .onChange(of: model.places.count) { exportURL = model.exportPackURL() }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search by name", text: $query, axis: .vertical)
                .growingTextField()
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search places")
                .accessibilityHint("Type part of a name or a pack name. Results update as you type.")
                .accessibilityIdentifier("places.search")
            if !query.isEmpty {
                Button("Clear search") { query = "" }.buttonStyle(.secondary)
            }
            Text("Show").font(.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PlaceFilter.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: filter == option) { filter = option }
                }
            }
            Text("Order").font(.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PlaceSort.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: sort == option) { sort = option }
                }
            }
        }
    }
}

/// A compact selectable button used for filters. Reads as "Pins, selected".
struct ChipButton: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : 0.35), lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        if let source = place.source { parts.append("from \(source)") }
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
                    if let source = place.source { InfoRow(label: "From pack", value: source) }
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
