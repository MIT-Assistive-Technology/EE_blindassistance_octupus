import CoreHaptics
import Foundation
import OctopiCore
import UIKit

/// Plays the single-motor version of each pattern on the phone's Taptic Engine.
final class PhoneHaptics: HapticOutput {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private(set) var lastPattern: HapticPattern?

    init() {
        guard supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    var isAvailable: Bool { supportsHaptics && engine != nil }

    func play(_ pattern: HapticPattern, parameterMs: Int?) {
        lastPattern = pattern
        guard let engine else { return }
        let script = HapticVocabulary.script(for: pattern, layout: .singleMotor, parameterMs: parameterMs)
        try? player?.stop(atTime: CHHapticTimeImmediate)
        var events: [CHHapticEvent] = []
        var time = 0.0
        for pulse in script.pulses {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(pulse.intensity))
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.durationMs < 150 ? 0.8 : 0.3)
            if pulse.durationMs < 150 {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: time))
            } else {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: time, duration: Double(pulse.durationMs) / 1000))
            }
            time += Double(pulse.durationMs + pulse.gapMs) / 1000
        }
        guard let hapticPattern = try? CHHapticPattern(events: events, parameters: []),
              let newPlayer = try? engine.makeAdvancedPlayer(with: hapticPattern) else { return }
        newPlayer.loopEnabled = pattern == .proximityPulse || pattern == .leftBehindAlert
        if pattern == .leftBehindAlert { newPlayer.loopEnd = time * Double(script.repeatCount) }
        player = newPlayer
        try? engine.start()
        try? newPlayer.start(atTime: CHHapticTimeImmediate)
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }
}
