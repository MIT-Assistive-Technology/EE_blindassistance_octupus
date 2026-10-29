import Foundation

final class WorldAccelPath: OnlinePath {
    let id: String
    let name: String
    let detail: String
    private var track = TrapezoidTrack()

    init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    func reset() { track.reset() }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        track.advance(time: sample.elapsed, east: sample.eastAcceleration, north: sample.northAcceleration)
    }

    func line() -> PathLine { track.finish(id: id, name: name, detail: detail) }
}
