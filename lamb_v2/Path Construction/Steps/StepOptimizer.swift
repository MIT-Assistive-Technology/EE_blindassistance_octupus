import Darwin
import Foundation

struct StepOptimizer: OfflinePath {
    let id = "h2"
    let name = "H2 Step optimizer"

    func run(_ samples: [Sample]) -> PathLine {
        let marks = StepFinder.marks(in: samples)
        guard marks.count >= 2 else {
            return PathLine.empty(id: id, name: name)
        }
        let start = samples.first(where: \.isPath)
        var heading = start?.heading ?? Stats.Heading.initial
        var lastTime = start?.elapsed ?? 0
        var deltas: [Double] = []
        var cursor = 0
        for sample in samples where sample.isPath {
            let dt = sample.elapsed - lastTime
            if dt > 0, dt < Stats.Path.gapReset {
                heading = HeadingMath.wrap(heading + (sample.yawRate - Stats.Heading.gyroBias) * min(dt, Stats.Path.maximumDelta))
            }
            lastTime = sample.elapsed
            if cursor < marks.count, sample.elapsed >= marks[cursor].peak {
                deltas.append(heading)
                cursor += 1
            }
        }
        while deltas.count < marks.count { deltas.append(heading) }
        var east = [0.0]
        var north = [0.0]
        var headings = [heading]
        for index in marks.indices {
            let move = HeadingMath.step(length: Stats.Length.normal, heading: deltas[index])
            east.append(east[index] + move.east)
            north.append(north[index] + move.north)
            headings.append(deltas[index])
        }
        let hop = max(1, Stats.Offline.windowSteps - Stats.Offline.overlapSteps)
        var from = 0
        while from < marks.count {
            let end = min(marks.count, from + Stats.Offline.windowSteps)
            refine(from: from, to: end, east: &east, north: &north, headings: &headings, gyro: deltas)
            if end == marks.count { break }
            from += hop
        }
        var points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: headings[0])]
        for index in marks.indices {
            points.append(PathPoint(id: index + 1, time: marks[index].peak, east: east[index + 1], north: north[index + 1], heading: headings[index + 1]))
        }
        let endEast = east.last ?? 0, endNorth = north.last ?? 0
        return PathLine(id: id, name: name, points: points, finalDisplacement: hypot(endEast, endNorth), maximumSpeed: 0, velocityDrift: 0, detail: "Offline steps \(marks.count)")
    }

    private func refine(from start: Int, to end: Int, east: inout [Double], north: inout [Double], headings: inout [Double], gyro: [Double]) {
        guard end > start else { return }
        let locked = start == 0 ? 0 : start + Stats.Offline.overlapSteps
        for _ in 0..<Stats.Offline.iterations {
            for index in start..<end {
                let target = gyro[min(index, gyro.count - 1)]
                headings[index + 1] = HeadingMath.blend(headings[index + 1], target, gain: 0.5)
                let move = HeadingMath.step(length: Stats.Length.normal, heading: headings[index + 1])
                let proposedEast = east[index] + move.east
                let proposedNorth = north[index] + move.north
                let error = hypot(proposedEast - east[index + 1], proposedNorth - north[index + 1])
                var weight = 1.0
                if Stats.Offline.useHuberOnSteps, error > Stats.Offline.huberDelta, error > 0 {
                    weight = Stats.Offline.huberDelta / error
                }
                guard index + 1 > locked else { continue }
                east[index + 1] += (proposedEast - east[index + 1]) * weight
                north[index + 1] += (proposedNorth - north[index + 1]) * weight
            }
        }
    }
}
