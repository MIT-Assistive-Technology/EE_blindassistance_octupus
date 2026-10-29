import Foundation

final class TunedAttitude: OnlinePath {
    let id: String
    let name: String
    let detail: String
    let proportional: Double
    let integral: Double
    private var attitude = AttitudeEstimate()
    private var track = TrapezoidTrack()

    init(id: String, name: String, detail: String, proportional: Double, integral: Double) {
        self.id = id
        self.name = name
        self.detail = detail
        self.proportional = proportional
        self.integral = integral
    }

    func reset() { attitude.reset(); track.reset() }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        let accel = attitude.update(sample, proportional: proportional, integralGain: integral)
        track.advance(time: sample.elapsed, east: accel.east, north: accel.north)
    }

    func line() -> PathLine { track.finish(id: id, name: name, detail: detail) }
}
