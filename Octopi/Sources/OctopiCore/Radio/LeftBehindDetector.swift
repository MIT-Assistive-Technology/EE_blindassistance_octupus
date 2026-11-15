import Foundation

public struct LeftBehindPolicy: Sendable {
    /// Beacon must be still for this long (s) before it can count as left behind.
    public var stationarySeconds = 10.0
    /// Phone must have walked this far (m) since the beacon stopped moving.
    public var walkAwayMetres = 8.0
    /// Alternative trigger: smoothed RSSI at or below this (dBm) ...
    public var farRSSI = -85.0
    /// ... while receding for at least this long (s) and the phone is walking.
    public var recedingSeconds = 15.0
    /// A suspect beacon must stay suspect this long (s) before we alert. Filters brief separations.
    public var confirmSeconds = 5.0
    /// No advertisement for this long (s) means the beacon is out of range.
    public var lostAfter = 45.0
    /// Default snooze (s) after the user dismisses an alert.
    public var snoozeSeconds = 600.0
    public init() {}
}

/// What the phone has been doing; supplied by the dead reckoner.
public protocol PhoneMotionSource: AnyObject {
    func position(at time: Double) -> LocalPoint
    func distanceWalked(from start: Double, to end: Double) -> Double
    func isMoving(at time: Double) -> Bool
}

/// One advertisement from a beacon, after parsing.
public struct BeaconObservation: Equatable, Sendable {
    public var time: Double
    public var rssi: Double
    public var isMoving: Bool
    public var secondsSinceMotion: Double?
    public var txPowerAt1m: Double?
    public var batteryPercent: Int?
    public var isBatteryLow: Bool

    public init(time: Double, rssi: Double, isMoving: Bool, secondsSinceMotion: Double? = nil, txPowerAt1m: Double? = nil, batteryPercent: Int? = nil, isBatteryLow: Bool = false) {
        self.time = time
        self.rssi = rssi
        self.isMoving = isMoving
        self.secondsSinceMotion = secondsSinceMotion
        self.txPowerAt1m = txPowerAt1m
        self.batteryPercent = batteryPercent
        self.isBatteryLow = isBatteryLow
    }
}

public enum BeaconTrackingState: Equatable, Sendable {
    case withUser
    case suspect(since: Double)
    case leftBehind(at: Double)
    case lost(since: Double)
    /// The user gave the beacon to someone else on purpose; no alerts.
    case handedOff
}

public struct LeftBehindEvent: Equatable, Sendable {
    public enum Basis: String, Sendable {
        case beaconStoppedWhilePhoneWalkedAway
        case signalReceding
        case signalLost
    }
    public var beacon: BeaconIdentifier
    public var time: Double
    /// When the beacon stopped moving, if known.
    public var beaconStoppedAt: Double?
    /// The phone's last confident position while the beacon was still with us.
    public var estimatedPosition: LocalPoint
    public var basis: Basis
}

public enum BeaconEvent: Equatable, Sendable {
    case leftBehind(LeftBehindEvent)
    /// A beacon we had flagged started moving again (someone picked it up).
    case pickedUp(BeaconIdentifier)
    /// A lost beacon is back in range.
    case backInRange(BeaconIdentifier)
    case lowBattery(BeaconIdentifier)
}

/// Per-beacon left-behind state machine.
///
/// Two triggers (either is enough):
///  A. the beacon reports it has been still ≥ `stationarySeconds` **and** the phone has walked
///     ≥ `walkAwayMetres` since the beacon stopped;
///  B. the smoothed RSSI is ≤ `farRSSI` and receding for ≥ `recedingSeconds` while the phone walks.
/// A suspect beacon must stay suspect for `confirmSeconds` before an alert, which filters out
/// walking to the far side of a room. Losing the signal entirely for `lostAfter` also alerts.
public final class LeftBehindDetector {
    public var policy: LeftBehindPolicy

    final class Track {
        var filter: RSSIFilter
        var state = BeaconTrackingState.withUser
        var lastHeard: Double
        var lastMoving: Double?
        var recedingSince: Double?
        var suspectPosition: LocalPoint?
        var suspectBasis: LeftBehindEvent.Basis?
        var snoozedUntil: Double?
        var lowBatteryReported = false
        var txPower: Double?
        init(filter: RSSIFilter, time: Double) { self.filter = filter; lastHeard = time }
    }

    private var tracks: [BeaconIdentifier: Track] = [:]
    private var filterConfig: RSSIFilter.Config

    public init(policy: LeftBehindPolicy = LeftBehindPolicy(), filterConfig: RSSIFilter.Config = RSSIFilter.Config()) {
        self.policy = policy
        self.filterConfig = filterConfig
    }

    public var trackedBeacons: [BeaconIdentifier] { Array(tracks.keys) }

    public func state(of beacon: BeaconIdentifier) -> BeaconTrackingState? { tracks[beacon]?.state }
    public func filter(for beacon: BeaconIdentifier) -> RSSIFilter? { tracks[beacon]?.filter }
    public func txPower(for beacon: BeaconIdentifier) -> Double? { tracks[beacon]?.txPower }
    public func lastHeard(_ beacon: BeaconIdentifier) -> Double? { tracks[beacon]?.lastHeard }

