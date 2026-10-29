import Foundation

final class BiasCalibration: OnlinePath {
    let id = "a2"
    let name = "A2 Start bias"
    private var track = TrapezoidTrack()
    private var window = StationaryWindow()
    private var eastSum = 0.0
    private var northSum = 0.0
    private var count = 0

    func reset() {
        track.reset(); window.reset(); eastSum = 0; northSum = 0; count = 0
    }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        if sample.elapsed <= Stats.Path.biasWindow, window.isConfident(after: sample) {
            eastSum += sample.eastAcceleration
            northSum += sample.northAcceleration
            count += 1
        }
        let biasEast = count > 0 ? eastSum / Double(count) : 0
        let biasNorth = count > 0 ? northSum / Double(count) : 0
        track.advance(time: sample.elapsed, east: sample.eastAcceleration, north: sample.northAcceleration, biasEast: biasEast, biasNorth: biasNorth)
    }

    func line() -> PathLine {
        track.finish(id: id, name: name, detail: count > 0 ? "Bias from \(count) still samples" : "No still window")
    }
}
