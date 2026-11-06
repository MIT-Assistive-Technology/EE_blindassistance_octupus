import Foundation
import OctopiCore

/// Stands in for the band, the beacons, walking and GPS so the whole flow can be exercised in the
/// iOS simulator and in UI tests. Enabled with the `-simulateHardware` launch argument or from Settings.
final class HardwareSimulator {
    final class Band: HapticOutput {
        var isAvailable = true
        private(set) var log: [String] = []
        func play(_ pattern: HapticPattern, parameterMs: Int?) {
            log.append(pattern.spokenName + (parameterMs.map { " (\($0) ms)" } ?? ""))
            if log.count > 30 { log.removeFirst() }
        }
        func stop() { log.append("stop") }
    }

    struct Beacon: Identifiable {
        var id: UInt32
        var name: String
        /// Where the beacon is in the PDR frame when it is not carried.
        var position: LocalPoint?
        var carried = true
        var stoppedAt: Double?
        var battery = 85
    }

    let band = Band()
    private(set) var beacons: [Beacon] = [Beacon(id: 0x1001, name: "Keys"), Beacon(id: 0x1002, name: "Bag")]
    private(set) var isWalking = false
    private(set) var heading = Double.pi / 2
    private var timer: Timer?
    private var time = ProcessInfo.processInfo.systemUptime
    private var sequence: UInt8 = 0
    private let home = GeoFix(latitude: 42.3601, longitude: -71.0942, horizontalAccuracy: 5, timestamp: Date())

    var onMotion: ((MotionSample) -> Void)?
    var onBeacon: ((BeaconAdvertisement, Double) -> Void)?
    var onFix: ((GeoFix) -> Void)?
    var onBandEvent: ((WearableProtocol.Event) -> Void)?
    var positionProvider: (() -> LocalPoint)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggleWalking() { isWalking.toggle() }
    func turn(byDegrees degrees: Double) { heading += degrees * .pi / 180 }

    /// Feed a good fix at the simulated home position offset by the current PDR position.
    func sendGoodFix() {
        var fix = GeoMath.offset(home, by: positionProvider?() ?? .origin)
        fix.timestamp = Date()
        fix.horizontalAccuracy = 5
        onFix?(fix)
    }

    func dropBeacon(_ id: UInt32) {
        guard let index = beacons.firstIndex(where: { $0.id == id }) else { return }
        beacons[index].carried = false
        beacons[index].position = positionProvider?() ?? .origin
        beacons[index].stoppedAt = ProcessInfo.processInfo.systemUptime
    }

    func pickUpBeacon(_ id: UInt32) {
        guard let index = beacons.firstIndex(where: { $0.id == id }) else { return }
        beacons[index].carried = true
        beacons[index].position = nil
        beacons[index].stoppedAt = nil
    }

    func pressBandButton(_ action: WearableProtocol.ButtonAction) {
        onBandEvent?(.button(.record, action))
    }

    private var tickCount = 0
    private func step() {
        let now = ProcessInfo.processInfo.systemUptime
        // 100 Hz motion in 0.1 s batches.
        while time < now {
            onMotion?(sample(at: time))
            time += 0.01
        }
        tickCount += 1
        guard tickCount % 10 == 0 else { return }
        let here = positionProvider?() ?? .origin
        for beacon in beacons {
            let distance = beacon.carried ? 0.5 : max(0.3, here.distance(to: beacon.position ?? .origin))
            let rssi = -59 - 10 * 2.4 * log10(distance) + Double.random(in: -2...2)
            guard rssi > -100 else { continue }
            sequence &+= 1
            let age = beacon.stoppedAt.map { now - $0 }
            let adv = BeaconAdvertisement(serial: beacon.id, isMoving: beacon.carried && isWalking, isBatteryLow: beacon.battery < 15,
                                          batteryPercent: beacon.battery, secondsSinceMotion: beacon.carried ? 0 : age, txPowerAt1m: -59, sequence: sequence)
            onBeacon?(adv, rssi)
        }
    }

    private func sample(at t: Double) -> MotionSample {
        let phi = heading - .pi
        let q = Quaternion(x: 0, y: 0, z: sin(phi / 2), w: cos(phi / 2))
        let phase = 2 * .pi * 1.8 * t
        let bob = isWalking ? 2 + 2 * sin(phase) : 0.02
        return MotionSample(elapsed: t, attitude: q, userAcceleration: Vector3(x: 0, y: 0, z: bob), rotationRate: .zero)
    }
}
