import Foundation

/// One GPS reading as reported by the phone.
nonisolated public struct GeoFix: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy radius in metres. Negative means invalid.
    public var horizontalAccuracy: Double
    public var timestamp: Date
    /// Ground speed in m/s when the phone reports it, otherwise nil.
    public var speed: Double?
    /// Direction of travel in degrees clockwise from north, when moving fast enough for GPS to know it.
    public var course: Double?
    /// Pressure in kilopascals when the phone's barometer reports it.
    public var pressureKPa: Double?

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date, speed: Double? = nil, course: Double? = nil, pressureKPa: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.speed = speed
        self.course = course
        self.pressureKPa = pressureKPa
    }

    public var isValid: Bool { horizontalAccuracy >= 0 && abs(latitude) <= 90 && abs(longitude) <= 180 }
}

/// How much we trust an anchor at the moment it was taken.
nonisolated public enum AnchorQuality: String, Codable, Sendable, Comparable {
    case poor, fair, good

    private var rank: Int { switch self { case .poor: 0; case .fair: 1; case .good: 2 } }
    public static func < (lhs: AnchorQuality, rhs: AnchorQuality) -> Bool { lhs.rank < rhs.rank }
}

/// The last trustworthy GPS fix before the signal degraded. Stored paths are relative to it.
nonisolated public struct Anchor: Codable, Equatable, Sendable {
    public var fix: GeoFix
    public var quality: AnchorQuality
    public var establishedAt: Date

    public init(fix: GeoFix, quality: AnchorQuality, establishedAt: Date) {
        self.fix = fix
        self.quality = quality
        self.establishedAt = establishedAt
    }
}
