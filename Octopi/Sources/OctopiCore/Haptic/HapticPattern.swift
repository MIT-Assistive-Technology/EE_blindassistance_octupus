import Foundation

/// The fixed haptic vocabulary. The band and the phone fallback both implement every pattern,
/// and the setup tutorial plays each one with its spoken name.
nonisolated public enum HapticPattern: String, CaseIterable, Codable, Sendable, Identifiable {
    case pinConfirmed
    case ahead
    case left
    case right
    case turnAround
    case arrived
    case leftBehindAlert
    case proximityPulse
    case lostSignal
    case lowBattery
    case bandConnected
    case error

    public var id: String { rawValue }

    /// Byte sent to the band for this pattern (stable; firmware depends on it).
    public var wireID: UInt8 {
        switch self {
        case .pinConfirmed: 0x01
        case .ahead: 0x02
        case .left: 0x03
        case .right: 0x04
        case .turnAround: 0x05
        case .arrived: 0x06
        case .leftBehindAlert: 0x07
        case .proximityPulse: 0x08
        case .lostSignal: 0x09
        case .lowBattery: 0x0A
        case .bandConnected: 0x0B
        case .error: 0x0C
        }
    }

    public init?(wireID: UInt8) {
        guard let match = Self.allCases.first(where: { $0.wireID == wireID }) else { return nil }
        self = match
    }

    /// Name spoken in the tutorial and the settings screen.
    public var spokenName: String {
        switch self {
        case .pinConfirmed: "Pin saved"
        case .ahead: "Go straight"
        case .left: "Turn left"
        case .right: "Turn right"
        case .turnAround: "Turn around"
        case .arrived: "You have arrived"
        case .leftBehindAlert: "Something was left behind"
        case .proximityPulse: "Getting closer"
        case .lostSignal: "Signal lost"
        case .lowBattery: "Battery low"
        case .bandConnected: "Band connected"
        case .error: "Something went wrong"
        }
    }

    /// What it feels like, for the tutorial.
    public var feelDescription: String {
        switch self {
        case .pinConfirmed: "Two quick taps."
        case .ahead: "One long buzz in the middle."
        case .left: "Two taps on the left side."
        case .right: "Three taps on the right side."
        case .turnAround: "Long, short, long, alternating sides."
        case .arrived: "A rising sweep across all motors, then a long buzz."
        case .leftBehindAlert: "Four strong, slow buzzes, repeated until you respond."
        case .proximityPulse: "Single taps that get faster as you get closer."
        case .lostSignal: "Two slow, weak buzzes."
        case .lowBattery: "Three faint taps."
        case .bandConnected: "One short tap."
        case .error: "A short double buzz on both sides."
        }
    }

    /// Patterns worth teaching in the tutorial, in teaching order.
    public static let tutorialOrder: [HapticPattern] = [.ahead, .left, .right, .turnAround, .arrived, .pinConfirmed, .proximityPulse, .leftBehindAlert]
}
