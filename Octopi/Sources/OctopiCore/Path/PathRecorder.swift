import Foundation

public struct PathPolicy: Sendable {
    /// Heading change (degrees) at a simplified vertex that counts as a turn the user should feel.
    public var turnThresholdDegrees = 35.0
    /// Spacing (m) of extra waypoints on straight runs; ~10 ft as asked for in co-design.
    public var spacing = 3.0
    /// Douglas–Peucker tolerance (m). Smaller keeps more wiggles.
    public var simplifyEpsilon = 0.8
    /// Hard cap on stored waypoints.
    public var maxWaypoints = 200
    /// Hard cap on stored path length (m). Beyond this the oldest part is dropped.
    public var maxLength = 400.0

    public init() {}
}

/// Collects PDR steps while recording and produces a bounded `StoredPath` when finished.
public final class PathRecorder {
    public var policy: PathPolicy
    private var raw: [(time: Double, point: LocalPoint)] = []
    public private(set) var walkedLength = 0.0
    public private(set) var isRecording = false

    public init(policy: PathPolicy = PathPolicy()) {
        self.policy = policy
    }

    public var pointCount: Int { raw.count }

    public func start(at origin: LocalPoint = .origin, time: Double = 0) {
        raw = [(time, origin)]
        walkedLength = 0
        isRecording = true
    }

    public func add(_ step: StepRecord) {
        guard isRecording else { return }
        if let last = raw.last { walkedLength += last.point.distance(to: step.position) }
        raw.append((step.time, step.position))
    }

    /// Rebase every recorded point when the anchor moves (new origin expressed in the old frame).
    public func rebase(to newOrigin: LocalPoint) {
        raw = raw.map { ($0.time, $0.point - newOrigin) }
    }

    public func cancel() {
        raw.removeAll()
        walkedLength = 0
        isRecording = false
    }

    /// Build a path from what has been recorded so far without stopping. `until` cuts the recording at a
    /// time (used when a beacon stopped moving earlier); `appending` adds a final point (the estimated spot).
    public func snapshot(until time: Double? = nil, appending end: LocalPoint? = nil) -> StoredPath {
        var subset = time.map { t in raw.filter { $0.time <= t } } ?? raw
        if subset.isEmpty, let first = raw.first { subset = [first] }
        if let end { subset.append((time ?? (subset.last?.time ?? 0), end)) }
        var length = 0.0
        if subset.count > 1 {
            for index in 1..<subset.count { length += subset[index - 1].point.distance(to: subset[index].point) }
        }
        return Self.build(subset, walkedLength: length, policy: policy)
    }

    /// Finish recording and build the simplified path.
    public func finish() -> StoredPath {
        isRecording = false
        defer { raw.removeAll() }
        return Self.build(raw, walkedLength: walkedLength, policy: policy)
    }

    static func build(_ raw: [(time: Double, point: LocalPoint)], walkedLength: Double, policy: PathPolicy) -> StoredPath {
        guard raw.count >= 2 else {
            let only = raw.first.map { [Waypoint(point: $0.point, kind: .start, time: $0.time)] } ?? []
            return StoredPath(waypoints: only, walkedLength: walkedLength)
        }
        var points = raw
        var truncated = false
        // Length cap: keep the most recent part of the walk.
        if walkedLength > policy.maxLength {
            var kept: [(time: Double, point: LocalPoint)] = [points[points.count - 1]]
            var total = 0.0
            var index = points.count - 2
            while index >= 0 {
                total += points[index].point.distance(to: points[index + 1].point)
                if total > policy.maxLength { break }
                kept.append(points[index])
                index -= 1
            }
            points = kept.reversed()
            truncated = true
        }
        let coords = points.map(\.point)
        let keptIndices = PathSimplifier.douglasPeucker(coords, epsilon: policy.simplifyEpsilon)
        var waypoints: [Waypoint] = []
        for (position, index) in keptIndices.enumerated() {
            let kind: WaypointKind
            if position == 0 { kind = .start }
            else if position == keptIndices.count - 1 { kind = .end }
            else {
                let angle = PathSimplifier.turnAngle(coords[keptIndices[position - 1]], coords[index], coords[keptIndices[position + 1]])
                kind = angle >= policy.turnThresholdDegrees ? .turn : .spacing
            }
            waypoints.append(Waypoint(point: coords[index], kind: kind, time: points[index].time))
        }
        // Drop simplifier vertices that are not turns; they are re-added as spacing points below.
        let vertices = waypoints.filter { $0.kind != .spacing }
        var spaced = withSpacing(vertices, spacing: policy.spacing)
        if spaced.count > policy.maxWaypoints {
            spaced = withSpacing(vertices, spacing: policy.spacing * 2)
        }
        if spaced.count > policy.maxWaypoints {
            spaced = vertices
        }
        if spaced.count > policy.maxWaypoints {
            spaced = Array(spaced.suffix(policy.maxWaypoints))
            spaced[0].kind = .start
            truncated = true
        }
        return StoredPath(waypoints: spaced, walkedLength: walkedLength, truncated: truncated)
    }

    static func withSpacing(_ vertices: [Waypoint], spacing: Double) -> [Waypoint] {
        guard vertices.count > 1, spacing > 0 else { return vertices }
        var result: [Waypoint] = [vertices[0]]
        for index in 1..<vertices.count {
            let a = vertices[index - 1], b = vertices[index]
            let length = a.point.distance(to: b.point)
            let pieces = Int((length / spacing).rounded(.up))
            if pieces >= 2 {
                for piece in 1..<pieces {
                    let t = Double(piece) / Double(pieces)
                    let point = LocalPoint(east: a.point.east + (b.point.east - a.point.east) * t,
                                           north: a.point.north + (b.point.north - a.point.north) * t)
                    result.append(Waypoint(point: point, kind: .spacing, time: a.time + (b.time - a.time) * t))
                }
            }
            result.append(b)
        }
        return result
    }
}
