import Darwin
import Foundation

struct PlannedLeg: Identifiable, Equatable {
    var id = UUID()
    var meters: Double
    var turnDegrees: Double
}

struct PlannedPath: Equatable {
    var facingDegrees = 90.0
    var legs: [PlannedLeg] = []

    static func straight(meters: Double = 20) -> PlannedPath {
        PlannedPath(facingDegrees: 90, legs: [PlannedLeg(meters: meters, turnDegrees: 0)])
    }

    static func outAndBack(meters: Double = 20) -> PlannedPath {
        PlannedPath(facingDegrees: 90, legs: [
            PlannedLeg(meters: meters, turnDegrees: 0),
            PlannedLeg(meters: meters, turnDegrees: 180)
        ])
    }

    static func square(side: Double = 20) -> PlannedPath {
        PlannedPath(facingDegrees: 90, legs: [
            PlannedLeg(meters: side, turnDegrees: 0),
            PlannedLeg(meters: side, turnDegrees: 90),
            PlannedLeg(meters: side, turnDegrees: 90),
            PlannedLeg(meters: side, turnDegrees: 90)
        ])
    }

    func line() -> PathLine {
        var heading = facingDegrees * .pi / 180
        var east = 0.0
        var north = 0.0
        var points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: heading)]
        for (index, leg) in legs.enumerated() {
            heading = HeadingMath.wrap(heading + leg.turnDegrees * .pi / 180)
            let move = HeadingMath.step(length: max(leg.meters, 0), heading: heading)
            east += move.east
            north += move.north
            points.append(PathPoint(id: index + 1, time: 0, east: east, north: north, heading: heading))
        }
        return PathLine(id: "planned", name: "Planned path", points: points, finalDisplacement: hypot(east, north), maximumSpeed: 0, velocityDrift: 0, detail: "")
    }

    static func sidecar(for csv: URL) -> URL {
        csv.deletingPathExtension().appendingPathExtension("planned")
    }

    func save(beside csv: URL?) {
        guard let csv else { return }
        let url = Self.sidecar(for: csv)
        guard !legs.isEmpty else {
            _ = try? FileManager.default.removeItem(at: url)
            return
        }
        var rows = [String(format: "facing,%.3f", locale: Locale(identifier: "en_US_POSIX"), facingDegrees)]
        for leg in legs {
            rows.append(String(format: "%.3f,%.3f", locale: Locale(identifier: "en_US_POSIX"), leg.meters, leg.turnDegrees))
        }
        _ = try? rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func load(beside csv: URL) -> PlannedPath? {
        let planned = sidecar(for: csv)
        let older = csv.deletingPathExtension().appendingPathExtension("course")
        let text = (try? String(contentsOf: planned, encoding: .utf8)) ?? (try? String(contentsOf: older, encoding: .utf8))
        guard let text else { return nil }
        var facing = 90.0
        var legs: [PlannedLeg] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2 else { continue }
            if fields[0] == "facing", let degrees = Double(fields[1]) {
                facing = degrees
            } else if let meters = Double(fields[0]), let turn = Double(fields[1]) {
                legs.append(PlannedLeg(meters: meters, turnDegrees: turn))
            }
        }
        guard !legs.isEmpty else { return nil }
        return PlannedPath(facingDegrees: facing, legs: legs)
    }
}
