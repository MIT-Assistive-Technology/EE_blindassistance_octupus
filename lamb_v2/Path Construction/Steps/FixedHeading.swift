import Foundation

final class FixedHeading: OnlinePath {
    let id = "b1"
    let name = "B1 Fixed heading"
    private var finder = StepFinder()
    private var trail = StepTrail()
    private var facing = Stats.Heading.initial
    private var seeded = false

    func reset() { finder.reset(); trail.reset(); facing = Stats.Heading.initial; seeded = false }

    func push(_ sample: Sample) {
        if sample.isPath, !seeded { facing = sample.heading; seeded = true }
        guard let step = finder.push(sample) else { return }
        trail.add(time: step.peak, length: Stats.Length.normal, heading: facing)
    }

    func line() -> PathLine { trail.line(id: id, name: name, detail: "Length \(Stats.Length.normal) m") }
}
