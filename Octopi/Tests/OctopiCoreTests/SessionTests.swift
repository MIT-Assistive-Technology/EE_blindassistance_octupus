import Foundation
import Testing
@testable import OctopiCore

/// End-to-end scenarios through the coordinator with simulated sensors.
@Suite struct OctopiSessionTests {
    final class World {
        var now = 0.0
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryPlaceStore()
        let haptics = FakeHaptics()
        var spoken: [Announcement] = []
        var bandCommands: [WearableProtocol.Command] = []
        var s: OctopiSession!
        let home = GeoFix(latitude: 42.3601, longitude: -71.0942, horizontalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        init(settings: OctopiSettings = OctopiSettings()) {
            s = OctopiSession(store: store, haptics: haptics, settings: settings, clock: { [unowned self] in self.now }, wallClock: { [unowned self] in self.wall })
            s.onAnnouncement = { [unowned self] in self.spoken.append($0) }
            s.onBandCommand = { [unowned self] in self.bandCommands.append($0) }
        }

        func advance(_ seconds: Double) { now += seconds; wall = wall.addingTimeInterval(seconds) }

        /// Feed a walk and keep the clocks in step with the samples.
        func feed(_ sim: inout WalkSimulator) {
            for sample in sim.samples {
                if sample.elapsed > now { let d = sample.elapsed - now; advance(d) }
                s.handleMotion(sample)
            }
            sim.samples.removeAll()
        }

        func gps(east: Double = 0, north: Double = 0, accuracy: Double = 5) {
            var f = GeoMath.offset(home, by: LocalPoint(east: east, north: north))
            f.horizontalAccuracy = accuracy
            f.timestamp = wall
            s.handleLocation(f)
        }

        func lastSpoken(containing text: String) -> Bool { spoken.contains { $0.text.localizedCaseInsensitiveContains(text) } }
    }

    @Test func dropPinRecordsPathFromAnchor() {
        let w = World()
        w.gps()
        #expect(w.s.anchors.current != nil)
        #expect(w.lastSpoken(containing: "anchor set"))
        var sim = WalkSimulator(time: w.now)
        sim.walk(seconds: 15, walkHeading: north)
        w.feed(&sim)
        let place = w.s.dropPin(name: "My seat")
        #expect(place.name == "My seat")
        #expect(place.anchor?.fix.latitude == w.home.latitude)
        #expect(place.path.waypoints.count >= 3)
        #expect((place.path.destination?.north ?? 0) > 10)
        #expect(place.confidence.level == .high)
        #expect(w.haptics.patterns.contains(.pinConfirmed))
        #expect(w.lastSpoken(containing: "Pin saved: My seat"))
        #expect(w.store.places.count == 1 && w.store.saveCount == 1)
        #expect(w.s.diagnostics.stepCount > 20)
        let unnamed = w.s.dropPin()
        #expect(unnamed.name.hasPrefix("Pin 2"))
        #expect(w.s.places.first?.id == unnamed.id, "newest first")
    }

    @Test func pinWithoutGPSUsesFrameAndLowerConfidence() {
        let w = World()
        var sim = WalkSimulator(time: w.now)
        sim.walk(seconds: 6, walkHeading: east)
        w.feed(&sim)
        let place = w.s.dropPin(name: "Desk")
        #expect(place.anchor == nil)
        #expect(place.frameID == w.s.frameID)
        #expect(place.confidence.level < .high)
        #expect(w.s.positionInFrame(of: place) != nil)
    }

