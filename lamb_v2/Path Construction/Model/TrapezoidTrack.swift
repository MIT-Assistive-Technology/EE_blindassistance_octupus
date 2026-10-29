import Darwin
import Foundation

struct TrapezoidTrack {
    var east = 0.0
    var north = 0.0
    var velocityEast = Stats.Path.initialEast
    var velocityNorth = Stats.Path.initialNorth
    var maximumSpeed = 0.0
    private var previous: (time: Double, east: Double, north: Double)?
    private var points: [PathPoint] = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: 0)]
    private var nextID = 1

    mutating func reset() {
        east = 0; north = 0
        velocityEast = Stats.Path.initialEast
        velocityNorth = Stats.Path.initialNorth
        maximumSpeed = 0
        previous = nil
        points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: 0)]
        nextID = 1
    }

    mutating func advance(time: Double, east accelEast: Double, north accelNorth: Double, biasEast: Double = 0, biasNorth: Double = 0, hold: Bool = false) {
        let eastAccel = accelEast - biasEast
        let northAccel = accelNorth - biasNorth
        guard let prior = previous else {
            previous = (time, eastAccel, northAccel)
            return
        }
        let dt = time - prior.time
        previous = (time, eastAccel, northAccel)
        guard dt > 0 else { return }
        if dt > Stats.Path.gapReset {
            velocityEast = Stats.Path.initialEast
            velocityNorth = Stats.Path.initialNorth
            return
        }
        let step = min(dt, Stats.Path.maximumDelta)
        let oldEast = velocityEast, oldNorth = velocityNorth
        if hold {
            velocityEast = 0; velocityNorth = 0
        } else {
            velocityEast = oldEast + (prior.east + eastAccel) / 2 * step
            velocityNorth = oldNorth + (prior.north + northAccel) / 2 * step
        }
        east += (oldEast + velocityEast) / 2 * step
        north += (oldNorth + velocityNorth) / 2 * step
        maximumSpeed = max(maximumSpeed, hypot(velocityEast, velocityNorth))
        let heading = atan2(velocityNorth, velocityEast)
        points.append(PathPoint(id: nextID, time: time, east: east, north: north, heading: heading))
        nextID += 1
    }

    func finish(id: String, name: String, detail: String) -> PathLine {
        let drift = hypot(velocityEast - Stats.Path.initialEast, velocityNorth - Stats.Path.initialNorth)
        return PathLine(id: id, name: name, points: points, finalDisplacement: hypot(east, north), maximumSpeed: maximumSpeed, velocityDrift: drift, detail: detail)
    }
}
