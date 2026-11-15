import Foundation
import Testing
@testable import OctopiCore

@Suite struct WearableProtocolTests {
    @Test func commandEncoding() {
        let play = WearableProtocol.Command.play(pattern: .left, intensity: 120, repeatCount: 2, parameterMs: 0x0102)
        #expect([UInt8](play.encoded) == [0x01, 0x03, 100, 2, 0x02, 0x01])
        #expect([UInt8](WearableProtocol.Command.stop.encoded) == [0x02])
        #expect([UInt8](WearableProtocol.Command.setMode(.simple).encoded) == [0x03, 2])
        #expect([UInt8](WearableProtocol.Command.setSimpleTarget(serial: 0xAABBCCDD).encoded) == [0x04, 0xDD, 0xCC, 0xBB, 0xAA])
        #expect([UInt8](WearableProtocol.Command.ping.encoded) == [0x05])
    }

    @Test func eventRoundTrip() {
        let events: [WearableProtocol.Event] = [
            .button(.record, .single), .button(.record, .double), .button(.power, .long),
            .battery(percent: 77, charging: true), .ack(opcode: 1, ok: true), .ack(opcode: 2, ok: false),
            .modeChanged(.path), .simpleLock(serial: 0x01020304, rssi: -70)
        ]
        for event in events { #expect(WearableProtocol.Event(data: event.encoded) == event) }
        #expect(WearableProtocol.Event(data: Data()) == nil)
        #expect(WearableProtocol.Event(data: Data([0x10, 9, 1])) == nil)
        #expect(WearableProtocol.Event(data: Data([0x99])) == nil)
        #expect(WearableProtocol.Event(data: Data([0x14, 1, 2])) == nil)
    }

    @Test func statusParsing() {
        let status = WearableProtocol.Status(data: Data([55, 1, 2, 1, 4]))
        #expect(status?.batteryPercent == 55 && status?.charging == true && status?.mode == .simple && status?.firmware == "1.4")
        #expect(WearableProtocol.Status(data: Data([1, 2])) == nil)
    }
}

@Suite struct HapticVocabularyTests {
    @Test func everyPatternHasAScriptOnBothLayouts() {
        for pattern in HapticPattern.allCases {
            for layout in [MotorLayout.threeMotor, .singleMotor] {
                let script = HapticVocabulary.script(for: pattern, layout: layout, parameterMs: 500)
                #expect(!script.pulses.isEmpty, "\(pattern) on \(layout)")
                #expect(script.totalDurationMs > 0)
                #expect(script.pulses.allSatisfy { !$0.motors.isEmpty && $0.intensity > 0 && $0.intensity <= 1 })
            }
            #expect(!pattern.spokenName.isEmpty && !pattern.feelDescription.isEmpty)
        }
    }

    @Test func wireIDsAreUniqueAndReversible() {
        let ids = HapticPattern.allCases.map(\.wireID)
        #expect(Set(ids).count == ids.count)
        for pattern in HapticPattern.allCases { #expect(HapticPattern(wireID: pattern.wireID) == pattern) }
        #expect(HapticPattern(wireID: 0xFF) == nil)
    }

    @Test func directionUsesSideOnBandAndCountOnSingleMotor() {
        let left = HapticVocabulary.script(for: .left, layout: .threeMotor)
        let right = HapticVocabulary.script(for: .right, layout: .threeMotor)
        #expect(left.pulses.allSatisfy { $0.motors == [.left] })
        #expect(right.pulses.allSatisfy { $0.motors == [.right] })
        let singleLeft = HapticVocabulary.script(for: .left, layout: .singleMotor)
        let singleRight = HapticVocabulary.script(for: .right, layout: .singleMotor)
        #expect(singleLeft.pulses.count != singleRight.pulses.count)
        #expect(singleLeft.pulses.allSatisfy { $0.motors == [.center] })
    }

    @Test func proximityPulseUsesInterval() {
        let slow = HapticVocabulary.script(for: .proximityPulse, layout: .threeMotor, parameterMs: 1000)
        let fast = HapticVocabulary.script(for: .proximityPulse, layout: .threeMotor, parameterMs: 300)
        #expect(slow.totalDurationMs == 1000 && fast.totalDurationMs == 300)
        #expect(HapticVocabulary.script(for: .proximityPulse, layout: .threeMotor, parameterMs: 10).totalDurationMs == 150)
    }

    @Test func routerPrefersBandAndMirrors() {
        let band = FakeHaptics(), phone = FakeHaptics()
        let router = HapticRouter(band: band, phone: phone)
        router.play(.ahead)
        #expect(band.patterns == [.ahead] && phone.patterns.isEmpty)
        router.mirrorToPhone = true
        router.play(.left)
        #expect(phone.patterns == [.left])
        band.isAvailable = false
        router.play(.right, parameterMs: 5)
        #expect(band.patterns == [.ahead, .left] && phone.patterns == [.left, .right])
        #expect(router.lastPlayed?.pattern == .right && router.lastPlayed?.parameterMs == 5)
        router.stop()
        #expect(band.stops == 1 && phone.stops == 1)
        #expect(router.isAvailable)
        phone.isAvailable = false
        #expect(!router.isAvailable)
    }
}
