import Foundation

struct StepWalk {
    var finder = StepFinder()
    var gyro = GyroIntegrator()
    var history = HeadingHistory()
    var trail = StepTrail()
    var clamped = 0
    var held: Double?

    mutating func reset() {
        finder.reset(); gyro.reset(); history.reset(); trail.reset()
        clamped = 0; held = nil
    }

    mutating func push(
        _ sample: Sample,
        length: (StepMark, inout StepWalk) -> Double = { _, _ in Stats.Length.normal },
        tune: (inout StepWalk, Sample) -> Void = { _, _ in }
    ) {
        guard sample.isPath else { return }
        gyro.push(sample)
        tune(&self, sample)
        history.add(time: sample.elapsed, heading: gyro.heading)
        guard let step = finder.push(sample) else { return }
        let chosen = length(step, &self)
        let heading = history.heading(at: step.peak)
        trail.add(time: step.peak, length: chosen, heading: heading)
    }

    func line(id: String, name: String, detail: String) -> PathLine {
        trail.line(id: id, name: name, detail: detail)
    }
}
