import Foundation

/// A position in metres relative to an anchor: east is +x, north is +y.
nonisolated public struct LocalPoint: Codable, Equatable, Hashable, Sendable {
    public var east: Double
    public var north: Double

    public init(east: Double, north: Double) {
        self.east = east
        self.north = north
    }

    public static let origin = LocalPoint(east: 0, north: 0)

    public func distance(to other: LocalPoint) -> Double {
        ((east - other.east) * (east - other.east) + (north - other.north) * (north - other.north)).squareRoot()
    }

    /// Heading from this point to `other` in radians, counter-clockwise from east (the PDR convention).
    public func heading(to other: LocalPoint) -> Double {
        atan2(other.north - north, other.east - east)
    }

    public static func + (lhs: LocalPoint, rhs: LocalPoint) -> LocalPoint {
        LocalPoint(east: lhs.east + rhs.east, north: lhs.north + rhs.north)
    }

    public static func - (lhs: LocalPoint, rhs: LocalPoint) -> LocalPoint {
        LocalPoint(east: lhs.east - rhs.east, north: lhs.north - rhs.north)
    }
}
