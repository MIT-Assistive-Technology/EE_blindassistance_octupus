import Foundation

final class TurnPath: OnlinePath {
    let id = "d3"
    let name = "D3 Turn path"
    private var finder = StepFinder()
    private var turns = TurnDetector()
    private var trail = StepTrail()
    private var heading = Stats.Heading.initial
    private var activeStart = 0.0
    private var activeAngle = 0.0
    private var turning = false
    private var seeded = false

    func reset() {
        finder.reset(); turns.reset(); trail.reset()
        heading = Stats.Heading.initial; turning = false; seeded = false
    }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        if !seeded { heading = sample.heading; seeded = true }
        if let event = turns.push(sample) {
            heading = HeadingMath.wrap(heading + event.angle)
            turning = false
        } else if abs(sample.yawRate) >= Stats.Heading.turnStart, !turning {
            turning = true; activeStart = sample.elapsed; activeAngle = 0
        } else if turning {
            activeAngle += sample.yawRate * Stats.Log.pathInterval
        }
        guard let step = finder.push(sample) else { return }
        var used = heading
        if turning, step.peak >= activeStart {
            let span = max(sample.elapsed - activeStart, 1e-3)
            let fraction = min(1, max(0, (step.peak - activeStart) / span))
            used = HeadingMath.wrap(heading + activeAngle * fraction)
        }
        trail.add(time: step.peak, length: Stats.Length.normal, heading: used)
    }

    func line() -> PathLine { trail.line(id: id, name: name, detail: "Turns \(turns.events.count)") }
}
