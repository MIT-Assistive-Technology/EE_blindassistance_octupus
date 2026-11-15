import Foundation

/// A shareable bundle of places: a mapped building from an orientation specialist, a friend's
/// favourite spots, or a backup of your own. It is one JSON file (`.json`).
public struct PlacePack: Codable, Equatable, Sendable {
    public static let format = "octopi-pack"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var name: String
    public var author: String?
    public var notes: String?
    public var createdAt: Date
    public var places: [Place]

    public init(name: String, author: String? = nil, notes: String? = nil, createdAt: Date = Date(), places: [Place]) {
        format = Self.format
        version = Self.currentVersion
        self.name = name
        self.author = author
        self.notes = notes
        self.createdAt = createdAt
        self.places = places
    }

    public enum PackError: Error, Equatable, LocalizedError {
        case notAPack
        case unsupportedVersion(Int)
        case empty

        public var errorDescription: String? {
            switch self {
            case .notAPack: "This file is not an Octopi pack."
            case .unsupportedVersion(let v): "This pack uses format version \(v), which this app cannot read."
            case .empty: "This pack has no places in it."
            }
        }
    }

    public enum MergePolicy: Sendable {
        /// Keep what the phone already has when a place with the same id (or same beacon) exists.
        case skipExisting
        /// Overwrite existing places with the pack's version.
        case replaceExisting
    }

    public struct MergeResult: Equatable, Sendable {
        public var places: [Place]
        public var added: Int
        public var replaced: Int
        public var skipped: Int

        public var spoken: String {
            var parts: [String] = []
            if added > 0 { parts.append("\(added) added") }
            if replaced > 0 { parts.append("\(replaced) replaced") }
            if skipped > 0 { parts.append("\(skipped) already on this phone") }
            return parts.isEmpty ? "Nothing to import." : parts.joined(separator: ", ") + "."
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func encoded() throws -> Data { try Self.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> PlacePack {
        guard let pack = try? decoder.decode(PlacePack.self, from: data), pack.format == format else { throw PackError.notAPack }
        guard pack.version <= currentVersion else { throw PackError.unsupportedVersion(pack.version) }
        guard !pack.places.isEmpty else { throw PackError.empty }
        return pack
    }

    /// Merge the pack into `existing`. Imported places are marked `.imported` and carry the pack name as `source`.
    public func merge(into existing: [Place], policy: MergePolicy = .skipExisting) -> MergeResult {
        var result = existing
        var added = 0, replaced = 0, skipped = 0
        for var incoming in places {
            incoming.origin = .imported
            incoming.source = name
            let match = result.firstIndex { $0.id == incoming.id }
                ?? incoming.kind.beaconIdentifier.flatMap { id in result.firstIndex { $0.kind.beaconIdentifier == id } }
            if let match {
                switch policy {
                case .skipExisting: skipped += 1
                case .replaceExisting: result[match] = incoming; replaced += 1
                }
            } else {
                result.insert(incoming, at: 0)
                added += 1
            }
        }
        return MergeResult(places: result, added: added, replaced: replaced, skipped: skipped)
    }
}
