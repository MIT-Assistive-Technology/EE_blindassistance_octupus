import Foundation
import Testing
@testable import OctopiCore

@Suite struct DirectionTests {
    @Test func bucketsRelativeAngles() {
        #expect(Direction.from(relativeDegrees: 5) == .ahead)
        #expect(Direction.from(relativeDegrees: -15) == .ahead)
        #expect(Direction.from(relativeDegrees: 30) == .slightLeft)
        #expect(Direction.from(relativeDegrees: -30) == .slightRight)
        #expect(Direction.from(relativeDegrees: 90) == .left)
        #expect(Direction.from(relativeDegrees: -90) == .right)
        #expect(Direction.from(relativeDegrees: 130) == .sharpLeft)
        #expect(Direction.from(relativeDegrees: -130) == .sharpRight)
        #expect(Direction.from(relativeDegrees: 170) == .turnAround)
        #expect(Direction.from(relativeDegrees: -180) == .turnAround)
        #expect(Direction.left.hapticPattern == .left && Direction.sharpRight.hapticPattern == .right && Direction.turnAround.hapticPattern == .turnAround)
        #expect(Direction.slightLeft.isLeft && Direction.right.isRight && !Direction.ahead.isLeft)
    }
}

@Suite struct AnchorApproachTests {
    let t0 = Date()

    @Test func arrivesInsideRadius() {
        let approach = AnchorApproach()
        let anchor = Anchor(fix: fix(accuracy: 5, at: t0), quality: .good, establishedAt: t0)
        let nearby = GeoMath.offset(anchor.fix, by: LocalPoint(east: 3, north: 0))
        #expect(approach.cue(from: nearby, to: anchor, userBearing: 0).kind == .arrived)
    }

    @Test func directionRelativeToFacing() {
        let approach = AnchorApproach()
        let anchor = Anchor(fix: fix(accuracy: 5, at: t0), quality: .good, establishedAt: t0)
        // The anchor is 50 m north of us.
        let here = GeoMath.offset(anchor.fix, by: LocalPoint(east: 0, north: -50))
        #expect(approach.cue(from: here, to: anchor, userBearing: 0).kind == .go(.ahead))
        #expect(approach.cue(from: here, to: anchor, userBearing: 90).kind == .go(.left))
        #expect(approach.cue(from: here, to: anchor, userBearing: 270).kind == .go(.right))
        #expect(approach.cue(from: here, to: anchor, userBearing: 180).kind == .go(.turnAround))
        #expect(approach.cue(from: here, to: anchor, userBearing: nil).kind == .needHeading)
        var coarse = here; coarse.horizontalAccuracy = 100
        #expect(approach.cue(from: coarse, to: anchor, userBearing: 0).kind == .lost)
        #expect(approx(approach.cue(from: here, to: anchor, userBearing: 0).distanceToTarget ?? 0, 50, tolerance: 0.1))
    }
}

@Suite struct RouteFollowerTests {
    func path(_ points: [LocalPoint]) -> StoredPath {
        var waypoints = points.enumerated().map { Waypoint(point: $0.element, kind: .spacing, time: Double($0.offset)) }
        waypoints[0].kind = .start
        waypoints[waypoints.count - 1].kind = .end
        return StoredPath(waypoints: waypoints, walkedLength: 0)
    }

    @Test func straightPathGuidesAheadThenArrives() {
        let follower = RouteFollower(path: path([.origin, LocalPoint(east: 5, north: 0), LocalPoint(east: 10, north: 0)]))
        let start = follower.update(position: .origin, heading: east)
        #expect(start.kind == .go(.ahead))
        #expect(approx(start.distanceRemaining ?? 0, 10, tolerance: 1e-9))
        #expect(follower.update(position: LocalPoint(east: 5.5, north: 0.2), heading: east).kind == .go(.ahead))
        #expect(follower.targetIndex == 2)
        #expect(follower.update(position: LocalPoint(east: 9, north: 0), heading: east).kind == .arrived)
    }

    @Test func turnsAreRelativeToHeading() {
        let follower = RouteFollower(path: path([.origin, LocalPoint(east: 0, north: 10)]))
        #expect(follower.update(position: .origin, heading: east).kind == .go(.left))
        #expect(follower.update(position: .origin, heading: west).kind == .go(.right))
        #expect(follower.update(position: .origin, heading: south).kind == .go(.turnAround))
        #expect(follower.update(position: .origin, heading: nil).kind == .needHeading)
    }

    @Test func offTrackRetargetsNearestWaypoint() {
        let follower = RouteFollower(path: path([.origin, LocalPoint(east: 10, north: 0), LocalPoint(east: 20, north: 0), LocalPoint(east: 20, north: 10)]))
        _ = follower.update(position: .origin, heading: east)
        let cue = follower.update(position: LocalPoint(east: 20, north: 8), heading: north)
        #expect(follower.isOffTrack || follower.targetIndex == 3)
        #expect(follower.targetIndex == 3)
        #expect(cue.kind == .go(.ahead))
    }

    @Test func farFromEverythingIsLost() {
        let follower = RouteFollower(path: path([.origin, LocalPoint(east: 10, north: 0)]))
        let cue = follower.update(position: LocalPoint(east: 5, north: 40), heading: east)
        #expect(cue.kind == .lost && cue.phase == .lost)
    }

