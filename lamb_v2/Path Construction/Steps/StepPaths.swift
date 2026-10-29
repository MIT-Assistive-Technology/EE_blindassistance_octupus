import Foundation

final class GyroHeading: OnlinePath {
    let id = "b2"
    let name = "B2 Gyro heading"
    private var walk = StepWalk()

    func reset() { walk.reset() }
    func push(_ sample: Sample) { walk.push(sample) }
    func line() -> PathLine { walk.line(id: id, name: name, detail: "Length \(Stats.Length.normal) m") }
}

final class GyroIntegration: OnlinePath {
    let id = "d1"
    let name = "D1 Gyro heading"
    private var walk = StepWalk()

    func reset() { walk.reset() }
    func push(_ sample: Sample) { walk.push(sample) }
    func line() -> PathLine { walk.line(id: id, name: name, detail: "World yaw rate") }
}

final class CompassHeading: OnlinePath {
    let id = "b3"
    let name = "B3 Compass heading"
    private var walk = StepWalk()

    func reset() { walk.reset() }

    func push(_ sample: Sample) {
        walk.push(sample, tune: { state, sample in
            guard sample.magneticIsUsable else { return }
            state.gyro.heading = HeadingMath.blend(state.gyro.heading, sample.heading, gain: Stats.Heading.compassBlend)
        })
    }

    func line() -> PathLine {
        walk.line(id: id, name: name, detail: Stats.Heading.useMagnetometer ? "Magnetometer on" : "Magnetometer off")
    }
}

final class MagnetometerHeading: OnlinePath {
    let id = "d4"
    let name = "D4 Magnetometer heading"
    private var walk = StepWalk()

    func reset() { walk.reset() }

    func push(_ sample: Sample) {
        walk.push(sample, tune: { state, sample in
            if Stats.Heading.useMagnetometer, sample.magneticIsUsable {
                state.held = sample.heading
                state.gyro.heading = HeadingMath.blend(state.gyro.heading, sample.heading, gain: Stats.Heading.compassBlend)
            } else if let held = state.held {
                state.gyro.heading = HeadingMath.blend(state.gyro.heading, held, gain: Stats.Heading.compassBlend * 0.25)
            }
        })
    }

    func line() -> PathLine {
        walk.line(id: id, name: name, detail: Stats.Heading.useMagnetometer ? "Compass when calm" : "Magnetometer off")
    }
}

final class CadenceLength: OnlinePath {
    let id = "c1"
    let name = "C1 Cadence length"
    private var walk = StepWalk()

    func reset() { walk.reset() }

    func push(_ sample: Sample) {
        walk.push(sample, length: { step, _ in StepLengthModel.cadence(step.frequency) })
    }

    func line() -> PathLine { walk.line(id: id, name: name, detail: "a \(Stats.Cadence.intercept), b \(Stats.Cadence.slope)") }
}

final class WeinbergLength: OnlinePath {
    let id = "c2"
    let name = "C2 Weinberg length"
    private var walk = StepWalk()

    func reset() { walk.reset() }

    func push(_ sample: Sample) {
        walk.push(sample, length: { step, state in
            StepLengthModel.weinberg(range: step.maximum - step.minimum, clamped: &state.clamped)
        })
    }

    func line() -> PathLine { walk.line(id: id, name: name, detail: "Clamped \(walk.clamped) steps") }
}
