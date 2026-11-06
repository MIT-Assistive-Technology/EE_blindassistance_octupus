import Foundation

/// Why a waypoint was kept when the path was simplified.
public enum WaypointKind: String, Codable, Sendable {
    /// The path origin (the anchor, or where recording began).
    case start
    /// A noticeable change of heading. These matter most to blind users, who remember routes as "left, then straight".
    case turn
    /// A spacing point on a straight run.
    case spacing
    /// The destination.
    case end
}

public struct Waypoint: Codable, Equatable, Sendable {
    public var point: LocalPoint
    public var kind: WaypointKind
    /// Seconds since recording started.
    public var time: Double

    public init(point: LocalPoint, kind: WaypointKind, time: Double) {
        self.point = point
        self.kind = kind
        self.time = time
    }
}

/// A simplified walking path from an anchor to a place, in metres relative to the anchor.
public struct StoredPath: Codable, Equatable, Sendable {
    public var waypoints: [Waypoint]
    /// Metres actually walked while recording (before simplification), used for confidence.
    public var walkedLength: Double
    /// True when the recording exceeded the storage cap and the earliest part was dropped.
    public var truncated: Bool

    public init(waypoints: [Waypoint], walkedLength: Double, truncated: Bool = false) {
        self.waypoints = waypoints
        self.walkedLength = walkedLength
        self.truncated = truncated
    }

    public static let empty = StoredPath(waypoints: [], walkedLength: 0)

    public var isEmpty: Bool { waypoints.count < 2 }

    public var destination: LocalPoint? { waypoints.last?.point }

    /// Length of the simplified polyline.
    public var length: Double {
        guard waypoints.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<waypoints.count {
            total += waypoints[index - 1].point.distance(to: waypoints[index].point)
        }
        return total
    }

    public var turnCount: Int { waypoints.filter { $0.kind == .turn }.count }
}