    @Test func navigateBackToPinArrives() {
        let w = World()
        w.gps()
        var sim = WalkSimulator(time: w.now)
        var heading = north
        sim.walk(seconds: 12, walkHeading: heading)
        w.feed(&sim)
        let place = w.s.dropPin(name: "Table")
        // Walk on another 12 s, then navigate back: we should be told to turn around, then arrive.
        sim.walk(seconds: 12, walkHeading: heading)
        w.feed(&sim)
        w.s.startNavigation(to: place.id)
        #expect(w.s.navigation?.phase == .alongPath)
        #expect(w.lastSpoken(containing: "Guiding you to Table"))
        #expect(w.bandCommands.contains(.setMode(.path)))
        w.s.tick()
        #expect(w.s.navigation?.cue?.kind == .go(.turnAround))
        #expect(w.haptics.patterns.contains(.turnAround))
        sim.turn(by: .pi, seconds: 1.5, from: &heading)
        w.feed(&sim)
        sim.walk(seconds: 20, walkHeading: heading)
        var arrivedAt: Double?
        for sample in sim.samples {
            if sample.elapsed > w.now { w.advance(sample.elapsed - w.now) }
            w.s.handleMotion(sample)
            if w.s.navigation?.phase == .arrived { arrivedAt = sample.elapsed; break }
        }
        #expect(arrivedAt != nil, "should arrive while walking back; last cue \(String(describing: w.s.navigation?.cue))")
        #expect(w.haptics.patterns.contains(.arrived))
        #expect(w.lastSpoken(containing: "arrived"))
        w.s.stopNavigation()
        #expect(w.s.navigation == nil)
        #expect(w.bandCommands.contains(.stop) && w.bandCommands.last == .setMode(.idle))
    }

    @Test func outdoorStartGoesToAnchorFirst() {
        let w = World()
        w.gps()
        var sim = WalkSimulator(time: w.now)
        sim.walk(seconds: 8, walkHeading: east)
        w.feed(&sim)
        let place = w.s.dropPin(name: "Door")
        // Now we are far away outdoors with a fresh fix 80 m south of the anchor.
        w.advance(600)
        w.gps(east: 0, north: -80, accuracy: 6)
        w.s.startNavigation(to: place.id)
        #expect(w.s.navigation?.phase == .toAnchor)
        #expect(w.lastSpoken(containing: "starting point"))
        // Arrive at the anchor: phase switches to the path.
        w.advance(60)
        w.gps(east: 0, north: -2, accuracy: 5)
        #expect(w.s.navigation?.phase == .alongPath)
        #expect(w.s.reckoner.position == .origin, "PDR re-origins at the anchor")
    }

    @Test func leftBehindBeaconCreatesPlaceAndAlert() {
        let w = World()
        w.gps()
        let adv = BeaconAdvertisement(serial: 7, isMoving: true, batteryPercent: 80, secondsSinceMotion: 0)
        w.s.pairBeacon(adv, name: "Keys")
        #expect(w.s.beacons.count == 1)
        // Walk 8 s with the keys moving along.
        var sim = WalkSimulator(time: w.now)
        sim.walk(seconds: 8, walkHeading: east)
        for sample in sim.samples {
            if sample.elapsed > w.now { w.advance(sample.elapsed - w.now) }
            w.s.handleMotion(sample)
            if Int(sample.elapsed * 100) % 100 == 0 { w.s.handleBeacon(adv, rssi: -60) }
        }
        let stoppedAt = w.now
        let stoppedPosition = w.s.reckoner.position
        // Keys stop; we keep walking 30 s and the signal fades.
        sim.samples.removeAll()
        sim.walk(seconds: 30, walkHeading: east)
        for sample in sim.samples {
            if sample.elapsed > w.now { w.advance(sample.elapsed - w.now) }
            w.s.handleMotion(sample)
            if Int(sample.elapsed * 100) % 100 == 0 {
                let age = w.now - stoppedAt
                let still = BeaconAdvertisement(serial: 7, isMoving: false, batteryPercent: 80, secondsSinceMotion: age)
                w.s.handleBeacon(still, rssi: -60 - age)
            }
        }
        #expect(w.s.activeAlert?.name == "Keys")
        #expect(w.haptics.patterns.contains(.leftBehindAlert))
        #expect(w.lastSpoken(containing: "Keys may have been left behind"))
        let place = w.s.places.first { $0.kind.beaconIdentifier == adv.identifier }
        #expect(place?.origin == .leftBehind)
        #expect(place?.path.destination.map { $0.distance(to: stoppedPosition) < 3 } == true, "place is where we were when the keys stopped")
        // Find it: proximity phase takes over once the signal is strong.
        w.s.findLeftBehindItem()
        #expect(w.s.activeAlert == nil)
        #expect(w.s.navigation?.placeName == "Keys")
        for i in 0..<12 { w.advance(1); w.s.handleBeacon(BeaconAdvertisement(serial: 7, isMoving: false, secondsSinceMotion: 60 + Double(i)), rssi: -64) }
        #expect(w.s.navigation?.phase == .proximity, "phase: \(String(describing: w.s.navigation?.phase))")
        #expect(w.haptics.patterns.contains(.proximityPulse))
        for _ in 0..<12 { w.advance(1); w.s.handleBeacon(BeaconAdvertisement(serial: 7, isMoving: false, secondsSinceMotion: 100), rssi: -58) }
        #expect(w.s.navigation?.phase == .arrived)
    }

