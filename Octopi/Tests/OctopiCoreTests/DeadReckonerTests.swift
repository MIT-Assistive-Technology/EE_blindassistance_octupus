import Foundation
import Testing
@testable import OctopiCore

@Suite struct DeadReckonerTests {
    @Test func straightWalkProducesStepsAlongHeading() {
        var sim = WalkSimulator()
        sim.walk(seconds: 20, walkHeading: north)
        let pdr = DeadReckoner()
        for s in sim.samples { pdr.push(s) }
        #expect(pdr.stepCount >= 30 && pdr.stepCount <= 38, "steps: \(pdr.stepCount)")
        let expected = Double(pdr.stepCount) * StepLengthModel.cadence(1.8)
        #expect(approx(pdr.position.north, expected, tolerance: 1.5))
        #expect(abs(pdr.position.east) < 1.0)
        #expect(pdr.compassBearing.map { approx($0, 0, tolerance: 2) || approx($0, 360, tolerance: 2) } == true)
        #expect(pdr.isMoving(at: sim.time))
        #expect(!pdr.isMoving(at: sim.time + 10))
    }

    @Test func fixedStepLengthOption() {
        var sim = WalkSimulator()
        sim.walk(seconds: 10, walkHeading: east)
        var config = PDRConfig(); config.stepLength = .fixed
        let pdr = DeadReckoner(config: config)
        for s in sim.samples { pdr.push(s) }
        #expect(approx(pdr.distanceSinceReset, Double(pdr.stepCount) * Stats.Length.normal, tolerance: 1e-9))
    }

    @Test func turningUpdatesHeadingByGyro() {
        var sim = WalkSimulator()
        var heading = east
        sim.walk(seconds: 10, walkHeading: heading)
        sim.turn(by: .pi / 2, seconds: 1, from: &heading)
        sim.walk(seconds: 10, walkHeading: heading)
        let pdr = DeadReckoner()
        for s in sim.samples { pdr.push(s) }
        #expect(pdr.position.east > 8)
        #expect(pdr.position.north > 8)
        #expect(approx(pdr.heading ?? 0, north, tolerance: 0.15))
    }

    @Test func resetAndRebase() {
        var sim = WalkSimulator()
        sim.walk(seconds: 10, walkHeading: east)
        let pdr = DeadReckoner()
        for s in sim.samples { pdr.push(s) }
        let before = pdr.position
        pdr.rebase(to: LocalPoint(east: 2, north: 0))
        #expect(approx(pdr.position.east, before.east - 2, tolerance: 1e-9))
        pdr.reset()
        #expect(pdr.position == .origin)
        #expect(pdr.stepCount == 0)
        #expect(pdr.heading != nil, "heading survives a reset")
        pdr.resetAll()
        #expect(pdr.heading == nil)
    }

    @Test func positionAtTimeInterpolates() {
        var sim = WalkSimulator()
        sim.walk(seconds: 10, walkHeading: east)
        let pdr = DeadReckoner()
        for s in sim.samples { pdr.push(s) }
        let mid = pdr.steps[pdr.steps.count / 2]
        let next = pdr.steps[pdr.steps.count / 2 + 1]
        let between = pdr.position(at: (mid.time + next.time) / 2)
        #expect(between.east > mid.position.east && between.east < next.position.east)
        #expect(pdr.position(at: -1) == .origin)
        #expect(pdr.position(at: 1e9) == pdr.position)
        #expect(pdr.distanceWalked(from: mid.time, to: next.time) == next.length)
    }

    @Test func driftGrowsWithDistance() {
        let pdr = DeadReckoner()
        #expect(pdr.driftEstimate == pdr.config.driftFloor)
        var sim = WalkSimulator()
        sim.walk(seconds: 30, walkHeading: east)
        for s in sim.samples { pdr.push(s) }
        #expect(pdr.driftEstimate > pdr.config.driftFloor + 1)
    }

    @Test func walkingAxisCorrectsPocketOffset() {
        // Phone points 90° left of the walking direction (like a pocket); body accelerates along the walk.
        var sim = WalkSimulator()
        sim.walk(seconds: 20, walkHeading: north, deviceOffset: .pi / 2)
        var config = PDRConfig(); config.heading = .walkingAxis
        let corrected = DeadReckoner(config: config)
        let raw = DeadReckoner()
        for s in sim.samples { corrected.push(s); raw.push(s) }
        #expect(raw.position.east < -8, "device heading alone walks west")
        #expect(corrected.position.north > 8, "axis-corrected heading walks north: \(corrected.position)")
        #expect(abs(corrected.position.east) < 4)
    }
}
