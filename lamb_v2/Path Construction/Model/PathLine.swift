import Foundation

struct PathPoint: Identifiable {
    var id: Int
    var time: Double
    var east: Double
    var north: Double
    var heading: Double
}

struct PathLine: Identifiable {
    var id: String
    var name: String
    var points: [PathPoint]
    var finalDisplacement: Double
    var maximumSpeed: Double
    var velocityDrift: Double
    var detail: String

    static func empty(id: String, name: String) -> PathLine {
        PathLine(id: id, name: name, points: [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: 0)], finalDisplacement: 0, maximumSpeed: 0, velocityDrift: 0, detail: "")
    }
}

protocol OnlinePath: AnyObject {
    var id: String { get }
    var name: String { get }
    func reset()
    func push(_ sample: Sample)
    func line() -> PathLine
}

protocol OfflinePath {
    var id: String { get }
    var name: String { get }
    func run(_ samples: [Sample]) -> PathLine
}

struct UnavailableVariant: Identifiable {
    var id: String
    var name: String
    var reason: String
}

struct StepMark {
    var start: Double
    var peak: Double
    var end: Double
    var minimum: Double
    var maximum: Double
    var frequency: Double
}