    @Test func snoozeAndHandOff() {
        let w = World()
        let adv = BeaconAdvertisement(serial: 9, isMoving: true)
        w.s.pairBeacon(adv, name: "Bag")
        w.s.handleBeacon(adv, rssi: -60)
        w.s.setHandedOff(adv.identifier, true)
        #expect(w.s.beacons.first?.isHandedOff == true)
        #expect(w.s.detector.state(of: adv.identifier) == .handedOff)
        #expect(w.lastSpoken(containing: "handed off"))
        w.s.setHandedOff(adv.identifier, false)
        #expect(w.s.detector.state(of: adv.identifier) == .withUser)
        w.s.unpairBeacon(adv.identifier)
        #expect(w.s.beacons.isEmpty)
    }

    @Test func bandButtonsMapToActions() {
        let w = World()
        w.s.handleWearable(.button(.record, .double))
        #expect(w.lastSpoken(containing: "No saved places"))
        #expect(w.haptics.patterns.last == .error)
        w.s.handleWearable(.button(.record, .single))
        #expect(w.s.places.count == 1 && w.s.places[0].origin == .bandButton)
        w.s.handleWearable(.button(.record, .double))
        #expect(w.s.navigation?.placeID == w.s.places[0].id)
        w.s.handleWearable(.button(.record, .long))
        #expect(w.s.navigation == nil)
        w.s.handleWearable(.battery(percent: 33, charging: false))
        #expect(w.s.bandBattery == 33)
        w.s.bandConnectionChanged(connected: true)
        #expect(w.s.bandConnected && w.haptics.patterns.contains(.bandConnected))
        w.s.bandConnectionChanged(connected: false)
        #expect(w.lastSpoken(containing: "Band disconnected"))
    }

    @Test func renameDeleteAndSettings() {
        let w = World()
        let place = w.s.dropPin(name: "A")
        w.s.rename(place.id, to: "B")
        #expect(w.s.places[0].name == "B")
        w.s.startNavigation(to: place.id)
        w.s.delete(place.id)
        #expect(w.s.places.isEmpty && w.s.navigation == nil)
        var settings = OctopiSettings()
        settings.leftBehindSensitivity = .high
        settings.snoozeMinutes = 3
        w.s.settings = settings
        #expect(w.s.detector.policy.walkAwayMetres == 5 && w.s.detector.policy.snoozeSeconds == 180)
        #expect(OctopiSettings().leftBehindPolicy.walkAwayMetres == 8)
        var low = OctopiSettings(); low.leftBehindSensitivity = .low
        #expect(low.leftBehindPolicy.walkAwayMetres == 15)
    }

    @Test func jsonStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("octopi-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONPlaceStore(url: url)
        #expect(try store.load().isEmpty)
        let anchor = Anchor(fix: fix(at: Date()), quality: .good, establishedAt: Date())
        let place = Place(name: "Car", kind: .physicalBeacon(BeaconIdentifier("OCT-00000001")), origin: .leftBehind, anchor: anchor,
                          path: StoredPath(waypoints: [Waypoint(point: .origin, kind: .start, time: 0)], walkedLength: 0),
                          confidence: Confidence(value: 0.9, reasons: ["x"]), createdAt: Date(), pressureDeltaKPa: 0.04)
        try store.save([place])
        let loaded = try store.load()
        #expect(loaded.count == 1 && loaded[0].name == "Car" && loaded[0].kind == place.kind)
        #expect(loaded[0].mayBeOnAnotherFloor)
        #expect(loaded[0].estimatedFix != nil)
        let reopened = OctopiSession(store: store, haptics: FakeHaptics(), clock: { 0 })
        #expect(reopened.places.count == 1)
    }
}
