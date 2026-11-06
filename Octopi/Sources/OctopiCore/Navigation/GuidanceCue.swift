import Foundation

/// Which way to go, relative to the way the user is facing.
public enum Direction: String, Equatable, Sendable, Codable {
    case ahead, slightLeft, left, sharpLeft, slightRight, right, sharpRight, turnAround

    /// `relativeDegrees` is the signed turn needed: positive = left (counter-clockwise), -180...180.
    public static func from(relativeDegrees d: Double) -> Direction {
        let magnitude = abs(d)
        if magnitude < 20 { return .ahead }
        if magnitude >= 150 { return .turnAround }
        if d > 0 {
            if magnitude < 50 { return .slightLeft }
            if magnitude < 120 { return .left }
            return .sharpLeft
        } else {
            if magnitude < 50 { return .slightRight }
            if magnitude < 120 { return .right }
            return .sharpRight
        }
    }

    public var hapticPattern: HapticPattern {
        switch self {
        case .ahead: .ahead
        case .slightLeft, .left, .sharpLeft: .left
        case .slightRight, .right, .sharpRight: .right
        case .turnAround: .turnAround
        }
    }

    public var spoken: String {
        switch self {
        case .ahead: "Straight ahead"
        case .slightLeft: "Bear left"
        case .left: "Turn left"
        case .sharpLeft: "Sharp left"
        case .slightRight: "Bear right"
        case .right: "Turn right"
        case .sharpRight: "Sharp right"
        case .turnAround: "Turn around"
        }
    }

    public var isLeft: Bool { [.slightLeft, .left, .sharpLeft].contains(self) }
    public var isRight: Bool { [.slightRight, .right, .sharpRight].contains(self) }
}

public enum NavigationPhase: String, Equatable, Sendable, Codable {
    /// Outdoors, walking to the GPS anchor.
    case toAnchor
    /// Following the stored waypoints with dead reckoning.
    case alongPath
    /// Within radio range of a physical beacon; homing on signal strength.
    case proximity
    case arrived
    /// We cannot tell where the user is relative to the path.
    case lost

    public var spoken: String {
        switch self {
        case .toAnchor: "Heading to the starting point"
        case .alongPath: "Following the path"
        case .proximity: "Homing in on the beacon"
        case .arrived: "Arrived"
        case .lost: "Lost the path"
        }
    }
}

/// One guidance decision. Produced a few times a second; the narrator and haptics decide what to surface.
public struct GuidanceCue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case go(Direction)
        /// We do not know which way the user faces yet; ask them to take a few steps.
        case needHeading
        case proximity(ProximityEstimate)
        case arrived
        case lost
    }

    public var kind: Kind
    public var phase: NavigationPhase
    /// Metres to the current target (waypoint, anchor or beacon), when known.
    public var distanceToTarget: Double?
    /// Metres along the remaining route, when known.
    public var distanceRemaining: Double?

    public init(kind: Kind, phase: NavigationPhase, distanceToTarget: Double? = nil, distanceRemaining: Double? = nil) {
        self.kind = kind
        self.phase = phase
        self.distanceToTarget = distanceToTarget
        self.distanceRemaining = distanceRemaining
    }
}
