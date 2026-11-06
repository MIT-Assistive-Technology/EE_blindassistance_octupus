import Foundation

/// Something to say to the user. The app routes it to VoiceOver or speech.
public struct Announcement: Equatable, Sendable {
    public enum Priority: Int, Sendable, Comparable {
        case low, normal, high
        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public var text: String
    public var priority: Priority
    public init(_ text: String, priority: Priority = .normal) { self.text = text; self.priority = priority }
}

/// A physical beacon the user has paired, whether or not it currently has a place record.
public struct PairedBeacon: Codable, Equatable, Identifiable, Sendable {
    public var id: BeaconIdentifier
    public var serial: UInt32
    public var name: String
    public var lastSeen: Date?
    public var batteryPercent: Int?
    public var lastRSSI: Double?
    public var isHandedOff = false

    public init(id: BeaconIdentifier, serial: UInt32, name: String) {
        self.id = id
        self.serial = serial
        self.name = name
    }
}

public struct NavigationStatus: Equatable, Sendable {
    public var placeID: UUID
    public var placeName: String
    public var phase: NavigationPhase
    public var cue: GuidanceCue?
    public var confidence: Confidence
    /// Spoken summary for the live screen.
    public var spokenSummary: String {
        var parts = [phase.spoken]
        if let cue, case .go(let direction) = cue.kind { parts.append(direction.spoken) }
        if let remaining = cue?.distanceRemaining { parts.append(GuidanceNarrator.spokenDistance(remaining)) }
        return parts.joined(separator: ". ")
    }
}

public struct ActiveAlert: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var beacon: BeaconIdentifier
    public var placeID: UUID
    public var name: String
    public var time: Date
}

public struct SessionDiagnostics: Equatable, Sendable {
    public var stepCount = 0
    public var distanceSinceAnchor = 0.0
    public var compassBearing: Double?
    public var position = LocalPoint.origin
    public var anchorQuality: AnchorQuality?
    public var anchorAgeSeconds: Double?
    public var anchorAccuracy: Double?
    public var driftEstimate = 0.0
    public var gpsDegraded = false
    public var lastAnchorDecision: String?
    public var isMoving = false
}

/// The coordinator: feeds sensors to the modules, owns app state, emits announcements and haptics.
/// The UI talks only to this type.
public final class OctopiSession {
    public var settings: OctopiSettings {
        didSet {
            detector.policy = settings.leftBehindPolicy
            narrator.config.useMetric = settings.useMetric
            (haptics as? HapticRouter)?.mirrorToPhone = settings.mirrorHapticsToPhone
        }
    }
    public let store: PlaceStore
    public let haptics: HapticOutput
    /// Monotonic seconds (the same time base as `MotionSample.elapsed`).
    public let clock: () -> Double
    public let wallClock: () -> Date

    public let anchors: AnchorManager
    public let reckoner: DeadReckoner
    public let recorder: PathRecorder
    public let detector: LeftBehindDetector
    private let approach = AnchorApproach()
    private let proximity = ProximityEstimator()
    private let narrator = GuidanceNarrator()

    public private(set) var places: [Place] = []
    public private(set) var beacons: [PairedBeacon] = []
    public private(set) var navigation: NavigationStatus?
    public private(set) var activeAlert: ActiveAlert?
    public private(set) var bandConnected = false
    public private(set) var bandBattery: Int?
    public private(set) var lastFix: GeoFix?
    public private(set) var diagnostics = SessionDiagnostics()
    public private(set) var frameID = UUID()
    public private(set) var announcements: [Announcement] = []
    /// Latest barometer reading from the phone, if it has one. Used for the "other floor" hint.
    public var currentPressureKPa: Double? {
        didSet { if anchorPressureKPa == nil { anchorPressureKPa = currentPressureKPa } }
    }
    private var anchorPressureKPa: Double?
    private var pressureDelta: Double? {
        guard let current = currentPressureKPa, let anchor = anchorPressureKPa else { return nil }
        return current - anchor
    }

    public var onAnnouncement: ((Announcement) -> Void)?
    public var onBandCommand: ((WearableProtocol.Command) -> Void)?
    public var onPlacesChanged: (() -> Void)?

