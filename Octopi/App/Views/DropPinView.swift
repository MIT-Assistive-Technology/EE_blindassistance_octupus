import SwiftUI

/// Name picker used for pins and beacons: quick names first, then free text (the keyboard offers dictation).
struct NamePicker: View {
    var title: String
    var quickNames: [String]
    var onPick: (String?) -> Void
    var onCancel: () -> Void
    @State private var custom = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeading(text: title)
                ForEach(quickNames, id: \.self) { name in
                    Button(name) { onPick(name) }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("name.\(name)")
                }
                TextField("Or type a name", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if !custom.isEmpty { onPick(custom) } }
                    .accessibilityLabel("Type a name")
                    .accessibilityHint("Use the microphone key on the keyboard to dictate.")
                Button("Save as \(custom.isEmpty ? "automatic name" : custom)") { onPick(custom.isEmpty ? nil : custom) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("name.save")
                Button("Cancel") { onCancel() }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("name.cancel")
            }
            .padding(20)
        }
    }
}

struct DropPinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NamePicker(title: "Name this spot", quickNames: ["My seat", "The car", "Front door", "My room", "Bathroom", "Camp"], onPick: { name in
                model.dropPin(name: name)
                dismiss()
            }, onCancel: { dismiss() })
        }
        .presentationDetents([.large])
    }
}