    @Test func emptyPathIsAlreadyArrived() {
        let follower = RouteFollower(path: .empty)
        #expect(follower.update(position: .origin, heading: east).kind == .arrived)
    }
}

@Suite struct GuidanceNarratorTests {
    @Test func speaksChangesThrottlesRepeats() {
        let narrator = GuidanceNarrator()
        let ahead = GuidanceCue(kind: .go(.ahead), phase: .alongPath, distanceRemaining: 12)
        #expect(narrator.phrase(for: ahead, now: 0) == "Straight ahead, 12 metres.")
        #expect(narrator.phrase(for: ahead, now: 1) == nil)
        #expect(narrator.phrase(for: ahead, now: 9) == "Straight ahead, 12 metres.")
        let left = GuidanceCue(kind: .go(.left), phase: .alongPath, distanceRemaining: 12)
        #expect(narrator.phrase(for: left, now: 10) == nil, "too soon after the last phrase")
        #expect(narrator.phrase(for: left, now: 12) == "Turn left.")
        let around = GuidanceCue(kind: .go(.turnAround), phase: .alongPath)
        #expect(narrator.phrase(for: around, now: 12.1) == "Turn around.", "urgent cues skip the gap")
    }

    @Test func arrivalAndLostAndHeading() {
        let narrator = GuidanceNarrator()
        let arrived = GuidanceCue(kind: .arrived, phase: .alongPath)
        #expect(narrator.phrase(for: arrived, now: 0) == "You have arrived.")
        #expect(narrator.phrase(for: arrived, now: 5) == nil)
        narrator.reset()
        #expect(narrator.phrase(for: GuidanceCue(kind: .arrived, phase: .toAnchor), now: 0)?.contains("starting point") == true)
        #expect(narrator.phrase(for: GuidanceCue(kind: .needHeading, phase: .alongPath), now: 1)?.contains("few steps") == true)
        #expect(narrator.phrase(for: GuidanceCue(kind: .needHeading, phase: .alongPath), now: 2) == nil)
        #expect(narrator.phrase(for: GuidanceCue(kind: .lost, phase: .lost), now: 3)?.contains("lost the path") == true)
        #expect(narrator.phrase(for: GuidanceCue(kind: .lost, phase: .toAnchor), now: 30)?.contains("location signal") == true)
    }

    @Test func proximityZoneChanges() {
        let narrator = GuidanceNarrator()
        func cue(_ zone: ProximityZone, trend: ProximityTrend = .steady) -> GuidanceCue {
            GuidanceCue(kind: .proximity(ProximityEstimate(zone: zone, trend: trend, distance: 3, pulseInterval: 1)), phase: .proximity)
        }
        #expect(narrator.phrase(for: cue(.far), now: 0)?.contains("far") == true)
        #expect(narrator.phrase(for: cue(.far), now: 1) == nil)
        #expect(narrator.phrase(for: cue(.close), now: 2) == "Close. Keep going.")
        #expect(narrator.phrase(for: cue(.close, trend: .receding), now: 12)?.contains("weaker") == true)
        #expect(narrator.phrase(for: cue(.near), now: 13)?.contains("Very close") == true)
        #expect(narrator.phrase(for: cue(.here), now: 14)?.contains("arm's reach") == true)
        #expect(narrator.phrase(for: cue(.lost), now: 15)?.contains("lost") == true)
    }

    @Test func spokenDistances() {
        #expect(GuidanceNarrator.spokenDistance(0.4) == "less than a metre")
        #expect(GuidanceNarrator.spokenDistance(7.4) == "7 metres")
        #expect(GuidanceNarrator.spokenDistance(43) == "about 45 metres")
        #expect(GuidanceNarrator.spokenDistance(127) == "about 130 metres")
        #expect(GuidanceNarrator.spokenDistance(0.5, metric: false) == "a couple of feet")
        #expect(GuidanceNarrator.spokenDistance(10, metric: false) == "33 feet")
        #expect(GuidanceNarrator.spokenDistance(30, metric: false) == "about 100 feet")
    }
}

@Suite struct ConfidenceModelTests {
    @Test func degradesWithEachProblem() {
        let short = StoredPath(waypoints: [], walkedLength: 20)
        let good = ConfidenceModel.estimate(anchorQuality: .good, path: short, driftEstimate: 1, ageSeconds: 60)
        #expect(good.level == .high && good.reasons.isEmpty)
        let noAnchor = ConfidenceModel.estimate(anchorQuality: nil, path: short, driftEstimate: 1, ageSeconds: 60)
        #expect(noAnchor.level == .medium && noAnchor.reasons.contains("No GPS anchor"))
        let old = ConfidenceModel.estimate(anchorQuality: .poor, path: StoredPath(waypoints: [], walkedLength: 300, truncated: true), driftEstimate: 15, ageSeconds: 2 * 86400)
        #expect(old.level == .low && old.value == 0)
        #expect(old.reasons.count == 5)
        #expect(Confidence(value: 2).value == 1 && Confidence(value: -1).value == 0)
        #expect(Confidence(value: 0.8).spoken == "Confidence high")
        #expect(Confidence.Level.low < .high)
    }
}
