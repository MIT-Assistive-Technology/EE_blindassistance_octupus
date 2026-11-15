import Darwin
import Foundation

final class WalkPath: OnlinePath {
    let id: String
    let name: String
    private let weinberg: Bool
    private var finder = StepFinder()
    private var course = WalkCourse()
    private var strides: [Stride] = []
    private var clamped = 0

    init(id: String, name: String, weinberg: Bool) {
        self.id = id
        self.name = name
        self.weinberg = weinberg
    }

    func reset() {
        finder.reset()
        course.reset()
        strides.removeAll()
        clamped = 0
    }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        course.push(sample)
        guard let step = finder.push(sample) else { return }
        let nominal = weinberg
            ? StepLengthModel.weinberg(range: step.maximum - step.minimum, clamped: &clamped, coefficient: Stats.Walk.coefficient)
            : Stats.Length.normal
        let length = weinberg ? course.pace(nominal, at: step.peak) : nominal
        let choice = course.note(step.peak)
        if let from = choice.from {
            for index in strides.indices where strides[index].time >= from {
                strides[index].heading = choice.heading
            }
        }
        strides.append(Stride(time: step.peak, length: length, heading: choice.heading))
    }

    func line() -> PathLine {
        let trail = StepTrail()
        for stride in strides {
            trail.add(time: stride.time, length: stride.length, heading: stride.heading)
        }
        let detail = weinberg ? "Turns \(course.turns), clamped \(clamped)" : "Turns \(course.turns)"
        return trail.line(id: id, name: name, detail: detail)
    }
}

private struct Stride {
    var time: Double
    var length: Double
    var heading: Double
}

private struct WalkCourse {
    private(set) var heading = Stats.Heading.initial
    private(set) var turns = 0
    private var base = Stats.Heading.initial
    private var lastTime: Double?
    private var slow = 0.0
    private var hold = 0.0
    private var turn = 0.0
    private var active = false
    private var armed = false
    private var steps = 0
    private var pending = false
    private var followed = 0
    private var turnStart = 0.0
    private var snapped = 0.0
    private var lastStep = -1e9

    struct Choice {
        var heading: Double
        var from: Double?
    }

    mutating func reset() {
        heading = Stats.Heading.initial
        turns = 0
        base = Stats.Heading.initial
        lastTime = nil
        slow = 0
        hold = 0
        turn = 0
        active = false
        armed = false
        steps = 0
        pending = false
        followed = 0
        turnStart = 0
        snapped = 0
        lastStep = -1e9
    }

    mutating func push(_ sample: Sample) {
        guard sample.isPath else { return }
        guard let last = lastTime else {
            lastTime = sample.elapsed
            base = sample.heading
            heading = base
            return
        }
        let dt = sample.elapsed - last
        lastTime = sample.elapsed
        guard dt > 0, dt < Stats.Path.gapReset else { return }
        let step = min(dt, Stats.Path.maximumDelta)
        slow += (sample.yawRate - slow) * (1 - exp(-step / Stats.Heading.turnSmooth))
        guard armed, !pending else { return }
        if !active {
            if hold != 0, slow * hold < 0, abs(slow) > Stats.Heading.turnReversal {
                hold = 0
            }
            hold += slow * step
            if abs(hold) >= Stats.Heading.turnCommit {
                active = true
                turn = hold
                turnStart = sample.elapsed
            }
            return
        }
        turn += slow * step
        if abs(slow) <= Stats.Heading.turnSettle {
            if let snapped = snap(turn) {
                self.snapped = snapped
                pending = true
                followed = 0
            }
            active = false
            turn = 0
            hold = 0
        }
    }

    func pace(_ nominal: Double, at time: Double) -> Double {
        guard lastStep >= 0 else { return nominal }
        let gap = time - lastStep
        guard gap > 0, gap <= Stats.Walk.paceCap else { return nominal }
        let scaled = nominal * gap / Stats.Walk.pacePeriod
        return min(max(scaled, Stats.Walk.paceMin), Stats.Walk.paceMax)
    }

    mutating func note(_ time: Double) -> Choice {
        steps += 1
        if steps == Stats.Walk.stepsBeforeTurn {
            armed = true
            hold = 0
            slow = 0
        }
        var from: Double?
        if pending {
            if time - lastStep > Stats.Walk.turnGap {
                pending = false
                followed = 0
            } else {
                followed += 1
                if followed >= Stats.Walk.stepsAfterTurn {
                    base = HeadingMath.wrap(base + snapped)
                    heading = base
                    turns += 1
                    from = turnStart
                    pending = false
                    followed = 0
                }
            }
        }
        lastStep = time
        return Choice(heading: heading, from: from)
    }

    private func snap(_ angle: Double) -> Double? {
        var degrees = angle * 180 / .pi
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        let targets = [0.0, 90.0, -90.0, 180.0, -180.0]
        var chosen = 0.0
        var best = Stats.Walk.turnSnap + 1
        var hit = false
        for target in targets {
            var error = abs(degrees - target)
            if abs(target) == 180 { error = min(abs(degrees - 180), abs(degrees + 180)) }
            guard error <= Stats.Walk.turnSnap, error < best else { continue }
            best = error
            hit = true
            if target == 0 { chosen = 0 }
            else if abs(target) == 180 { chosen = degrees >= 0 ? .pi : -.pi }
            else { chosen = target * .pi / 180 }
        }
        guard hit, chosen != 0 else { return nil }
        return chosen
    }
}
