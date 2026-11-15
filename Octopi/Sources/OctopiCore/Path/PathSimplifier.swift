import Foundation

/// Line simplification helpers for stored paths.
public enum PathSimplifier {
    /// Ramer–Douglas–Peucker on a polyline. Returns the indices of the kept points, always including both ends.
    public static func douglasPeucker(_ points: [LocalPoint], epsilon: Double) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            var maxDistance = 0.0
            var index = first
            for i in (first + 1)..<last {
                let d = perpendicularDistance(points[i], from: points[first], to: points[last])
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > epsilon {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return points.indices.filter { keep[$0] }
    }

    /// Distance from `p` to the segment `a`–`b`.
    public static func perpendicularDistance(_ p: LocalPoint, from a: LocalPoint, to b: LocalPoint) -> Double {
        let dx = b.east - a.east, dy = b.north - a.north
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.east - a.east) * dx + (p.north - a.north) * dy) / lengthSquared))
        let projection = LocalPoint(east: a.east + t * dx, north: a.north + t * dy)
        return p.distance(to: projection)
    }

    /// Turn angle at vertex `b` of a–b–c in degrees, 0 for straight.
    public static func turnAngle(_ a: LocalPoint, _ b: LocalPoint, _ c: LocalPoint) -> Double {
        let incoming = a.heading(to: b)
        let outgoing = b.heading(to: c)
        return abs(HeadingMath.wrap(outgoing - incoming)) * 180 / .pi
    }
}