    private var follower: RouteFollower?
    private var navigatingPlace: Place?
    private var lastHapticKind: GuidanceCue.Kind?
    private var lastHapticAt: Double?
    private var lastProximityIntervalMs: Int?
    private var proximityLostSince: Double?
    private var pinCounter = 0
    private var announcedAnchor = false

    public init(store: PlaceStore, haptics: HapticOutput, settings: OctopiSettings = OctopiSettings(), clock: @escaping () -> Double, wallClock: @escaping () -> Date = { Date() }, pdrConfig: PDRConfig = PDRConfig()) {
        self.store = store
        self.haptics = haptics
        self.settings = settings
        self.clock = clock
        self.wallClock = wallClock
        anchors = AnchorManager()
        reckoner = DeadReckoner(config: pdrConfig)
        recorder = PathRecorder()
        detector = LeftBehindDetector(policy: settings.leftBehindPolicy)
        places = (try? store.load()) ?? []
        pinCounter = places.filter { $0.origin != .leftBehind }.count
        recorder.start(at: .origin, time: clock())
    }

    // MARK: - Sensor inputs

    public func handleMotion(_ sample: MotionSample) {
        guard let step = reckoner.push(sample) else { return }
        recorder.add(step)
        refreshDiagnostics()
        if navigation != nil { updateNavigation() }
    }

    public func handleLocation(_ fix: GeoFix) {
        lastFix = fix
        let decision = anchors.offer(fix, now: wallClock(), pdrDisplacement: reckoner.position, pdrDistance: reckoner.distanceSinceReset)
        switch decision {
        case .accepted(let anchor, let reason):
            diagnostics.lastAnchorDecision = "Anchor set: \(reason)"
            anchorPressureKPa = currentPressureKPa
            reckoner.reset()
            recorder.start(at: .origin, time: clock())
            if !announcedAnchor {
                announcedAnchor = true
                announce("Location anchor set, accuracy \(Int(anchor.fix.horizontalAccuracy)) metres.", priority: .low)
            }
        case .kept(let reason):
            diagnostics.lastAnchorDecision = "Anchor kept: \(reason)"
        case .rejected(let reason):
            diagnostics.lastAnchorDecision = "Fix rejected: \(reason)"
        }
        refreshDiagnostics()
        if navigation?.phase == .toAnchor { updateNavigation() }
    }

    public func handleBeacon(_ advertisement: BeaconAdvertisement, rssi: Double) {
        let now = clock()
        let id = advertisement.identifier
        guard let index = beacons.firstIndex(where: { $0.id == id }) else { return }
        beacons[index].lastSeen = wallClock()
        beacons[index].batteryPercent = advertisement.batteryPercent
        let observation = BeaconObservation(time: now, rssi: rssi, isMoving: advertisement.isMoving,
                                            secondsSinceMotion: advertisement.secondsSinceMotion,
                                            txPowerAt1m: advertisement.txPowerAt1m,
                                            batteryPercent: advertisement.batteryPercent,
                                            isBatteryLow: advertisement.isBatteryLow)
        let events = detector.observe(observation, beacon: id, phone: reckoner)
        beacons[index].lastRSSI = detector.filter(for: id)?.value
        if let placeIndex = places.firstIndex(where: { $0.kind.beaconIdentifier == id }) {
            places[placeIndex].lastHeard = wallClock()
            places[placeIndex].lastRSSI = beacons[index].lastRSSI
        }
        for event in events { handle(event, now: now) }
        if navigation != nil, navigatingPlace?.kind.beaconIdentifier == id { updateNavigation() }
    }

    public func handleWearable(_ event: WearableProtocol.Event) {
        switch event {
        case .button(.record, .single):
            dropPin(origin: .bandButton)
        case .button(.record, .double):
            if let recent = places.first { startNavigation(to: recent.id) }
            else { announce("No saved places yet.", priority: .high); haptics.play(.error, parameterMs: nil) }
        case .button(.record, .long):
            if activeAlert != nil { snoozeAlert() }
            else if navigation != nil { stopNavigation() }
        case .button(.power, _):
            break
        case .battery(let percent, _):
            bandBattery = percent
        case .ack, .modeChanged, .simpleLock:
            break
        }
    }

