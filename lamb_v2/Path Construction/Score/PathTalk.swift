import Darwin
import Foundation

enum PathTalk {
    static func say(_ line: PathLine) -> String {
        var legs: [(heading: Double, meters: Double)] = []
        let points = line.points
        guard points.count >= 2 else { return "Stand" }
        for index in 1..<points.count {
            let east = points[index].east - points[index - 1].east
            let north = points[index].north - points[index - 1].north
            let length = hypot(east, north)
            guard length >= 0.05 else { continue }
            let heading = atan2(north, east)
            if let last = legs.last, abs(HeadingMath.wrap(heading - last.heading)) < 25 * .pi / 180 {
                legs[legs.count - 1].meters += length
            } else {
                legs.append((heading, length))
            }
        }
        legs.removeAll { $0.meters < 0.4 }
        guard let first = legs.first else { return "Stand" }
        var words = ["Walk forward \(meters(first.meters))"]
        for index in 1..<legs.count {
            let turn = HeadingMath.wrap(legs[index].heading - legs[index - 1].heading) * 180 / .pi
            words.append(turnWord(turn))
            words.append("walk forward \(meters(legs[index].meters))")
        }
        return words.joined(separator: ", ")
    }

    private static func meters(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return String(format: "%.0f m", locale: Locale(identifier: "en_US_POSIX"), rounded)
        }
        return String(format: "%.1f m", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    private static func turnWord(_ degrees: Double) -> String {
        let mag = abs(degrees)
        let way = degrees > 0 ? "left" : "right"
        if mag >= 150 { return "turn around" }
        if abs(mag - 90) <= 20 { return "turn \(way)" }
        return "turn \(way) \(Int(mag.rounded()))°"
    }
}
