import Foundation

/// Turns a stream of cues into short spoken phrases without talking over the user.
///
/// Rules: say every change of direction; repeat the distance every `repeatInterval` seconds while
/// going straight; say "arrived" once; do not speak more often than `minimumGap` except for
/// turn-around and arrival. Distances are rounded so they sound natural.
public final class GuidanceNarrator {
    public struct Config: Sendable {
        public var minimumGap = 2.5
        public var repeatInterval = 8.0
        public var useMetric = true
        public init() {}
    }

    public var config: Config
    private var lastKind: GuidanceCue.Kind?
    private var lastSpokenAt: Double?
    private var lastZone: ProximityZone?
    private var announcedArrival = false

    public init(config: Config = Config()) { self.config = config }

    public func reset() {
        lastKind = nil; lastSpokenAt = nil; lastZone = nil; announcedArrival = false
    }

    /// Returns a phrase to speak now, or nil to stay quiet.
    public func phrase(for cue: GuidanceCue, now: Double) -> String? {
        let result = decide(cue, now: now)
        // Only remember what was actually spoken, so a suppressed change is still pending next time.
        if result != nil { lastKind = cue.kind }
        return result
    }

    private func decide(_ cue: GuidanceCue, now: Double) -> String? {
        let since = lastSpokenAt.map { now - $0 } ?? .infinity
        switch cue.kind {
        case .arrived:
            guard !announcedArrival else { return nil }
            announcedArrival = true
            lastSpokenAt = now
            return cue.phase == .toAnchor ? "You are at the starting point. Now following the path." : "You have arrived."
        case .lost:
            guard lastKind != .lost || since >= config.repeatInterval * 2 else { return nil }
            lastSpokenAt = now
            return cue.phase == .toAnchor ? "Waiting for a better location signal." : "I lost the path. Walk back the way you came, or try again from the starting point."
        case .needHeading:
            guard lastKind != .needHeading || since >= config.repeatInterval else { return nil }
            lastSpokenAt = now
            return "Take a few steps so I can tell which way you are facing."
        case .proximity(let estimate):
            let zoneChanged = estimate.zone != lastZone
            lastZone = estimate.zone
            guard zoneChanged || since >= config.repeatInterval else { return nil }
            lastSpokenAt = now
            switch estimate.zone {
            case .here: return "It is right here, within arm's reach."
            case .near: return "Very close. Slow down and feel around."
            case .close: return estimate.trend == .receding ? "Close, but getting weaker. Try another direction." : "Close. Keep going."
            case .far: return estimate.trend == .approaching ? "Signal getting stronger. Keep going." : "I can hear the beacon but it is far. Try walking in a different direction."
            case .lost: return "I lost the beacon's signal."
            }
        case .go(let direction):
            let changed: Bool
            if case .go(let previous) = lastKind { changed = previous != direction } else { changed = true }
            let urgent = direction == .turnAround
            if changed {
                guard urgent || since >= config.minimumGap || lastSpokenAt == nil else { return nil }
            } else {
                guard since >= config.repeatInterval else { return nil }
            }
            lastSpokenAt = now
            let distance = cue.distanceRemaining.map { Self.spokenDistance($0, metric: config.useMetric) }
            if changed, direction != .ahead { return direction.spoken + "." }
            if let distance { return "\(direction.spoken), \(distance)." }
            return direction.spoken + "."
        }
    }

    public static func spokenDistance(_ metres: Double, metric: Bool = true) -> String {
        if metric {
            if metres < 1 { return "less than a metre" }
            if metres < 20 { return "\(Int(metres.rounded())) metres" }
            if metres < 100 { return "about \(Int((metres / 5).rounded()) * 5) metres" }
            return "about \(Int((metres / 10).rounded()) * 10) metres"
        }
        let feet = metres * 3.28084
        if feet < 3 { return "a couple of feet" }
        if feet < 60 { return "\(Int(feet.rounded())) feet" }
        return "about \(Int((feet / 10).rounded()) * 10) feet"
    }
}
