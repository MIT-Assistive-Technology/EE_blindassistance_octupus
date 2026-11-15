import Foundation
import Testing
@testable import OctopiCore

@Suite struct RSSIFilterTests {
    @Test func convergesAndClipsOutliers() {
        var filter = RSSIFilter()
        for i in 0..<20 { filter.add(-70, at: Double(i)) }
        #expect(approx(filter.value ?? 0, -70, tolerance: 0.5))
        filter.add(-20, at: 21) // a single wild reading
        #expect((filter.value ?? 0) < -60)
        #expect(filter.lastUpdate == 21)
        filter.reset()
        #expect(filter.value == nil)
    }

    @Test func slopeSignFollowsTrend() {
        var filter = RSSIFilter()
        for i in 0..<10 { filter.add(-90 + Double(i) * 2, at: Double(i)) }
        #expect((filter.slope ?? 0) > 0.5)
        var receding = RSSIFilter()
        for i in 0..<10 { receding.add(-60 - Double(i) * 2, at: Double(i)) }
        #expect((receding.slope ?? 0) < -0.5)
        var short = RSSIFilter(); short.add(-60, at: 0)
        #expect(short.slope == nil)
    }

    @Test func distanceModel() {
        #expect(approx(RSSIFilter.distance(rssi: -59, txPower: -59, exponent: 2.4), 1, tolerance: 1e-9))
        #expect(RSSIFilter.distance(rssi: -83, txPower: -59, exponent: 2.4) > 9)
        var filter = RSSIFilter()
        #expect(filter.distance() == nil)
        filter.add(-59, at: 0)
        #expect(approx(filter.distance(txPower: -59) ?? 0, 1, tolerance: 1e-9))
    }
}

@Suite struct ProximityEstimatorTests {
    @Test func zonesAndPulseRate() {
        let estimator = ProximityEstimator()
        var filter = RSSIFilter()
        for i in 0..<10 { filter.add(-59, at: Double(i)) }
        let here = estimator.estimate(from: filter, txPower: -59, now: 10)
        #expect(here.zone == .here)
        #expect(here.pulseInterval == estimator.config.fastestPulse)
        var far = RSSIFilter()
        for i in 0..<10 { far.add(-90, at: Double(i)) }
        let farEstimate = estimator.estimate(from: far, txPower: -59, now: 10)
        #expect(farEstimate.zone == .far)
        #expect(farEstimate.pulseInterval == estimator.config.slowestPulse)
        #expect(estimator.pulseInterval(for: 2) < estimator.pulseInterval(for: 5))
    }

    @Test func lostAfterSilence() {
        let estimator = ProximityEstimator()
        var filter = RSSIFilter()
        filter.add(-65, at: 0)
        #expect(estimator.estimate(from: filter, txPower: nil, now: 5).zone == .near)
        #expect(estimator.estimate(from: filter, txPower: nil, now: 30).zone == .lost)
        #expect(ProximityZone.here < ProximityZone.lost)
    }

    @Test func trendFromSlope() {
        let estimator = ProximityEstimator()
        var filter = RSSIFilter()
        for i in 0..<10 { filter.add(-80 + Double(i) * 2, at: Double(i)) }
        #expect(estimator.estimate(from: filter, txPower: nil, now: 10).trend == .approaching)
    }
}

@Suite struct BeaconAdvertisementTests {
    @Test func roundTrip() {
        let adv = BeaconAdvertisement(serial: 0xDEADBEEF, isMoving: true, isBatteryLow: true, isButtonPressed: false, isCharging: true, batteryPercent: 42, secondsSinceMotion: 17, txPowerAt1m: -62, sequence: 9)
        let parsed = BeaconAdvertisement(manufacturerData: adv.manufacturerData)
        #expect(parsed == adv)
        #expect(adv.identifier.rawValue == "OCT-DEADBEEF")
        #expect(adv.manufacturerData.count == BeaconAdvertisement.length)
    }

    @Test func unknownsEncodeAsSentinels() {
        let adv = BeaconAdvertisement(serial: 1, isMoving: false)
        let bytes = [UInt8](adv.manufacturerData)
        #expect(bytes[9] == 0xFF)
        #expect(bytes[10] == 0xFF && bytes[11] == 0xFF)
        let parsed = BeaconAdvertisement(manufacturerData: adv.manufacturerData)
        #expect(parsed?.batteryPercent == nil && parsed?.secondsSinceMotion == nil)
    }

    @Test func rejectsForeignData() {
        #expect(BeaconAdvertisement(manufacturerData: Data([0x4C, 0x00, 0x02, 0x15])) == nil)
        var bytes = [UInt8](BeaconAdvertisement(serial: 1, isMoving: false).manufacturerData)
        bytes[2] = 0x00
        #expect(BeaconAdvertisement(manufacturerData: Data(bytes)) == nil)
        #expect(BeaconAdvertisement(manufacturerData: Data()) == nil)
    }
}

@Suite struct LeftBehindDetectorTests {
    let keys = BeaconIdentifier("OCT-00000001")

    func observation(_ t: Double, rssi: Double = -65, moving: Bool, age: Double? = nil, lowBattery: Bool = false) -> BeaconObservation {
        BeaconObservation(time: t, rssi: rssi, isMoving: moving, secondsSinceMotion: age, txPowerAt1m: -59, isBatteryLow: lowBattery)
    }

