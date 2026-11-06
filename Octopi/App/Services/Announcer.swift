import AVFoundation
import Foundation
import OctopiCore
import UIKit

/// Speaks announcements. With VoiceOver running we post accessibility announcements so they interleave
/// correctly with what VoiceOver is reading; otherwise we use speech synthesis (if enabled).
final class Announcer {
    private let synthesizer = AVSpeechSynthesizer()
    var speakWhenVoiceOverOff = true
    private(set) var log: [Announcement] = []

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func announce(_ announcement: Announcement) {
        log.append(announcement)
        if log.count > 100 { log.removeFirst(log.count - 100) }
        if UIAccessibility.isVoiceOverRunning {
            let priority: UIAccessibilityPriority = announcement.priority == .high ? .high : (announcement.priority == .low ? .low : .default)
            let text = NSAttributedString(string: announcement.text, attributes: [.accessibilitySpeechAnnouncementPriority: priority])
            UIAccessibility.post(notification: .announcement, argument: text)
        } else if speakWhenVoiceOverOff {
            if announcement.priority == .high, synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
            let utterance = AVSpeechUtterance(string: announcement.text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.prefersAssistiveTechnologySettings = true
            synthesizer.speak(utterance)
        }
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
