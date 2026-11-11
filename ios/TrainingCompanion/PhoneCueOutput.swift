import AudioToolbox
import UIKit

/// The phone's cues for the workout engine (WorkoutCueOutput). The phone is
/// on the floor or a bench, not on the wrist, so a cue that matters — the
/// lead-in's count, the go, a step's end — sounds as well as vibrating; the
/// count's words are spoken with Voice on (CueSpeaker, ducking music).
@MainActor
final class PhoneCueOutput: WorkoutCueOutput {
    static let shared = PhoneCueOutput()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()

    /// System sounds (AudioToolbox): short, and they mix with the athlete's music.
    private enum Tone: SystemSoundID {
        case tick = 1104      // keyboard click
        case go = 1113        // begin
        case end = 1114       // end
        case alert = 1005     // alarm
    }

    func haptic(_ cue: CueHaptic) {
        switch cue {
        case .click, .directionUp:
            light.impactOccurred()
        case .turnLeft, .turnRight:
            heavy.impactOccurred()
        case .start:
            heavy.impactOccurred()
            play(.go)
        case .stop:
            heavy.impactOccurred()
            play(.end)
        case .notification:
            notice.notificationOccurred(.warning)
            play(.alert)
        case .success:
            notice.notificationOccurred(.success)
            play(.end)
        }
    }

    func leadIn(_ cue: WatchCues.LeadIn, secondsLeft: Int) {
        if cue == .go {
            heavy.impactOccurred()
            play(.go)
        } else {
            light.impactOccurred()
            play(.tick)
        }
        CueSpeaker.shared.leadInWord(secondsLeft)
    }

    /// The step the workout moved to, said aloud with Voice on ("Rest", "Round 3
    /// of 8 · Swing"): the phone may be across the room.
    func announce(_ text: String) {
        guard WatchCueSettings.voice, !text.isEmpty else { return }
        CueSpeaker.shared.speak(text.replacingOccurrences(of: " · ", with: ". "))
    }

    private func play(_ tone: Tone) {
        AudioServicesPlaySystemSound(tone.rawValue)
    }
}
