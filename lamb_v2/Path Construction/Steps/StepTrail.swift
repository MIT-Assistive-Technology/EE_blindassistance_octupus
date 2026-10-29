import Darwin
import Foundation

final class StepTrail {
    private var east = 0.0
    private var north = 0.0
    private var points: [PathPoint] = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: Stats.Heading.initial)]
    private var nextID = 1

    func reset() {
        east = 0; north = 0; nextID = 1
        points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: Stats.Heading.initial)]
    }

    func add(time: Double, length: Double, heading: Double) {
        let move = HeadingMath.step(length: length, heading: heading)
        east += move.east; north += move.north
        points.append(PathPoint(id: nextID, time: time, east: east, north: north, heading: heading))
        nextID += 1
    }

    func line(id: String, name: String, detail: String) -> PathLine {
        PathLine(id: id, name: name, points: points, finalDisplacement: hypot(east, north), maximumSpeed: 0, velocityDrift: 0, detail: detail)
    }
}
