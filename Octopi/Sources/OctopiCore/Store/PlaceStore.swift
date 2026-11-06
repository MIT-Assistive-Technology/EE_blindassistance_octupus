import Foundation

/// Persistence for places. The app uses the JSON store; tests use the in-memory one.
public protocol PlaceStore: AnyObject {
    func load() throws -> [Place]
    func save(_ places: [Place]) throws
}

public final class InMemoryPlaceStore: PlaceStore {
    public private(set) var places: [Place] = []
    public private(set) var saveCount = 0
    public init(places: [Place] = []) { self.places = places }
    public func load() throws -> [Place] { places }
    public func save(_ places: [Place]) throws { self.places = places; saveCount += 1 }
}

/// Stores places as a single JSON file, written atomically.
public final class JSONPlaceStore: PlaceStore {
    public let url: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(url: URL) { self.url = url }

    public static func inDocuments(fileName: String = "octopi_places.json") -> JSONPlaceStore {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return JSONPlaceStore(url: folder.appendingPathComponent(fileName))
    }

    public func load() throws -> [Place] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([Place].self, from: Data(contentsOf: url))
    }

    public func save(_ places: [Place]) throws {
        try encoder.encode(places).write(to: url, options: .atomic)
    }
}

/// App settings that the core needs. The app persists this with UserDefaults.
public struct OctopiSettings: Codable, Equatable, Sendable {
    public enum Sensitivity: String, Codable, Sendable, CaseIterable {
        case low, normal, high
    }

    public var leftBehindSensitivity: Sensitivity = .normal
    public var snoozeMinutes = 10
    public var mirrorHapticsToPhone = true
    public var speakGuidance = true
    public var useMetric = true
    /// Serial of the beacon the band should lock onto in Simple mode.
    public var simpleModeBeaconSerial: UInt32?

    public init() {}

    public var leftBehindPolicy: LeftBehindPolicy {
        var policy = LeftBehindPolicy()
        policy.snoozeSeconds = Double(snoozeMinutes) * 60
        switch leftBehindSensitivity {
        case .low:
            policy.stationarySeconds = 20; policy.walkAwayMetres = 15; policy.confirmSeconds = 10; policy.recedingSeconds = 25
        case .normal:
            break
        case .high:
            policy.stationarySeconds = 6; policy.walkAwayMetres = 5; policy.confirmSeconds = 3; policy.recedingSeconds = 10
        }
        return policy
    }
}
