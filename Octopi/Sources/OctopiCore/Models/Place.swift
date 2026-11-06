import Foundation

/// Identifies a physical beacon. For a BLE beacon this is its serial from the advertisement.
nonisolated public struct BeaconIdentifier: Codable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// What kind of thing a place points at.
public enum PlaceKind: Codable, Equatable, Sendable {
    /// A pin with no hardware: "my seat", "the car".
    case virtualPin
    /// A physical BLE beacon clipped to something.
    case physicalBeacon(BeaconIdentifier)

    public var beaconIdentifier: BeaconIdentifier? {
        if case .physicalBeacon(let id) = self { return id }
        return nil
    }
}

/// How the place came to be saved.
public enum PlaceOrigin: String, Codable, Sendable {
    case bandButton
    case app
    case leftBehind
}

/// A plain-language confidence estimate, with the reasons so the narrator can explain it.
public struct Confidence: Codable, Equatable, Sendable {
    public enum Level: String, Codable, Sendable, Comparable {
        case low, medium, high
        private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    /// 0...1
    public var value: Double
    public var reasons: [String]

    public init(value: Double, reasons: [String] = []) {
        self.value = min(max(value, 0), 1)
        self.reasons = reasons
    }

    public var level: Level {
        if value >= 0.7 { return .high }
        if value >= 0.4 { return .medium }
        return .low
    }

    /// Spoken form, e.g. "Confidence high".
    public var spoken: String { "Confidence \(level.rawValue)" }
}

/// A saved pin or beacon: anchor + path from it + metadata. This is the record in the design doc.
public struct Place: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: PlaceKind
    public var origin: PlaceOrigin
    /// Nil when no GPS fix was ever good enough. Paths are then relative to wherever recording began.
    public var anchor: Anchor?
    public var path: StoredPath
    public var confidence: Confidence
    public var createdAt: Date
    /// For physical beacons: when the phone last heard it.
    public var lastHeard: Date?
    /// For physical beacons: last smoothed RSSI in dBm.
    public var lastRSSI: Double?
    /// Barometric pressure change from anchor to destination in kPa, when available. ~0.012 kPa per metre.
    public var pressureDeltaKPa: Double?
    /// When `anchor` is nil the path is relative to an arbitrary origin identified by this id; it is only
    /// navigable while the session is still in that same frame.
    public var frameID: UUID?

    public init(id: UUID = UUID(), name: String, kind: PlaceKind, origin: PlaceOrigin, anchor: Anchor?, path: StoredPath, confidence: Confidence, createdAt: Date, lastHeard: Date? = nil, lastRSSI: Double? = nil, pressureDeltaKPa: Double? = nil, frameID: UUID? = nil) {
        self.frameID = frameID
        self.id = id
        self.name = name
        self.kind = kind
        self.origin = origin
        self.anchor = anchor
        self.path = path
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastHeard = lastHeard
        self.lastRSSI = lastRSSI
        self.pressureDeltaKPa = pressureDeltaKPa
    }

    public var isPhysical: Bool { kind.beaconIdentifier != nil }

    /// Best estimate of the place's global position: anchor fix shifted by the path destination.
    public var estimatedFix: GeoFix? {
        guard let anchor, let destination = path.destination else { return nil }
        return GeoMath.offset(anchor.fix, by: destination)
    }

    /// Roughly one floor is 3 m, i.e. about 0.036 kPa.
    public var mayBeOnAnotherFloor: Bool {
        guard let delta = pressureDeltaKPa else { return false }
        return abs(delta) >= 0.025
    }
}
