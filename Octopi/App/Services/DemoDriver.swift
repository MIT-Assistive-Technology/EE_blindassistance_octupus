#if DEBUG
import Foundation
import OctopiCore

/// Drives the hardware simulator like a cooperative walker for demo recordings (launch argument `-demoWalk`):
/// starts walking with a good GPS fix, turns the way guidance says, heads for a beacon when guided to one,
/// and "leaves" a beacon behind a few seconds after it is paired.
final class DemoDriver {
    private unowned let model: AppModel
    private var lastTurn = 0.0

    init(model: AppModel) { self.model = model }

    func start() {
        model.simulator.sendGoodFix()
        if !model.simulator.isWalking { model.simulator.toggleWalking() }
        // `-demoScenario=navigate`: walk, drop a pin, walk on, then start guidance back to it.
        // `-demoScenario=alert`: pair the Keys beacon and leave it behind so the alert appears.
        guard let scenario = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-demoScenario=") })?.dropFirst("-demoScenario=".count) else { return }
        switch scenario {
        case "navigate":
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.model.dropPin(name: "My seat") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
                guard let self, let place = self.model.places.first else { return }
                self.model.navigate(to: place)
            }
        case "alert":
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let keys = self.model.nearbyUnpairedBeacons.first(where: { $0.advertisement.serial == 0x1001 }) else { return }
                self.model.pair(keys, name: "Keys")
            }
        default: break
        }
    }

    func didPair(serial: UInt32) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.model.simulator.dropBeacon(serial)
        }
    }

    func tick(now: Double) {
        let sim = model.simulator
        guard let navigation = model.session.navigation else {
            if !sim.isWalking { sim.toggleWalking() }
            return
        }
        if navigation.phase == .arrived {
            if sim.isWalking { sim.toggleWalking() }
            return
        }
        // Guided to a physical beacon: walk straight at it and stop when within arm's reach.
        if let place = model.session.places.first(where: { $0.id == navigation.placeID }), let beaconID = place.kind.beaconIdentifier,
           let beacon = sim.beacons.first(where: { BeaconAdvertisement(serial: $0.id, isMoving: true).identifier == beaconID }), let target = beacon.position {
            let here = model.session.reckoner.position
            let distance = here.distance(to: target)
            if distance < 0.8 { if sim.isWalking { sim.toggleWalking() } }
            else { sim.setHeading(here.heading(to: target)); if !sim.isWalking { sim.toggleWalking() } }
            return
        }
        guard let cue = navigation.cue, case .go(let direction) = cue.kind, now - lastTurn > 2 else { return }
        switch direction {
        case .ahead: return
        case .slightLeft: sim.turn(byDegrees: 30)
        case .left, .sharpLeft: sim.turn(byDegrees: 90)
        case .slightRight: sim.turn(byDegrees: -30)
        case .right, .sharpRight: sim.turn(byDegrees: -90)
        case .turnAround: sim.turn(byDegrees: 180)
        }
        lastTurn = now
    }
}
#endif
