import Foundation

public enum PlaceFilter: String, CaseIterable, Sendable {
    case all, pins, beacons, imported

    public var title: String {
        switch self {
        case .all: "All"
        case .pins: "Pins"
        case .beacons: "Beacons"
        case .imported: "Imported"
        }
    }
}

public enum PlaceSort: String, CaseIterable, Sendable {
    case recent, name

    public var title: String {
        switch self {
        case .recent: "Most recent first"
        case .name: "By name"
        }
    }
}

/// Pure search/filter/sort over places. Every word in the query must appear in the name or the pack name.
public enum PlaceSearch {
    public static func apply(_ places: [Place], query: String = "", filter: PlaceFilter = .all, sort: PlaceSort = .recent) -> [Place] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result = places.filter { place in
            switch filter {
            case .all: true
            case .pins: !place.isPhysical
            case .beacons: place.isPhysical
            case .imported: place.origin == .imported
            }
        }
        if !tokens.isEmpty {
            result = result.filter { place in
                let haystack = (place.name + " " + (place.source ?? "")).lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        switch sort {
        case .recent: result.sort { $0.createdAt > $1.createdAt }
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return result
    }

    /// Spoken result count, e.g. "3 places match".
    public static func spokenCount(_ count: Int, query: String) -> String {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return count == 1 ? "1 place" : "\(count) places" }
        return count == 0 ? "No places match" : (count == 1 ? "1 place matches" : "\(count) places match")
    }
}