    public func bandConnectionChanged(connected: Bool) {
        guard connected != bandConnected else { return }
        bandConnected = connected
        if connected {
            onBandCommand?(.setMode(navigation == nil ? .idle : .path))
            haptics.play(.bandConnected, parameterMs: nil)
            announce("Band connected.", priority: .low)
        } else {
            announce("Band disconnected. Guidance continues on the phone.", priority: .high)
        }
    }

    /// Call about once per second.
    public func tick() {
        let now = clock()
        for event in detector.tick(now: now, phone: reckoner) { handle(event, now: now) }
        refreshDiagnostics()
        if navigation != nil { updateNavigation() }
    }

    // MARK: - Commands

    @discardableResult
    public func dropPin(name: String? = nil, origin: PlaceOrigin = .app) -> Place {
        pinCounter += 1
        let now = wallClock()
        let path = recorder.snapshot()
        let anchor = anchors.current
        let confidence = ConfidenceModel.estimate(anchorQuality: anchor.map { anchors.quality(of: $0, now: now) }, path: path, driftEstimate: reckoner.driftEstimate, ageSeconds: 0)
        let place = Place(name: name ?? Self.defaultPinName(pinCounter, at: now), kind: .virtualPin, origin: origin,
                          anchor: anchor, path: path, confidence: confidence, createdAt: now,
                          pressureDeltaKPa: pressureDelta, frameID: anchor == nil ? frameID : nil)
        places.insert(place, at: 0)
        persist()
        haptics.play(.pinConfirmed, parameterMs: nil)
        announce("Pin saved: \(place.name). \(confidence.spoken).", priority: .high)
        return place
    }

    public static func defaultPinName(_ number: Int, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Pin \(number), \(formatter.string(from: date))"
    }

    /// Import a pack of places. Announces the summary.
    @discardableResult
    public func importPack(_ pack: PlacePack, policy: PlacePack.MergePolicy = .skipExisting) -> PlacePack.MergeResult {
        let result = pack.merge(into: places, policy: policy)
        places = result.places
        persist()
        announce("Imported \(pack.name): \(result.spoken)", priority: .high)
        if result.added > 0 || result.replaced > 0 { haptics.play(.pinConfirmed, parameterMs: nil) }
        return result
    }

    /// Bundle places (all by default) into a pack for sharing or backup.
    public func exportPack(name: String, placeIDs: Set<UUID>? = nil, author: String? = nil) -> PlacePack {
        let chosen = placeIDs.map { ids in places.filter { ids.contains($0.id) } } ?? places
        return PlacePack(name: name, author: author, createdAt: wallClock(), places: chosen)
    }

    public func rename(_ placeID: UUID, to name: String) {
        guard let index = places.firstIndex(where: { $0.id == placeID }) else { return }
        places[index].name = name
        if let beaconID = places[index].kind.beaconIdentifier, let b = beacons.firstIndex(where: { $0.id == beaconID }) { beacons[b].name = name }
        persist()
    }

    public func delete(_ placeID: UUID) {
        if navigation?.placeID == placeID { stopNavigation() }
        places.removeAll { $0.id == placeID }
        persist()
    }

    public func pairBeacon(_ advertisement: BeaconAdvertisement, name: String) {
        let id = advertisement.identifier
        if let index = beacons.firstIndex(where: { $0.id == id }) {
            beacons[index].name = name
        } else {
            beacons.append(PairedBeacon(id: id, serial: advertisement.serial, name: name))
        }
        detector.acknowledge(id)
        announce("Beacon paired: \(name).", priority: .normal)
        haptics.play(.pinConfirmed, parameterMs: nil)
    }

    /// Restore beacons paired in an earlier run.
    public func restoreBeacons(_ restored: [PairedBeacon]) {
        beacons = restored
        for beacon in restored where beacon.isHandedOff { detector.setHandedOff(beacon.id, true, now: clock()) }
    }

    public func unpairBeacon(_ id: BeaconIdentifier) {
        beacons.removeAll { $0.id == id }
        detector.forget(id)
        places.removeAll { $0.kind.beaconIdentifier == id }
        persist()
    }

    public func setHandedOff(_ id: BeaconIdentifier, _ handedOff: Bool) {
        guard let index = beacons.firstIndex(where: { $0.id == id }) else { return }
        beacons[index].isHandedOff = handedOff
        detector.setHandedOff(id, handedOff, now: clock())
        announce(handedOff ? "\(beacons[index].name) handed off. I will not warn you about it." : "\(beacons[index].name) is back with you.", priority: .normal)
    }

