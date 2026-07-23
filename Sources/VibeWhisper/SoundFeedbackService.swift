import AppKit
import Foundation

enum SoundFeedbackEvent: String, CaseIterable, Sendable {
    case recordingStarted
    case recordingStopped

    var resourceName: String {
        switch self {
        case .recordingStarted:
            return "recording-start"
        case .recordingStopped:
            return "recording-stop"
        }
    }
}

@MainActor
protocol SoundFeedbackPlaying: AnyObject {
    func play(_ event: SoundFeedbackEvent, enabled: Bool)
}

@MainActor
final class SoundFeedbackService: SoundFeedbackPlaying {
    private var sounds: [SoundFeedbackEvent: NSSound] = [:]

    init(bundle: Bundle = .main) {
        for event in SoundFeedbackEvent.allCases {
            guard let url = bundle.url(
                forResource: event.resourceName,
                withExtension: "wav",
                subdirectory: "Sounds"
            ) ?? bundle.url(forResource: event.resourceName, withExtension: "wav") else {
                continue
            }

            sounds[event] = NSSound(contentsOf: url, byReference: true)
        }
    }

    func play(_ event: SoundFeedbackEvent, enabled: Bool) {
        guard enabled, let sound = sounds[event] else {
            return
        }

        sound.stop()
        sound.play()
    }
}
