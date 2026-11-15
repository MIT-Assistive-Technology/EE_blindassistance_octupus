import Darwin
import Foundation

struct GyroIntegrator {
    var heading = Stats.Heading.initial
    private var lastTime: Double?
    private var slow = 0.0
    private var hold = 0.0
    private var turn = 0.0
    private var base = Stats.Heading.initial
    private var active = false

    mutating func reset() {
        heading = Stats.Heading.initial
        lastTime = nil
        slow = 0
        hold = 0
        turn = 0
        base = Stats.Heading.initial
        active = false
    }

    mutating func nudge(toward aim: Double, gain: Double) {
        base = HeadingMath.blend(base, aim, gain: gain)
        publish()
    }

    mutating func push(_ sample: Sample) {
        guard sample.isPath else { return }
        guard let last = lastTime else {
            lastTime = sample.elapsed
            base = sample.heading
            publish()
            return
        }
        let dt = sample.elapsed - last
        lastTime = sample.elapsed
        guard dt > 0, dt < Stats.Path.gapReset else { return }
        let step = min(dt, Stats.Path.maximumDelta)
        let rate = sample.yawRate
        slow += (rate - slow) * (1 - exp(-step / Stats.Heading.turnSmooth))
        if !active {
            if hold != 0, slow * hold < 0, abs(slow) > Stats.Heading.turnReversal { hold = 0 }
            hold += slow * step
            if abs(hold) >= Stats.Heading.turnCommit {
                active = true
                turn = hold
            }
            publish()
            return
        }
        turn += slow * step
        if abs(slow) <= Stats.Heading.turnSettle {
            base = HeadingMath.wrap(base + snap(turn))
            turn = 0
            hold = 0
            active = false
        }
        publish()
    }

    private mutating func publish() {
        heading = active ? HeadingMath.wrap(base + turn) : base
    }

    private func snap(_ angle: Double) -> Double {
        var degrees = angle * 180 / .pi
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        let targets = [0.0, 90.0, -90.0, 180.0, -180.0]
        var chosen = angle
        var best = Stats.Heading.turnSnap + 1
        for target in targets {
            var error = abs(degrees - target)
            if abs(target) == 180 { error = min(abs(degrees - 180), abs(degrees + 180)) }
            guard error <= Stats.Heading.turnSnap, error < best else { continue }
            best = error
            if target == 0 { chosen = 0 }
            else if abs(target) == 180 { chosen = degrees >= 0 ? .pi : -.pi }
            else { chosen = target * .pi / 180 }
        }
        return chosen
    }
}