    @Test func beaconStoppedAndPhoneWalkedAwayTriggersAlert() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.positions = [(0, .origin), (10, LocalPoint(east: 5, north: 0)), (30, LocalPoint(east: 20, north: 0))]
        phone.walked = 0
        var events: [BeaconEvent] = []
        for t in stride(from: 0.0, through: 10, by: 1) { events += detector.observe(observation(t, moving: true), beacon: keys, phone: phone) }
        #expect(events.isEmpty)
        #expect(detector.state(of: keys) == .withUser)
        // Beacon stops at t=10; phone keeps walking.
        for t in stride(from: 11.0, through: 40, by: 1) {
            phone.walked = Double(t - 10) * 1.0
            events += detector.observe(observation(t, rssi: -65 - (t - 10), moving: false, age: t - 10), beacon: keys, phone: phone)
        }
        guard case .leftBehind(let detail)? = events.first else { Issue.record("expected a left-behind event, got \(events)"); return }
        #expect(detail.basis == .beaconStoppedWhilePhoneWalkedAway)
        #expect(detail.beaconStoppedAt == 10)
        #expect(detail.estimatedPosition == LocalPoint(east: 5, north: 0), "position where the phone was when the beacon stopped")
        #expect(events.count == 1, "alert fires once")
        if case .leftBehind = detector.state(of: keys) {} else { Issue.record("state should be leftBehind") }
    }

    @Test func noAlertWhenPhoneStaysPut() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.walked = 0
        phone.moving = false
        var events: [BeaconEvent] = []
        for t in stride(from: 0.0, through: 60, by: 1) { events += detector.observe(observation(t, moving: false, age: t), beacon: keys, phone: phone) }
        #expect(events.isEmpty)
    }

    @Test func recedingSignalTriggersAlert() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.walked = 0
        phone.moving = true
        var events: [BeaconEvent] = []
        for t in stride(from: 0.0, through: 60, by: 1) {
            let rssi = -70 - Double(t) * 0.8
            events += detector.observe(observation(t, rssi: rssi, moving: true), beacon: keys, phone: phone)
        }
        guard case .leftBehind(let detail)? = events.first else { Issue.record("expected receding alert, got \(events)"); return }
        #expect(detail.basis == .signalReceding)
    }

    @Test func snoozeSuppressesAndExpires() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.walked = 20
        _ = detector.observe(observation(0, moving: true), beacon: keys, phone: phone)
        detector.snooze(keys, now: 1, for: 100)
        #expect(detector.isSnoozed(keys, now: 50))
        var events: [BeaconEvent] = []
        for t in stride(from: 1.0, through: 90, by: 1) { events += detector.observe(observation(t, moving: false, age: t), beacon: keys, phone: phone) }
        #expect(events.isEmpty)
        for t in stride(from: 101.0, through: 130, by: 1) { events += detector.observe(observation(t, moving: false, age: t), beacon: keys, phone: phone) }
        #expect(events.count == 1)
    }

    @Test func handedOffNeverAlertsAndPickedUpClears() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.walked = 50
        detector.setHandedOff(keys, true, now: 0)
        var events: [BeaconEvent] = []
        for t in stride(from: 0.0, through: 60, by: 1) { events += detector.observe(observation(t, moving: false, age: t), beacon: keys, phone: phone) }
        #expect(events.isEmpty)
        detector.setHandedOff(keys, false, now: 61)
        for t in stride(from: 61.0, through: 90, by: 1) { events += detector.observe(observation(t, moving: false, age: t), beacon: keys, phone: phone) }
        #expect(events.count == 1)
        events = detector.observe(observation(91, moving: true), beacon: keys, phone: phone)
        #expect(events == [.pickedUp(keys)])
        #expect(detector.state(of: keys) == .withUser)
        detector.acknowledge(keys)
        detector.forget(keys)
        #expect(detector.state(of: keys) == nil)
    }

    @Test func silenceBecomesLostThenBackInRange() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        phone.positions = [(0, .origin), (5, LocalPoint(east: 3, north: 3))]
        _ = detector.observe(observation(5, moving: true), beacon: keys, phone: phone)
        #expect(detector.tick(now: 20, phone: phone).isEmpty)
        let events = detector.tick(now: 60, phone: phone)
        guard case .leftBehind(let detail)? = events.first else { Issue.record("expected lost alert"); return }
        #expect(detail.basis == .signalLost)
        #expect(detail.estimatedPosition == LocalPoint(east: 3, north: 3))
        #expect(detector.tick(now: 61, phone: phone).isEmpty, "no repeat")
        let back = detector.observe(observation(70, moving: false), beacon: keys, phone: phone)
        #expect(back.contains(.backInRange(keys)))
    }

    @Test func lowBatteryReportedOnce() {
        let detector = LeftBehindDetector()
        let phone = FakePhone()
        let first = detector.observe(observation(0, moving: true, lowBattery: true), beacon: keys, phone: phone)
        let second = detector.observe(observation(1, moving: true, lowBattery: true), beacon: keys, phone: phone)
        #expect(first == [.lowBattery(keys)])
        #expect(second.isEmpty)
        #expect(detector.trackedBeacons == [keys])
        #expect(detector.txPower(for: keys) == -59)
        #expect(detector.lastHeard(keys) == 1)
    }
}
