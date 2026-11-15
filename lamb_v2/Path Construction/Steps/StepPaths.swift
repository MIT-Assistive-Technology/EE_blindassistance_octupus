import Foundation

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
