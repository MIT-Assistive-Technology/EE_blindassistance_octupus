import Foundation

/// Follows a stored waypoint path using dead-reckoned position and heading in the anchor frame.
public final class RouteFollower {
    public struct Config: Sendable {
        /// A waypoint counts as reached inside this radius (m).
        public var waypointRadius = 2.0
        /// The destination counts as reached inside this radius (m).
        public var arriveRadius = 2.5
        /// Further than this (m) from the current segment is "off track"; we re-target the nearest waypoint.
        public var offTrackDistance = 6.0
        /// Further than this (m) from every waypoint is "lost".
        public var lostDistance = 25.0
        public init() {}
    }

    public var config: Config
    public let path: StoredPath
    public private(set) var targetIndex: Int
    public private(set) var isOffTrack = false

    public init(path: StoredPath, config: Config = Config()) {
        self.path = path
        self.config = config
        targetIndex = min(1, max(path.waypoints.count - 1, 0))
    }

    public var target: Waypoint? { path.waypoints.indices.contains(targetIndex) ? path.waypoints[targetIndex] : nil }
    public var isAtLastWaypoint: Bool { targetIndex >= path.waypoints.count - 1 }

    /// Compute the next cue. `heading` is the PDR heading in radians CCW from east; nil before the first step.
    public func update(position: LocalPoint, heading: Double?) -> GuidanceCue {
        guard !path.isEmpty, let destination = path.destination else {
            return GuidanceCue(kind: .arrived, phase: .alongPath, distanceToTarget: 0, distanceRemaining: 0)
        }
        advance(from: position)
        let distanceToDestination = position.distance(to: destination)
        if isAtLastWaypoint, distanceToDestination <= config.arriveRadius {
            return GuidanceCue(kind: .arrived, phase: .alongPath, distanceToTarget: distanceToDestination, distanceRemaining: distanceToDestination)
        }
        checkTrack(position)
        guard let target else {
            return GuidanceCue(kind: .arrived, phase: .alongPath, distanceToTarget: 0, distanceRemaining: 0)
        }
        let distanceToTarget = position.distance(to: target.point)
        let remaining = distanceToTarget + remainingAfterTarget()
        if nearestWaypointDistance(position) > config.lostDistance {
            return GuidanceCue(kind: .lost, phase: .lost, distanceToTarget: distanceToTarget, distanceRemaining: remaining)
        }
        guard let heading else {
            return GuidanceCue(kind: .needHeading, phase: .alongPath, distanceToTarget: distanceToTarget, distanceRemaining: remaining)
        }
        let desired = position.heading(to: target.point)
        let relative = HeadingMath.wrap(desired - heading) * 180 / .pi
        return GuidanceCue(kind: .go(Direction.from(relativeDegrees: relative)), phase: .alongPath, distanceToTarget: distanceToTarget, distanceRemaining: remaining)
    }

    /// Move the target forward past any waypoint we reached or walked past.
    private func advance(from position: LocalPoint) {
        while targetIndex < path.waypoints.count - 1 {
            let target = path.waypoints[targetIndex].point
            let previous = path.waypoints[max(targetIndex - 1, 0)].point
            let reached = position.distance(to: target) <= config.waypointRadius
            let passed = projection(of: position, from: previous, to: target) > 1 && position.distance(to: target) <= config.offTrackDistance
            guard reached || passed else { break }
            targetIndex += 1
        }
    }

    private func checkTrack(_ position: LocalPoint) {
        guard targetIndex > 0 else { isOffTrack = false; return }
        let a = path.waypoints[targetIndex - 1].point, b = path.waypoints[targetIndex].point
        let off = PathSimplifier.perpendicularDistance(position, from: a, to: b)
        isOffTrack = off > config.offTrackDistance
        guard isOffTrack else { return }
        // Re-target the nearest waypoint that is not behind us.
        var best = targetIndex
        var bestDistance = position.distance(to: b)
        for index in path.waypoints.indices where index >= 1 {
            let d = position.distance(to: path.waypoints[index].point)
            if d < bestDistance { bestDistance = d; best = index }
        }
        targetIndex = best
    }

    private func remainingAfterTarget() -> Double {
        guard targetIndex < path.waypoints.count - 1 else { return 0 }
        var total = 0.0
        for index in (targetIndex + 1)..<path.waypoints.count {
            total += path.waypoints[index - 1].point.distance(to: path.waypoints[index].point)
        }
        return total
    }

    private func nearestWaypointDistance(_ position: LocalPoint) -> Double {
        path.waypoints.map { position.distance(to: $0.point) }.min() ?? 0
    }

    /// Scalar projection parameter of `p` onto a→b (0 at a, 1 at b).
    private func projection(of p: LocalPoint, from a: LocalPoint, to b: LocalPoint) -> Double {
        let dx = b.east - a.east, dy = b.north - a.north
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        return ((p.east - a.east) * dx + (p.north - a.north) * dy) / lengthSquared
    }
}
