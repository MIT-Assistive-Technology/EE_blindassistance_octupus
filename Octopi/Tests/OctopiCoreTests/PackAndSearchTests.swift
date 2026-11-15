import Foundation
import Testing
@testable import OctopiCore

@Suite struct PlacePackTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func samplePlaces() -> [Place] {
        let anchor = Anchor(fix: GeoFix(latitude: 42.3601, longitude: -71.0942, horizontalAccuracy: 6, timestamp: t0), quality: .good, establishedAt: t0)
        let path = StoredPath(waypoints: [
            Waypoint(point: .origin, kind: .start, time: 0),
            Waypoint(point: LocalPoint(east: 12, north: 0), kind: .turn, time: 15),
            Waypoint(point: LocalPoint(east: 12, north: 8), kind: .end, time: 25)
        ], walkedLength: 20.5)
        return [
            Place(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Front desk", kind: .virtualPin, origin: .app, anchor: anchor, path: path, confidence: Confidence(value: 0.9), createdAt: t0),
            Place(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Bathroom", kind: .virtualPin, origin: .bandButton, anchor: anchor, path: path, confidence: Confidence(value: 0.8, reasons: ["Several hours old"]), createdAt: t0.addingTimeInterval(60)),
            Place(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Keys", kind: .physicalBeacon(BeaconIdentifier("OCT-00001001")), origin: .leftBehind, anchor: nil, path: .empty, confidence: Confidence(value: 0.5, reasons: ["No GPS anchor"]), createdAt: t0.addingTimeInterval(120), frameID: UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        ]
    }

    static func samplePack() -> PlacePack {
        PlacePack(name: "Student Center", author: "O&M office", notes: "Ground floor, from the Mass Ave entrance.", createdAt: t0, places: samplePlaces())
    }

    @Test func roundTrip() throws {
        let pack = Self.samplePack()
        let data = try pack.encoded()
        let decoded = try PlacePack.decode(data)
        #expect(decoded == pack)
        #expect(decoded.format == "octopi-pack" && decoded.version == 1)
    }

    @Test func fixtureStaysReadable() throws {
        let url = Bundle.module.url(forResource: "sample-pack", withExtension: "json")
        let data = try #require(url.flatMap { try? Data(contentsOf: $0) })
        let pack = try PlacePack.decode(data)
        #expect(pack.name == "Student Center" && pack.places.count == 3)
        #expect(pack.places[2].kind == .physicalBeacon(BeaconIdentifier("OCT-00001001")))
    }

    @Test func rejectsForeignAndFutureFiles() throws {
        #expect(throws: PlacePack.PackError.notAPack) { try PlacePack.decode(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: PlacePack.PackError.notAPack) { try PlacePack.decode(Data("not json".utf8)) }
        var future = Self.samplePack(); future.version = 99
        #expect(throws: PlacePack.PackError.unsupportedVersion(99)) { try PlacePack.decode(try future.encoded()) }
        let empty = PlacePack(name: "x", places: [])
        #expect(throws: PlacePack.PackError.empty) { try PlacePack.decode(try empty.encoded()) }
        #expect(PlacePack.PackError.notAPack.errorDescription?.isEmpty == false)
    }

    @Test func mergeSkipsOrReplacesExisting() {
        let pack = Self.samplePack()
        var mine = Place(name: "My seat", kind: .virtualPin, origin: .app, anchor: nil, path: .empty, confidence: Confidence(value: 1), createdAt: Date())
        mine.id = UUID()
        var sameKeys = pack.places[2]; sameKeys.id = UUID(); sameKeys.name = "My keys"
        let existing = [mine, sameKeys]
        let skipped = pack.merge(into: existing)
        #expect(skipped.added == 2 && skipped.skipped == 1 && skipped.replaced == 0)
        #expect(skipped.places.count == 4)
        #expect(skipped.places.first?.origin == .imported && skipped.places.first?.source == "Student Center")
        #expect(skipped.places.contains { $0.name == "My keys" }, "the phone's own beacon record is kept")
        #expect(skipped.spoken == "2 added, 1 already on this phone.")
        let replaced = pack.merge(into: existing, policy: .replaceExisting)
        #expect(replaced.added == 2 && replaced.replaced == 1)
        #expect(replaced.places.contains { $0.name == "Keys" } && !replaced.places.contains { $0.name == "My keys" })
        #expect(PlacePack(name: "e", places: []).merge(into: existing).spoken == "Nothing to import.")
    }

    @Test func sessionImportAndExport() {
        let store = InMemoryPlaceStore()
        let haptics = FakeHaptics()
        let session = OctopiSession(store: store, haptics: haptics, clock: { 0 })
        var spoken: [String] = []
        session.onAnnouncement = { spoken.append($0.text) }
        let result = session.importPack(Self.samplePack())
        #expect(result.added == 3 && session.places.count == 3)
        #expect(store.places.count == 3)
        #expect(spoken.last == "Imported Student Center: 3 added.")
        #expect(haptics.patterns.last == .pinConfirmed)
        let again = session.importPack(Self.samplePack())
        #expect(again.skipped == 3 && session.places.count == 3)
        let export = session.exportPack(name: "Backup", placeIDs: [session.places[0].id])
        #expect(export.places.count == 1 && export.name == "Backup")
        #expect(session.exportPack(name: "All").places.count == 3)
    }
}

@Suite struct PlaceSearchTests {
    let places = PlacePackTests.samplePlaces()

    @Test func filtersByKindAndOrigin() {
        #expect(PlaceSearch.apply(places, filter: .pins).map(\.name) == ["Bathroom", "Front desk"])
        #expect(PlaceSearch.apply(places, filter: .beacons).map(\.name) == ["Keys"])
        #expect(PlaceSearch.apply(places, filter: .imported).isEmpty)
        var imported = places[0]; imported.origin = .imported; imported.source = "Student Center"
        #expect(PlaceSearch.apply([imported] + places.dropFirst(), filter: .imported).count == 1)
    }

    @Test func queryMatchesEveryWordAgainstNameAndPackName() {
        #expect(PlaceSearch.apply(places, query: "front").map(\.name) == ["Front desk"])
        #expect(PlaceSearch.apply(places, query: "FRONT DESK").count == 1)
        #expect(PlaceSearch.apply(places, query: "front keys").isEmpty)
        var imported = places[1]; imported.source = "Student Center"
        #expect(PlaceSearch.apply([imported], query: "student").count == 1)
        #expect(PlaceSearch.apply(places, query: "   ").count == 3)
    }

    @Test func sorting() {
        #expect(PlaceSearch.apply(places, sort: .recent).map(\.name) == ["Keys", "Bathroom", "Front desk"])
        #expect(PlaceSearch.apply(places, sort: .name).map(\.name) == ["Bathroom", "Front desk", "Keys"])
    }

    @Test func spokenCounts() {
        #expect(PlaceSearch.spokenCount(1, query: "") == "1 place")
        #expect(PlaceSearch.spokenCount(3, query: "") == "3 places")
        #expect(PlaceSearch.spokenCount(0, query: "x") == "No places match")
        #expect(PlaceSearch.spokenCount(1, query: "x") == "1 place matches")
        #expect(PlaceSearch.spokenCount(2, query: "x") == "2 places match")
        #expect(PlaceFilter.allCases.allSatisfy { !$0.title.isEmpty } && PlaceSort.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
