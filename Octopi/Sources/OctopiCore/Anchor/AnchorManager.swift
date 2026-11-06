import Foundation

/// Tunable thresholds for accepting GPS fixes as anchors.
public struct AnchorPolicy: Sendable {
    /// Accuracy (m) at or below which a fix is "good" and may replace a good anchor.
    public var goodAccuracy = 12.0
    /// Accuracy (m) at or below which a fix is usable at all.
    public var usableAccuracy = 25.0
    /// Fixes older than this (s) when offered are ignored.
    public var maxFixAge = 10.0
    /// Walking speed (m/s) above which a jump between fixes is implausible.
    public var maxSpeed = 4.0
    /// Minimum PDR distance (m) before we compare GPS movement with step movement.
    public var minimumPDRDistanceForCheck = 5.0
    /// Fraction of the PDR distance allowed as disagreement between GPS and steps.
    public var pdrAgreementSlack = 0.25
    /// Age (s) after which a good anchor is refreshed by any good fix.
    public var refreshAfter = 120.0
    /// Age (s) after which an anchor is stale and confidence starts dropping.
    public var staleAfter = 6 * 3600.0
    /// Age (s) after which an anchor is treated as poor regardless of its original accuracy.
    public var expireAfter = 24 * 3600.0
    /// Number of consecutive unusable fixes before we say the signal has degraded (likely indoors).
    public var degradedAfterBadFixes = 3

    public init() {}
}

public enum AnchorDecision: Equatable, Sendable {
    /// A new anchor was set. PDR should reset its origin to it.
    case accepted(Anchor, reason: String)
    /// The fix was fine but the current anchor is still better.
    case kept(reason: String)
    /// The fix was not trustworthy.
    case rejected(reason: String)

    public var newAnchor: Anchor? {
        if case .accepted(let anchor, _) = self { return anchor }
        return nil
    }
}

/// Keeps the last trustworthy GPS fix ("anchor") and decides when to replace it.
///
/// Answers the design question "how do we know a GPS fix is good?" with four checks:
/// reported accuracy, fix age, plausibility of the jump from the previous fix, and
/// agreement with the distance the step counter says we walked.
public final class AnchorManager {
    public var policy: AnchorPolicy
    public private(set) var current: Anchor?
    public private(set) var lastFix: GeoFix?
    public private(set) var consecutiveBadFixes = 0
    public private(set) var lastDecision: AnchorDecision?

    public init(policy: AnchorPolicy = AnchorPolicy()) {
        self.policy = policy
    }

    /// True after several unusable fixes in a row, i.e. we have probably gone indoors.
    public var isSignalDegraded: Bool { consecutiveBadFixes >= policy.degradedAfterBadFixes }

    public func reset() {
        current = nil
        lastFix = nil
        consecutiveBadFixes = 0
        lastDecision = nil
    }

    /// Restore a previously saved anchor (e.g. when the app relaunches).
    public func restore(_ anchor: Anchor) {
        current = anchor
    }

    /// Offer a fix. `pdrDisplacement` is where the step counter thinks we are relative to the
    /// current anchor; `pdrDistance` is the metres walked since the anchor was set.
    @discardableResult
    public func offer(_ fix: GeoFix, now: Date, pdrDisplacement: LocalPoint? = nil, pdrDistance: Double = 0) -> AnchorDecision {
        let decision = evaluate(fix, now: now, pdrDisplacement: pdrDisplacement, pdrDistance: pdrDistance)
        lastDecision = decision
        return decision
    }

    private func evaluate(_ fix: GeoFix, now: Date, pdrDisplacement: LocalPoint?, pdrDistance: Double) -> AnchorDecision {
        guard fix.isValid else { return reject("invalid fix") }
        let age = now.timeIntervalSince(fix.timestamp)
        guard age <= policy.maxFixAge else { return reject("fix is \(Int(age)) s old") }
        guard fix.horizontalAccuracy <= policy.usableAccuracy else {
            return reject("accuracy \(Int(fix.horizontalAccuracy)) m is too coarse")
        }
        if let previous = lastFix {
            let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0, dt < 60 {
                let moved = GeoMath.distance(previous, fix)
                let allowed = policy.maxSpeed * dt + previous.horizontalAccuracy + fix.horizontalAccuracy
                if moved > allowed { return reject("implausible jump of \(Int(moved)) m in \(Int(dt)) s") }
            }
        }
        lastFix = fix
        if let anchor = current, let pdr = pdrDisplacement, pdrDistance >= policy.minimumPDRDistanceForCheck {
            let gps = GeoMath.localOffset(from: anchor.fix, to: fix)
            let mismatch = gps.distance(to: pdr)
            let allowed = fix.horizontalAccuracy + anchor.fix.horizontalAccuracy + policy.pdrAgreementSlack * pdrDistance + 3
            if mismatch > allowed {
                consecutiveBadFixes += 1
                return .rejected(reason: "GPS disagrees with steps by \(Int(mismatch)) m")
            }
        }
        consecutiveBadFixes = 0
        let quality = rawQuality(of: fix)
        guard let anchor = current else { return accept(fix, quality: quality, now: now, reason: "first usable fix") }
        let anchorAge = now.timeIntervalSince(anchor.establishedAt)
        let currentQuality = self.quality(of: anchor, now: now)
        if quality == .good {
            if currentQuality < .good { return accept(fix, quality: quality, now: now, reason: "better than current anchor") }
            if fix.horizontalAccuracy <= anchor.fix.horizontalAccuracy + 2 { return accept(fix, quality: quality, now: now, reason: "fresh good fix") }
            if anchorAge >= policy.refreshAfter { return accept(fix, quality: quality, now: now, reason: "refreshing an old anchor") }
            return .kept(reason: "current anchor is more accurate")
        }
        if currentQuality == .poor || anchorAge >= policy.staleAfter {
            return accept(fix, quality: quality, now: now, reason: "current anchor is stale")
        }
        return .kept(reason: "fix is only fair")
    }

    private func accept(_ fix: GeoFix, quality: AnchorQuality, now: Date, reason: String) -> AnchorDecision {
        let anchor = Anchor(fix: fix, quality: quality, establishedAt: now)
        current = anchor
        return .accepted(anchor, reason: reason)
    }

    private func reject(_ reason: String) -> AnchorDecision {
        consecutiveBadFixes += 1
        return .rejected(reason: reason)
    }

    private func rawQuality(of fix: GeoFix) -> AnchorQuality {
        if fix.horizontalAccuracy <= policy.goodAccuracy { return .good }
        if fix.horizontalAccuracy <= policy.usableAccuracy { return .fair }
        return .poor
    }

    /// Quality of an anchor now, after ageing.
    public func quality(of anchor: Anchor, now: Date) -> AnchorQuality {
        let age = now.timeIntervalSince(anchor.establishedAt)
        if age >= policy.expireAfter { return .poor }
        if age >= policy.staleAfter { return min(anchor.quality, .fair) }
        return anchor.quality
    }
}
