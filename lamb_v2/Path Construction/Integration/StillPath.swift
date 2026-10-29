import Foundation

final class StillPath: OnlinePath {
    let id: String
    let name: String
    let detail: String
    private var track = TrapezoidTrack()
    private var window = StationaryWindow()
    private var resets = 0

    init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    func reset() { track.reset(); window.reset(); resets = 0 }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        let hold = window.isConfident(after: sample)
        if hold { resets += 1 }
        track.advance(time: sample.elapsed, east: sample.eastAcceleration, north: sample.northAcceleration, hold: hold)
    }

    func line() -> PathLine { track.finish(id: id, name: name, detail: "\(detail) \(resets)") }
}
