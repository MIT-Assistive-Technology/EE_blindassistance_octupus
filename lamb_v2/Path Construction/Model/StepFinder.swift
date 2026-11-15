import Darwin
import Foundation

final class StepFinder {
    private var times: [Double] = []
    private var raw: [Double] = []
    private var smooth: [Double] = []
    private var level = 0.0
    private var primed = false
    private var lastPeak = -1e9
    private(set) var marks: [StepMark] = []

    func reset() {
        times.removeAll(); raw.removeAll(); smooth.removeAll()
        level = 0; primed = false; lastPeak = -1e9; marks.removeAll()
    }

    func push(_ sample: Sample) -> StepMark? {
        guard sample.isPath else { return nil }
        let magnitude = sample.accelerationMagnitude
        let dt = times.last.map { sample.elapsed - $0 } ?? Stats.Log.pathInterval
        let alpha = 1 - exp(-max(dt, 1e-4) / Stats.Steps.smoothSeconds)
        level += (magnitude - level) * (primed ? alpha : 1)
        primed = true
        times.append(sample.elapsed); raw.append(magnitude); smooth.append(level)
        while let first = times.first, sample.elapsed - first > Stats.Steps.levelWindow {
            times.removeFirst(); raw.removeFirst(); smooth.removeFirst()
        }
        guard smooth.count >= 3 else { return nil }
        let index = smooth.count - 2
        let value = smooth[index]
        guard value >= smooth[index - 1], value > smooth[index + 1] else { return nil }
        let mean = smooth.reduce(0, +) / Double(smooth.count)
        var spread = 0.0
        for item in smooth { let delta = item - mean; spread += delta * delta }
        let deviation = (spread / Double(smooth.count)).squareRoot()
        let time = times[index]
        guard value >= max(Stats.Steps.minimumLevel, mean + Stats.Steps.prominenceScale * deviation),
              time - lastPeak >= Stats.Steps.minimumGap else { return nil }
        let previous = marks.last?.peak ?? max(0, time - Stats.Steps.minimumGap)
        var low = raw[index], high = raw[index]
        for cursor in raw.indices where times[cursor] >= previous && times[cursor] <= time {
            low = min(low, raw[cursor]); high = max(high, raw[cursor])
        }
        let period = max(time - previous, 1 / Stats.Steps.maximumFrequency)
        let mark = StepMark(start: previous, peak: time, end: sample.elapsed, minimum: low, maximum: high, frequency: 1 / period)
        lastPeak = time
        marks.append(mark)
        return mark
    }

    static func marks(in samples: [Sample]) -> [StepMark] {
        let finder = StepFinder()
        var found: [StepMark] = []
        for sample in samples { if let mark = finder.push(sample) { found.append(mark) } }
        return found
    }
}
