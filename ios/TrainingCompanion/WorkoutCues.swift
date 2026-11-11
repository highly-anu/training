import AVFoundation
import Foundation

/// What the workout engine (WorkoutSessionState) asks of the device it runs
/// on: a haptic, the lead-in's count. The watch taps the wrist
/// (WatchCueOutput); the phone, not on the wrist, sounds as well
/// (PhoneCueOutput). Compiled into both apps, so the engine names no
/// platform API and the tests run it silent.
enum CueHaptic: Equatable {
    case start, stop, click, notification, success, directionUp, turnLeft, turnRight
}

@MainActor
protocol WorkoutCueOutput: AnyObject {
    func haptic(_ cue: CueHaptic)
    /// A lead-in count (3, 2, 1) or its go, with the vocabulary's word
    /// spoken when Voice is on.
    func leadIn(_ cue: WatchCues.LeadIn, secondsLeft: Int)
}

/// No sound, no haptics: the tests', a forecast's and a catch-up's.
@MainActor
final class SilentCues: WorkoutCueOutput {
    func haptic(_ cue: CueHaptic) {}
    func leadIn(_ cue: WatchCues.LeadIn, secondsLeft: Int) {}
}

/// The cue settings, the Garmin's (Cues.mc) with what a phone and an Apple
/// Watch can do: speak. Each device keeps its own (UserDefaults), set on its
/// own Settings page.
enum WatchCueSettings {
    static let voiceKey = "cueVoice"
    static let leadInKey = "leadIn"
    static let countdownStartKey = "countdownStart"

    /// Say the lead-in ("Work in 3", "2", "1", "Go") as well as tapping it.
    static var voice: Bool { flag(voiceKey, default: false) }
    /// "Work in 3, 2, 1, go" before work that starts on a clock: a rest's end.
    static var leadIn: Bool { flag(leadInKey, default: true) }
    /// The same count after Start, before a step's clock starts.
    static var countdownStart: Bool { flag(countdownStartKey, default: true) }

    private static func flag(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

/// The vocabulary's words through the speaker, ducking whatever else plays.
@MainActor
final class CueSpeaker {
    static let shared = CueSpeaker()

    private let speech = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        speech.speak(u)
    }

    /// The lead-in's word for a count, when Voice is on.
    func leadInWord(_ secondsLeft: Int) {
        guard WatchCueSettings.voice, let word = WatchCues.leadInWord(secondsLeft: secondsLeft) else { return }
        speak(word)
    }
}
