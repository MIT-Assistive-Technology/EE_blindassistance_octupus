import Foundation

public enum HapticMotor: String, Codable, Sendable, CaseIterable {
    case left, center, right
}

public enum MotorLayout: Sendable {
    /// The wristband: three DRV2605L-driven motors.
    case threeMotor
    /// The phone's Taptic Engine, or a band with one motor.
    case singleMotor
}

public struct HapticPulse: Equatable, Sendable {
    public var motors: Set<HapticMotor>
    /// 0...1
    public var intensity: Double
    public var durationMs: Int
    /// Pause after this pulse.
    public var gapMs: Int

    public init(_ motors: Set<HapticMotor>, intensity: Double, durationMs: Int, gapMs: Int) {
        self.motors = motors
        self.intensity = intensity
        self.durationMs = durationMs
        self.gapMs = gapMs
    }
}

public struct HapticScript: Equatable, Sendable {
    public var pulses: [HapticPulse]
    public var repeatCount: Int

    public init(pulses: [HapticPulse], repeatCount: Int = 1) {
        self.pulses = pulses
        self.repeatCount = repeatCount
    }

    public var totalDurationMs: Int {
        pulses.reduce(0) { $0 + $1.durationMs + $1.gapMs } * max(repeatCount, 1)
    }
}

/// Maps each pattern to motor scripts. Directional information uses motor side on the band
/// and pulse *count* on a single motor, so the vocabulary survives the fallback.
public enum HapticVocabulary {
    public static func script(for pattern: HapticPattern, layout: MotorLayout, parameterMs: Int? = nil) -> HapticScript {
        let all: Set<HapticMotor> = [.left, .center, .right]
        let left: Set<HapticMotor> = layout == .threeMotor ? [.left] : [.center]
        let right: Set<HapticMotor> = layout == .threeMotor ? [.right] : [.center]
        let center: Set<HapticMotor> = [.center]
        let both: Set<HapticMotor> = layout == .threeMotor ? [.left, .right] : [.center]
        let short = 90, gap = 110, long = 450
        switch pattern {
        case .pinConfirmed:
            return HapticScript(pulses: [HapticPulse(center, intensity: 0.8, durationMs: short, gapMs: gap), HapticPulse(center, intensity: 0.8, durationMs: short, gapMs: 0)])
        case .ahead:
            return HapticScript(pulses: [HapticPulse(center, intensity: 0.7, durationMs: long, gapMs: 0)])
        case .left:
            return HapticScript(pulses: Array(repeating: HapticPulse(left, intensity: 0.9, durationMs: short, gapMs: gap), count: 2))
        case .right:
            return HapticScript(pulses: Array(repeating: HapticPulse(right, intensity: 0.9, durationMs: short, gapMs: gap), count: 3))
        case .turnAround:
            return HapticScript(pulses: [
                HapticPulse(left, intensity: 1, durationMs: long, gapMs: gap),
                HapticPulse(right, intensity: 1, durationMs: short, gapMs: gap),
                HapticPulse(left, intensity: 1, durationMs: long, gapMs: 0)
            ])
        case .arrived:
            let sweep: [HapticPulse] = layout == .threeMotor
                ? [HapticPulse([.left], intensity: 0.6, durationMs: short, gapMs: 40), HapticPulse([.center], intensity: 0.8, durationMs: short, gapMs: 40), HapticPulse([.right], intensity: 1, durationMs: short, gapMs: 120)]
                : [HapticPulse(center, intensity: 0.4, durationMs: short, gapMs: 40), HapticPulse(center, intensity: 0.7, durationMs: short, gapMs: 40), HapticPulse(center, intensity: 1, durationMs: short, gapMs: 120)]
            return HapticScript(pulses: sweep + [HapticPulse(all.intersection(layout == .threeMotor ? all : center), intensity: 1, durationMs: 700, gapMs: 0)])
        case .leftBehindAlert:
            return HapticScript(pulses: Array(repeating: HapticPulse(layout == .threeMotor ? all : center, intensity: 1, durationMs: 400, gapMs: 300), count: 4), repeatCount: 3)
        case .proximityPulse:
            let interval = max(parameterMs ?? 1000, 150)
            return HapticScript(pulses: [HapticPulse(center, intensity: 0.8, durationMs: 60, gapMs: interval - 60)])
        case .lostSignal:
            return HapticScript(pulses: Array(repeating: HapticPulse(both, intensity: 0.5, durationMs: long, gapMs: 400), count: 2))
        case .lowBattery:
            return HapticScript(pulses: Array(repeating: HapticPulse(center, intensity: 0.35, durationMs: 60, gapMs: 140), count: 3))
        case .bandConnected:
            return HapticScript(pulses: [HapticPulse(center, intensity: 0.6, durationMs: short, gapMs: 0)])
        case .error:
            return HapticScript(pulses: [HapticPulse(both, intensity: 0.9, durationMs: short, gapMs: 80), HapticPulse(both, intensity: 0.9, durationMs: short, gapMs: 0)])
        }
    }
}

/// Something that can play a pattern: the band over BLE, or the phone's own engine.
public protocol HapticOutput: AnyObject {
    var isAvailable: Bool { get }
    func play(_ pattern: HapticPattern, parameterMs: Int?)
    func stop()
}

/// Sends patterns to the band when it is connected, otherwise (or additionally) to the phone.
public final class HapticRouter: HapticOutput {
    public var band: HapticOutput?
    public var phone: HapticOutput?
    /// Also play on the phone while the band is connected.
    public var mirrorToPhone = false
    public private(set) var lastPlayed: (pattern: HapticPattern, parameterMs: Int?)?

    public init(band: HapticOutput? = nil, phone: HapticOutput? = nil) {
        self.band = band
        self.phone = phone
    }

    public var isAvailable: Bool { (band?.isAvailable ?? false) || (phone?.isAvailable ?? false) }

    public func play(_ pattern: HapticPattern, parameterMs: Int? = nil) {
        lastPlayed = (pattern, parameterMs)
        if let band, band.isAvailable {
            band.play(pattern, parameterMs: parameterMs)
            if mirrorToPhone { phone?.play(pattern, parameterMs: parameterMs) }
        } else {
            phone?.play(pattern, parameterMs: parameterMs)
        }
    }

    public func stop() {
        band?.stop()
        phone?.stop()
    }
}
