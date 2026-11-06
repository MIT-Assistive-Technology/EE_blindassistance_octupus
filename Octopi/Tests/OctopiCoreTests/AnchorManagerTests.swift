import Foundation
import Testing
@testable import OctopiCore

@Suite struct AnchorManagerTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func firstUsableFixBecomesAnchor() {
        let manager = AnchorManager()
        let decision = manager.offer(fix(accuracy: 8, at: t0), now: t0)
        #expect(decision.newAnchor?.quality == .good)
        #expect(manager.current?.fix.horizontalAccuracy == 8)
    }

    @Test func coarseAndOldFixesAreRejected() {
        let manager = AnchorManager()
        #expect(manager.offer(fix(accuracy: 60, at: t0), now: t0) == .rejected(reason: "accuracy 60 m is too coarse"))
        #expect(manager.current == nil)
        let stale = fix(accuracy: 5, at: t0.addingTimeInterval(-30))
        if case .rejected = manager.offer(stale, now: t0) {} else { Issue.record("old fix should be rejected") }
        #expect(manager.consecutiveBadFixes == 2)
    }

    @Test func invalidFixIsRejected() {
        let manager = AnchorManager()
        let bad = GeoFix(latitude: 0, longitude: 0, horizontalAccuracy: -1, timestamp: t0)
        if case .rejected = manager.offer(bad, now: t0) {} else { Issue.record("invalid fix should be rejected") }
    }

    @Test func implausibleJumpIsRejected() {
        let manager = AnchorManager()
        manager.offer(fix(accuracy: 5, at: t0), now: t0)
        let far = fix(lat: 42.3601 + 0.01, accuracy: 5, at: t0.addingTimeInterval(5))
        if case .rejected(let reason) = manager.offer(far, now: t0.addingTimeInterval(5)) {
            #expect(reason.contains("jump"))
        } else { Issue.record("1 km in 5 s should be rejected") }
    }

    @Test func fixThatDisagreesWithStepsIsRejected() {
        let manager = AnchorManager()
        let origin = fix(accuracy: 5, at: t0)
        manager.offer(origin, now: t0)
        // GPS says we moved 60 m north, steps say we walked 50 m east.
        let later = t0.addingTimeInterval(40)
        let gps = GeoMath.offset(origin, by: LocalPoint(east: 0, north: 60))
        var moved = gps; moved.timestamp = later
        let decision = manager.offer(moved, now: later, pdrDisplacement: LocalPoint(east: 50, north: 0), pdrDistance: 50)
        if case .rejected(let reason) = decision { #expect(reason.contains("disagrees")) } else { Issue.record("should reject, got \(decision)") }
        // And agreeing movement is accepted as a refresh.
        let agree = GeoMath.offset(origin, by: LocalPoint(east: 52, north: 1))
        var agreeing = agree; agreeing.timestamp = later
        #expect(manager.offer(agreeing, now: later, pdrDisplacement: LocalPoint(east: 50, north: 0), pdrDistance: 50).newAnchor != nil)
    }

    @Test func fairFixDoesNotReplaceGoodAnchorUntilStale() {
        let manager = AnchorManager()
        manager.offer(fix(accuracy: 5, at: t0), now: t0)
        let fair = fix(accuracy: 20, at: t0.addingTimeInterval(10))
        if case .kept = manager.offer(fair, now: t0.addingTimeInterval(10)) {} else { Issue.record("fair fix should be kept") }
        let later = t0.addingTimeInterval(7 * 3600)
        let fairLater = fix(accuracy: 20, at: later)
        #expect(manager.offer(fairLater, now: later).newAnchor?.quality == .fair)
    }

    @Test func goodFixRefreshesAnchorAfterInterval() {
        let manager = AnchorManager()
        manager.offer(fix(accuracy: 5, at: t0), now: t0)
        let worse = fix(accuracy: 10, at: t0.addingTimeInterval(30))
        if case .kept = manager.offer(worse, now: t0.addingTimeInterval(30)) {} else { Issue.record("worse fix should be kept") }
        let refresh = fix(accuracy: 10, at: t0.addingTimeInterval(200))
        #expect(manager.offer(refresh, now: t0.addingTimeInterval(200)).newAnchor != nil)
    }

    @Test func qualityDecaysWithAge() {
        let manager = AnchorManager()
        let anchor = Anchor(fix: fix(accuracy: 5, at: t0), quality: .good, establishedAt: t0)
        #expect(manager.quality(of: anchor, now: t0.addingTimeInterval(3600)) == .good)
        #expect(manager.quality(of: anchor, now: t0.addingTimeInterval(7 * 3600)) == .fair)
        #expect(manager.quality(of: anchor, now: t0.addingTimeInterval(30 * 3600)) == .poor)
    }

    @Test func degradedSignalFlagAfterBadFixes() {
        let manager = AnchorManager()
        for i in 0..<3 { manager.offer(fix(accuracy: 80, at: t0.addingTimeInterval(Double(i))), now: t0.addingTimeInterval(Double(i))) }
        #expect(manager.isSignalDegraded)
        manager.offer(fix(accuracy: 5, at: t0.addingTimeInterval(4)), now: t0.addingTimeInterval(4))
        #expect(!manager.isSignalDegraded)
    }
}
