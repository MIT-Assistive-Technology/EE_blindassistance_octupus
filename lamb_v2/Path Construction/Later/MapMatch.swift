import Foundation

enum MapMatch {
    static let slot = UnavailableVariant(id: "j", name: "J Map match", reason: "No map is loaded")

    static func snap(east: Double, north: Double) -> (east: Double, north: Double)? { nil }
}
