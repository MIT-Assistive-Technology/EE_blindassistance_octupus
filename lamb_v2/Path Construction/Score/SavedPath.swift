import Foundation

enum SavedPath {
    static func write(_ lines: [PathLine], beside csv: URL) -> URL? {
        let url = csv.deletingPathExtension().appendingPathExtension("path").appendingPathExtension("csv")
        var rows = ["line,name,time,east,north,heading"]
        for line in lines {
            let name = line.name.replacingOccurrences(of: ",", with: " ")
            for point in line.points {
                rows.append([
                    line.id, name,
                    num(point.time), num(point.east), num(point.north), num(point.heading)
                ].joined(separator: ","))
            }
        }
        do {
            try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func url(beside csv: URL) -> URL {
        csv.deletingPathExtension().appendingPathExtension("path").appendingPathExtension("csv")
    }

    private static func num(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