    /// Tell the band which beacon to lock onto when it is in Simple mode.
    public func setSimpleModeBeacon(_ id: BeaconIdentifier?) {
        settings.simpleModeBeaconSerial = beacons.first { $0.id == id }?.serial
        if let serial = settings.simpleModeBeaconSerial { onBandCommand?(.setSimpleTarget(serial: serial)) }
    }

    public func startNavigation(to placeID: UUID) {
        guard let place = places.first(where: { $0.id == placeID }) else { return }
        if navigation != nil { stopNavigation(quietly: true) }
        narrator.reset()
        lastHapticKind = nil
        lastHapticAt = nil
        lastProximityIntervalMs = nil
        proximityLostSince = nil
        navigatingPlace = place
        follower = RouteFollower(path: place.path)
        let now = wallClock()
        let confidence = ConfidenceModel.estimate(anchorQuality: place.anchor.map { anchors.quality(of: $0, now: now) }, path: place.path,
                                                  driftEstimate: 0, ageSeconds: now.timeIntervalSince(place.createdAt), truncated: place.path.truncated)
        var phase = NavigationPhase.alongPath
        var intro = "Guiding you to \(place.name). \(confidence.spoken)."
        if place.isPhysical, let id = place.kind.beaconIdentifier, let estimate = proximityEstimate(for: id), estimate.zone <= .close {
            phase = .proximity
            intro += " The beacon is in range."
        } else if let anchor = place.anchor, let fix = lastFix, wallClock().timeIntervalSince(fix.timestamp) < 30,
                  fix.horizontalAccuracy <= approach.config.maxAccuracy,
                  GeoMath.distance(fix, anchor.fix) > approach.config.arriveRadius + fix.horizontalAccuracy {
            phase = .toAnchor
            intro += " First, walk to the starting point, \(GuidanceNarrator.spokenDistance(GeoMath.distance(fix, anchor.fix), metric: settings.useMetric)) away."
        } else {
            if positionInFrame(of: place) == nil {
                // We cannot place ourselves in the path's frame: assume the user is standing at its start.
                if let anchor = place.anchor { anchors.restore(anchor) } else { frameID = place.frameID ?? frameID }
                reckoner.reset()
                recorder.start(at: .origin, time: clock())
                intro += " Start from where this path began."
            }
            if place.mayBeOnAnotherFloor { intro += " This place may be on another floor." }
            if confidence.level == .low { intro += " This is an old or uncertain pin." }
        }
        navigation = NavigationStatus(placeID: place.id, placeName: place.name, phase: phase, cue: nil, confidence: confidence)
        onBandCommand?(.setMode(.path))
        announce(intro, priority: .high)
        updateNavigation()
    }

    public func stopNavigation(quietly: Bool = false) {
        guard navigation != nil else { return }
        navigation = nil
        navigatingPlace = nil
        follower = nil
        haptics.stop()
        onBandCommand?(.stop)
        onBandCommand?(.setMode(.idle))
        if !quietly { announce("Navigation stopped.", priority: .high) }
    }

    public func snoozeAlert() {
        guard let alert = activeAlert else { return }
        detector.snooze(alert.beacon, now: clock())
        activeAlert = nil
        haptics.stop()
        announce("Snoozed for \(settings.snoozeMinutes) minutes.", priority: .normal)
    }

    /// The user confirms they have the item; the record stays so they can still navigate to where it was.
    public func dismissAlert() {
        guard let alert = activeAlert else { return }
        detector.acknowledge(alert.beacon)
        activeAlert = nil
        haptics.stop()
    }

    public func findLeftBehindItem() {
        guard let alert = activeAlert else { return }
        activeAlert = nil
        startNavigation(to: alert.placeID)
    }

    // MARK: - Internals

