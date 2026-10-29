import Foundation

enum LoopClosure {
    static let slot = UnavailableVariant(id: "i", name: "I Loop closure", reason: "No revisit detector")

    static func constraint(points: [PathPoint]) -> (start: Int, end: Int)? { nil }
}