    public func forget(_ beacon: BeaconIdentifier) { tracks[beacon] = nil }

    public func snooze(_ beacon: BeaconIdentifier, now: Double, for seconds: Double? = nil) {
        guard let track = tracks[beacon] else { return }
        track.snoozedUntil = now + (seconds ?? policy.snoozeSeconds)
        track.state = .withUser
        track.recedingSince = nil
    }

    public func isSnoozed(_ beacon: BeaconIdentifier, now: Double) -> Bool {
        guard let until = tracks[beacon]?.snoozedUntil else { return false }
        return now < until
    }

    public func setHandedOff(_ beacon: BeaconIdentifier, _ handedOff: Bool, now: Double) {
        let track = tracks[beacon] ?? Track(filter: RSSIFilter(config: filterConfig), time: now)
        tracks[beacon] = track
        track.state = handedOff ? .handedOff : .withUser
    }

    /// The user confirms they have the beacon again.
    public func acknowledge(_ beacon: BeaconIdentifier) {
        tracks[beacon]?.state = .withUser
        tracks[beacon]?.recedingSince = nil
    }

    /// Feed one observation. Returns events to surface to the user.
    public func observe(_ observation: BeaconObservation, beacon: BeaconIdentifier, phone: PhoneMotionSource) -> [BeaconEvent] {
        let track = tracks[beacon] ?? Track(filter: RSSIFilter(config: filterConfig), time: observation.time)
        tracks[beacon] = track
        var events: [BeaconEvent] = []
        let now = observation.time
        let wasLost: Bool
        if case .lost = track.state { wasLost = true } else { wasLost = false }
        track.lastHeard = now
        track.txPower = observation.txPowerAt1m
        track.filter.add(observation.rssi, at: now)
        if observation.isMoving {
            track.lastMoving = now
        } else if let age = observation.secondsSinceMotion {
            let stopped = now - age
            track.lastMoving = max(track.lastMoving ?? stopped, stopped)
        }
        if observation.isBatteryLow, !track.lowBatteryReported {
            track.lowBatteryReported = true
            events.append(.lowBattery(beacon))
        }
        if wasLost { events.append(.backInRange(beacon)) }

        switch track.state {
        case .handedOff:
            return events
        case .leftBehind, .lost:
            if observation.isMoving {
                track.state = .withUser
                track.recedingSince = nil
                events.append(.pickedUp(beacon))
            }
            return events
        case .withUser, .suspect:
            break
        }
        if let until = track.snoozedUntil, now < until { return events }

        // Trigger A: beacon still, phone walked away.
        var basis: LeftBehindEvent.Basis?
        var position: LocalPoint?
        if !observation.isMoving, let lastMoving = track.lastMoving, now - lastMoving >= policy.stationarySeconds,
           phone.distanceWalked(from: lastMoving, to: now) >= policy.walkAwayMetres {
            basis = .beaconStoppedWhilePhoneWalkedAway
            position = phone.position(at: lastMoving)
        }
        // Trigger B: signal weak and receding while we walk.
        if basis == nil, let value = track.filter.value, value <= policy.farRSSI, track.filter.slope.map({ $0 < 0 }) ?? false, phone.isMoving(at: now) {
            if track.recedingSince == nil { track.recedingSince = now; track.suspectPosition = phone.position(at: now) }
            if now - (track.recedingSince ?? now) >= policy.recedingSeconds {
                basis = .signalReceding
                position = track.suspectPosition ?? phone.position(at: track.recedingSince ?? now)
            }
        } else if basis == nil {
            track.recedingSince = nil
        }

        guard let basis, let position else {
            if observation.isMoving { track.state = .withUser }
            return events
        }
        switch track.state {
        case .withUser:
            track.state = .suspect(since: now)
            track.suspectBasis = basis
            track.suspectPosition = position
        case .suspect(let since):
            if now - since >= policy.confirmSeconds {
                track.state = .leftBehind(at: now)
                let event = LeftBehindEvent(beacon: beacon, time: now, beaconStoppedAt: track.lastMoving,
                                            estimatedPosition: track.suspectPosition ?? position, basis: track.suspectBasis ?? basis)
                events.append(.leftBehind(event))
            }
        default:
            break
        }
        return events
    }

    /// Call periodically (about once a second) to detect beacons that went silent.
    public func tick(now: Double, phone: PhoneMotionSource) -> [BeaconEvent] {
        var events: [BeaconEvent] = []
        for (beacon, track) in tracks {
            guard now - track.lastHeard >= policy.lostAfter else { continue }
            switch track.state {
            case .withUser, .suspect:
                if let until = track.snoozedUntil, now < until {
                    track.state = .lost(since: now)
                    continue
                }
                track.state = .lost(since: now)
                let event = LeftBehindEvent(beacon: beacon, time: now, beaconStoppedAt: track.lastMoving,
                                            estimatedPosition: phone.position(at: track.lastHeard), basis: .signalLost)
                events.append(.leftBehind(event))
            default:
                continue
            }
        }
        return events
    }
}