    private func handle(_ event: BeaconEvent, now: Double) {
        switch event {
        case .leftBehind(let detail):
            guard let beacon = beacons.first(where: { $0.id == detail.beacon }) else { return }
            let path = recorder.snapshot(until: detail.beaconStoppedAt ?? now, appending: detail.estimatedPosition)
            let wall = wallClock()
            let anchor = anchors.current
            let confidence = ConfidenceModel.estimate(anchorQuality: anchor.map { anchors.quality(of: $0, now: wall) }, path: path, driftEstimate: reckoner.driftEstimate, ageSeconds: 0)
            var place = Place(name: beacon.name, kind: .physicalBeacon(beacon.id), origin: .leftBehind, anchor: anchor, path: path,
                              confidence: Confidence(value: confidence.value - (detail.basis == .signalLost ? 0.15 : 0), reasons: confidence.reasons),
                              createdAt: wall, lastHeard: wall, lastRSSI: detector.filter(for: beacon.id)?.value,
                              pressureDeltaKPa: pressureDelta, frameID: anchor == nil ? frameID : nil)
            if let existing = places.firstIndex(where: { $0.kind.beaconIdentifier == beacon.id }) {
                place.id = places[existing].id
                places.remove(at: existing)
            }
            places.insert(place, at: 0)
            persist()
            activeAlert = ActiveAlert(id: UUID(), beacon: beacon.id, placeID: place.id, name: beacon.name, time: wall)
            haptics.play(.leftBehindAlert, parameterMs: nil)
            announce("\(beacon.name) may have been left behind, about \(GuidanceNarrator.spokenDistance(reckoner.position.distance(to: detail.estimatedPosition), metric: settings.useMetric)) back. Double tap to find it, or hold the band button to snooze.", priority: .high)
        case .pickedUp(let id):
            let name = beacons.first { $0.id == id }?.name ?? "Beacon"
            if activeAlert?.beacon == id { activeAlert = nil; haptics.stop() }
            announce("\(name) is moving again.", priority: .normal)
        case .backInRange(let id):
            let name = beacons.first { $0.id == id }?.name ?? "Beacon"
            announce("\(name) is back in range.", priority: .normal)
        case .lowBattery(let id):
            let name = beacons.first { $0.id == id }?.name ?? "Beacon"
            haptics.play(.lowBattery, parameterMs: nil)
            announce("\(name) battery is low.", priority: .normal)
        }
    }

    private func proximityEstimate(for id: BeaconIdentifier) -> ProximityEstimate? {
        guard let filter = detector.filter(for: id) else { return nil }
        return proximity.estimate(from: filter, txPower: detector.txPower(for: id), now: clock())
    }

    /// Where we are in the frame a place's path was recorded in, or nil if we cannot know.
    public func positionInFrame(of place: Place) -> LocalPoint? {
        if let placeAnchor = place.anchor {
            guard let current = anchors.current else { return nil }
            return GeoMath.localOffset(from: placeAnchor.fix, to: current.fix) + reckoner.position
        }
        guard place.frameID == frameID else { return nil }
        return reckoner.position
    }

