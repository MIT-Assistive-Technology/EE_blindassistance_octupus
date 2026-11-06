import SwiftUI

/// The one button style used for every action. Large, high contrast, full width, and it reflows
/// with Dynamic Type instead of truncating.
struct BigButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive }
    var role: Role = .secondary
    var minHeight: CGFloat = 64
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(border, lineWidth: contrast == .increased ? 3 : 1.5))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var foreground: Color {
        switch role {
        case .primary: .white
        case .secondary: .primary
        case .destructive: .white
        }
    }

    private var background: Color {
        switch role {
        case .primary: .accentColor
        case .secondary: Color(.secondarySystemBackground)
        case .destructive: Color(red: 0.72, green: 0.08, blue: 0.08)
        }
    }

    private var border: Color {
        switch role {
        case .primary: .accentColor
        case .secondary: .primary.opacity(contrast == .increased ? 1 : 0.35)
        case .destructive: .clear
        }
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var primary: BigButtonStyle { BigButtonStyle(role: .primary, minHeight: 88) }
    static var secondary: BigButtonStyle { BigButtonStyle(role: .secondary) }
    static var destructive: BigButtonStyle { BigButtonStyle(role: .destructive) }
}

/// A heading that VoiceOver users can jump to with the rotor.
struct ScreenHeading: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A label/value pair read as one sentence.
struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline).foregroundStyle(Color.detailText)
            Text(value).font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

extension Color {
    /// Secondary text with at least 7:1 contrast on the system background in both appearances
    /// (the system `.secondary` only "nearly passes" Apple's audit).
    static let detailText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.82, alpha: 1) : UIColor(white: 0.28, alpha: 1)
    })
}

/// Section header for forms and lists with enough contrast (the default small grey caps only nearly pass).
struct SectionHeader: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.detailText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One option of a small choice list. Reads as "Normal, selected" and scales with Dynamic Type,
/// unlike SwiftUI's inline picker labels.
struct ChoiceRow: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body)
                Spacer()
                if isSelected { Text("Selected").font(.subheadline).foregroundStyle(Color.detailText) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
