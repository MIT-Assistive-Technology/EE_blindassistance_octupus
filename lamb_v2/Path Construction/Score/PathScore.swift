import Darwin
import Foundation

struct PathScore {
    var endError: Double
    var lengthError: Double
    var meanMiss: Double
    var maxMiss: Double
    var fittedYawDegrees: Double

    static func measure(_ line: PathLine, planned: PathLine) -> PathScore {
        let plannedPath = vertices(planned.points)
        let linePath = vertices(line.points)
        let plannedSamples = samples(plannedPath)
        let lineSamples = samples(linePath)
        let fixed = mismatch(from: plannedSamples, onto: linePath, and: lineSamples, onto: plannedPath)
        let end = hypot(lastEast(line) - lastEast(planned), lastNorth(line) - lastNorth(planned))
        let length = abs(polylineLength(linePath) - polylineLength(plannedPath))
        var bestYaw = 0.0
        var bestMiss = mismatch(from: plannedSamples, onto: lineSamples, and: lineSamples, onto: plannedPath).mean
        var degree = -179
        while degree <= 180 {
            let yaw = Double(degree) * .pi / 180
            let rotated = rotate(lineSamples, yaw: yaw)
            let trial = mismatch(from: plannedSamples, onto: rotated, and: rotated, onto: plannedPath).mean
            if trial < bestMiss {
                bestMiss = trial
                bestYaw = Double(degree)
            }
            degree += 1
        }
        return PathScore(endError: end, lengthError: length, meanMiss: fixed.mean, maxMiss: fixed.max, fittedYawDegrees: bestYaw)
    }

    private struct Vertex {
        var east: Double
        var north: Double
    }

    private static func vertices(_ points: [PathPoint]) -> [Vertex] {
        points.map { Vertex(east: $0.east, north: $0.north) }
    }

    private static func lastEast(_ line: PathLine) -> Double { line.points.last?.east ?? 0 }
    private static func lastNorth(_ line: PathLine) -> Double { line.points.last?.north ?? 0 }

    private static func polylineLength(_ points: [Vertex]) -> Double {
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for index in 1..<points.count {
            sum += hypot(points[index].east - points[index - 1].east, points[index].north - points[index - 1].north)
        }
        return sum
    }

    private static func samples(_ points: [Vertex], step: Double = 0.5) -> [Vertex] {
        guard let first = points.first else { return [] }
        var out = [first]
        guard points.count >= 2 else { return out }
        var traveled = 0.0
        var next = step
        var previous = first
        for point in points.dropFirst() {
            let dx = point.east - previous.east
            let dy = point.north - previous.north
            let span = hypot(dx, dy)
            if span > 0 {
                while traveled + span >= next - 1e-9 {
                    let t = (next - traveled) / span
                    out.append(Vertex(east: previous.east + dx * t, north: previous.north + dy * t))
                    next += step
                }
                traveled += span
            }
            previous = point
        }
        if let last = points.last, hypot(last.east - out[out.count - 1].east, last.north - out[out.count - 1].north) > 1e-6 {
            out.append(last)
        }
        return out
    }

    private static func rotate(_ points: [Vertex], yaw: Double) -> [Vertex] {
        let turn = cos(yaw)
        let rise = sin(yaw)
        return points.map { Vertex(east: $0.east * turn - $0.north * rise, north: $0.east * rise + $0.north * turn) }
    }

    private static func mismatch(from planned: [Vertex], onto line: [Vertex], and walked: [Vertex], onto reference: [Vertex]) -> (mean: Double, max: Double) {
        var values: [Double] = []
        values.reserveCapacity(planned.count + walked.count)
        for point in planned { values.append(nearest(point, on: line)) }
        for point in walked { values.append(nearest(point, on: reference)) }
        guard !values.isEmpty else { return (0, 0) }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0)
    }

    private static func nearest(_ point: Vertex, on path: [Vertex]) -> Double {
        guard let first = path.first else { return 0 }
        guard path.count >= 2 else { return hypot(point.east - first.east, point.north - first.north) }
        var best = Double.greatestFiniteMagnitude
        for index in 1..<path.count {
            let start = path[index - 1]
            let end = path[index]
            let dx = end.east - start.east
            let dy = end.north - start.north
            let span = dx * dx + dy * dy
            var t = 0.0
            if span > 0 {
                t = ((point.east - start.east) * dx + (point.north - start.north) * dy) / span
                t = min(1, max(0, t))
            }
            let east = start.east + t * dx
            let north = start.north + t * dy
            best = min(best, hypot(point.east - east, point.north - north))
        }
        return best
    }
}