    private func updateNavigation() {
        guard var status = navigation, let place = navigatingPlace else { return }
        let now = clock()
        var cue: GuidanceCue
        switch status.phase {
        case .toAnchor:
            guard let anchor = place.anchor, let fix = lastFix else { status.phase = .alongPath; navigation = status; return }
            let bearing = reckoner.isMoving(at: now) ? (reckoner.compassBearing ?? fix.course) : (fix.course ?? reckoner.compassBearing)
            cue = approach.cue(from: fix, to: anchor, userBearing: bearing)
            if cue.kind == .arrived {
                // We are standing at the anchor: make it the PDR origin and follow the path from here.
                anchors.restore(Anchor(fix: anchor.fix, quality: anchor.quality, establishedAt: wallClock()))
                reckoner.reset()
                recorder.start(at: .origin, time: now)
                follower = RouteFollower(path: place.path)
                status.phase = .alongPath
            }
        case .alongPath, .lost:
            guard let follower else { return }
            let position = positionInFrame(of: place) ?? reckoner.position
            cue = follower.update(position: position, heading: reckoner.heading)
            status.phase = cue.phase == .lost ? .lost : .alongPath
            if place.isPhysical, let id = place.kind.beaconIdentifier, let estimate = proximityEstimate(for: id), estimate.zone <= .close,
               follower.isAtLastWaypoint || (cue.distanceRemaining ?? .infinity) < 15 || cue.kind == .lost || cue.kind == .arrived {
                status.phase = .proximity
                cue = GuidanceCue(kind: .proximity(estimate), phase: .proximity, distanceToTarget: estimate.distance, distanceRemaining: estimate.distance)
            } else if cue.kind == .arrived {
                status.phase = .arrived
                cue.phase = .arrived
            }
        case .proximity:
            guard let id = place.kind.beaconIdentifier, let estimate = proximityEstimate(for: id) else { status.phase = .alongPath; navigation = status; return }
            if estimate.zone == .lost {
                if proximityLostSince == nil { proximityLostSince = now }
                if now - (proximityLostSince ?? now) > 20, !place.path.isEmpty {
                    proximityLostSince = nil
                    status.phase = .alongPath
                    navigation = status
                    return
                }
            } else {
                proximityLostSince = nil
            }
            if estimate.zone == .here {
                status.phase = .arrived
                cue = GuidanceCue(kind: .arrived, phase: .arrived, distanceToTarget: estimate.distance, distanceRemaining: estimate.distance)
            } else {
                cue = GuidanceCue(kind: .proximity(estimate), phase: .proximity, distanceToTarget: estimate.distance, distanceRemaining: estimate.distance)
            }
        case .arrived:
            cue = GuidanceCue(kind: .arrived, phase: .arrived, distanceToTarget: 0, distanceRemaining: 0)
        }
        status.cue = cue
        navigation = status
        emitHaptics(for: cue, now: now)
        if let phrase = narrator.phrase(for: cue, now: now) {
            announce(phrase, priority: cue.kind == .arrived || cue.kind == .go(.turnAround) ? .high : .normal)
        }
    }

    private func emitHaptics(for cue: GuidanceCue, now: Double) {
        switch cue.kind {
        case .go(let direction):
            let changed = lastHapticKind != cue.kind
            let since = lastHapticAt.map { now - $0 } ?? .infinity
            if changed || since >= 10 {
                lastProximityIntervalMs = nil
                haptics.play(direction.hapticPattern, parameterMs: nil)
                lastHapticAt = now
            }
        case .proximity(let estimate):
            let interval = Int(estimate.pulseInterval * 1000)
            if estimate.zone == .lost {
                if lastHapticKind != cue.kind { haptics.play(.lostSignal, parameterMs: nil); lastHapticAt = now }
                lastProximityIntervalMs = nil
            } else if let last = lastProximityIntervalMs, abs(last - interval) < max(last / 5, 50) {
                break
            } else {
                lastProximityIntervalMs = interval
                haptics.play(.proximityPulse, parameterMs: interval)
                lastHapticAt = now
            }
        case .arrived:
            if lastHapticKind != cue.kind {
                haptics.stop()
                haptics.play(.arrived, parameterMs: nil)
                lastHapticAt = now
                lastProximityIntervalMs = nil
            }
        case .lost:
            if lastHapticKind != cue.kind { haptics.play(.lostSignal, parameterMs: nil); lastHapticAt = now }
        case .needHeading:
            break
        }
        lastHapticKind = cue.kind
    }

    private func refreshDiagnostics() {
        let now = clock()
        let wall = wallClock()
        diagnostics.stepCount = reckoner.stepCount
        diagnostics.distanceSinceAnchor = reckoner.distanceSinceReset
        diagnostics.compassBearing = reckoner.compassBearing
        diagnostics.position = reckoner.position
        diagnostics.anchorQuality = anchors.current.map { anchors.quality(of: $0, now: wall) }
        diagnostics.anchorAgeSeconds = anchors.current.map { wall.timeIntervalSince($0.establishedAt) }
        diagnostics.anchorAccuracy = anchors.current?.fix.horizontalAccuracy
        diagnostics.driftEstimate = reckoner.driftEstimate
        diagnostics.gpsDegraded = anchors.isSignalDegraded
        diagnostics.isMoving = reckoner.isMoving(at: now)
    }

    private func persist() {
        try? store.save(places)
        onPlacesChanged?()
    }

    private func announce(_ text: String, priority: Announcement.Priority) {
        let announcement = Announcement(text, priority: priority)
        announcements.append(announcement)
        if announcements.count > 50 { announcements.removeFirst(announcements.count - 50) }
        onAnnouncement?(announcement)
    }
}

extension DeadReckoner: PhoneMotionSource {}
