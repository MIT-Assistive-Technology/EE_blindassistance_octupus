import Foundation

/// The outdoor leg: GPS guidance from wherever the user is to the stored anchor.
public struct AnchorApproach: Sendable {
    public struct Config: Sendable {
        /// Arrive when within this many metres of the anchor (or the fix accuracy if larger).
        public var arriveRadius = 8.0
        /// Ignore fixes worse than this (m) for guidance.
        public var maxAccuracy = 40.0
        public init() {}
    }

    public var config: Config
    public init(config: Config = Config()) { self.config = config }

    /// `userBearing` is the compass bearing the user faces, degrees clockwise from north.
    public func cue(from fix: GeoFix, to anchor: Anchor, userBearing: Double?) -> GuidanceCue {
        let distance = GeoMath.distance(fix, anchor.fix)
        let radius = max(config.arriveRadius, min(fix.horizontalAccuracy, config.maxAccuracy))
        if distance <= radius {
            return GuidanceCue(kind: .arrived, phase: .toAnchor, distanceToTarget: distance, distanceRemaining: distance)
        }
        guard fix.horizontalAccuracy <= config.maxAccuracy else {
            return GuidanceCue(kind: .lost, phase: .toAnchor, distanceToTarget: distance, distanceRemaining: distance)
        }
        guard let userBearing else {
            return GuidanceCue(kind: .needHeading, phase: .toAnchor, distanceToTarget: distance, distanceRemaining: distance)
        }
        let target = GeoMath.bearing(from: fix, to: anchor.fix)
        // Compass bearings grow clockwise; a positive delta means turn right, so negate for "positive = left".
        let relative = -GeoMath.signedDelta(from: userBearing, to: target)
        return GuidanceCue(kind: .go(Direction.from(relativeDegrees: relative)), phase: .toAnchor, distanceToTarget: distance, distanceRemaining: distance)
    }
}
