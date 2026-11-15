import Foundation
import Testing
@testable import OctopiCore

@Suite struct PathSimplifierTests {
    @Test func collinearPointsCollapse() {
        let points = (0...10).map { LocalPoint(east: Double($0), north: 0) }
        #expect(PathSimplifier.douglasPeucker(points, epsilon: 0.5) == [0, 10])
    }

    @Test func cornerIsKept() {
        var points = (0...10).map { LocalPoint(east: Double($0), north: 0) }
        points += (1...10).map { LocalPoint(east: 10, north: Double($0)) }
        #expect(PathSimplifier.douglasPeucker(points, epsilon: 0.5) == [0, 10, 20])
        #expect(approx(PathSimplifier.turnAngle(points[0], points[10], points[20]), 90, tolerance: 1e-9))
    }

    @Test func perpendicularDistance() {
        let a = LocalPoint(east: 0, north: 0), b = LocalPoint(east: 10, north: 0)
        #expect(PathSimplifier.perpendicularDistance(LocalPoint(east: 5, north: 3), from: a, to: b) == 3)
        #expect(PathSimplifier.perpendicularDistance(LocalPoint(east: 13, north: 4), from: a, to: b) == 5)
        #expect(PathSimplifier.perpendicularDistance(LocalPoint(east: 3, north: 4), from: a, to: a) == 5)
    }
}

@Suite struct PathRecorderTests {
    func steps(_ points: [LocalPoint], startTime: Double = 0) -> [StepRecord] {
        points.enumerated().map { StepRecord(time: startTime + Double($0.offset), position: $0.element, heading: 0, length: 0.7) }
    }

    @Test func lShapeKeepsOneTurnAndSpacingPoints() {
        let recorder = PathRecorder()
        recorder.start()
        var points: [LocalPoint] = []
        for i in 1...20 { points.append(LocalPoint(east: Double(i) * 0.5, north: Double.random(in: -0.1...0.1))) }
        for i in 1...14 { points.append(LocalPoint(east: 10, north: Double(i) * 0.5)) }
        for s in steps(points) { recorder.add(s) }
        let path = recorder.finish()
        #expect(path.waypoints.first?.kind == .start)
        #expect(path.waypoints.last?.kind == .end)
        #expect(path.turnCount == 1)
        #expect(approx(path.walkedLength, 17, tolerance: 1.5))
        #expect(approx(path.length, 17, tolerance: 1.0))
        for i in 1..<path.waypoints.count {
            #expect(path.waypoints[i - 1].point.distance(to: path.waypoints[i].point) <= 3.01)
        }
        #expect(!path.truncated)
        #expect(!recorder.isRecording)
    }

    @Test func waypointCapIsEnforced() {
        var policy = PathPolicy(); policy.maxWaypoints = 12
        let recorder = PathRecorder(policy: policy)
        recorder.start()
        // A zig-zag with many turns: 30 corners.
        var points: [LocalPoint] = []
        for i in 0..<30 { points.append(LocalPoint(east: Double(i) * 4, north: i % 2 == 0 ? 0 : 4)) }
        for s in steps(points) { recorder.add(s) }
        let path = recorder.finish()
        #expect(path.waypoints.count <= 12)
        #expect(path.truncated)
        #expect(path.waypoints.first?.kind == .start)
    }

    @Test func lengthCapKeepsTheRecentPart() {
        var policy = PathPolicy(); policy.maxLength = 50
        let recorder = PathRecorder(policy: policy)
        recorder.start()
        let points = (1...200).map { LocalPoint(east: Double($0), north: 0) }
        for s in steps(points) { recorder.add(s) }
        let path = recorder.finish()
        #expect(path.truncated)
        #expect(path.length <= 51)
        #expect(path.waypoints.last?.point.east == 200)
        #expect(path.waypoints.first!.point.east >= 149)
    }

    @Test func snapshotUntilTimeAppendsEstimate() {
        let recorder = PathRecorder()
        recorder.start()
        let points = (1...30).map { LocalPoint(east: Double($0), north: 0) }
        for s in steps(points) { recorder.add(s) }
        let cut = recorder.snapshot(until: 10, appending: LocalPoint(east: 10.5, north: 2))
        #expect(cut.waypoints.last?.point == LocalPoint(east: 10.5, north: 2))
        #expect(cut.waypoints.last?.kind == .end)
        #expect(recorder.isRecording, "snapshot does not stop recording")
        let full = recorder.snapshot()
        #expect(full.waypoints.last?.point.east == 30)
    }

    @Test func rebaseShiftsAllPoints() {
        let recorder = PathRecorder()
        recorder.start()
        for s in steps([LocalPoint(east: 5, north: 0), LocalPoint(east: 10, north: 0)]) { recorder.add(s) }
        recorder.rebase(to: LocalPoint(east: 10, north: 0))
        let path = recorder.finish()
        #expect(path.waypoints.last?.point == LocalPoint(east: 0, north: 0))
        #expect(path.waypoints.first?.point == LocalPoint(east: -10, north: 0))
    }

    @Test func emptyAndSinglePointPaths() {
        let recorder = PathRecorder()
        #expect(recorder.finish().isEmpty)
        recorder.start()
        let one = recorder.finish()
        #expect(one.waypoints.count == 1 && one.isEmpty)
        recorder.start()
        recorder.cancel()
        #expect(recorder.pointCount == 0)
    }

    @Test func storedPathCodableRoundTrip() throws {
        let path = StoredPath(waypoints: [Waypoint(point: .origin, kind: .start, time: 0), Waypoint(point: LocalPoint(east: 3, north: 4), kind: .end, time: 5)], walkedLength: 5)
        let data = try JSONEncoder().encode(path)
        #expect(try JSONDecoder().decode(StoredPath.self, from: data) == path)
        #expect(path.length == 5)
    }
}
