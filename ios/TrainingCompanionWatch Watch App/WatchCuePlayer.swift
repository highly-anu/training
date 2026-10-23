import AVFoundation
import SwiftUI
import WatchKit

/// The watch's cue settings, the Garmin's (Cues.mc) with what only the Apple
/// Watch can do: speak. Kept on the watch, set on its Settings page.
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

/// Plays the lead-in (WatchCues.leadIn): a click on each count and the start
/// haptic on the go — a haptic sounds as well unless the watch is silenced —
/// and, with Voice on, the vocabulary's words through the speaker, ducking
/// whatever else is playing.
@MainActor
final class WatchCuePlayer {
    static let shared = WatchCuePlayer()

    private let speech = AVSpeechSynthesizer()

    func play(_ cue: WatchCues.LeadIn, secondsLeft: Int) {
        WKInterfaceDevice.current().play(cue == .go ? .start : .click)
        guard WatchCueSettings.voice, let word = WatchCues.leadInWord(secondsLeft: secondsLeft) else { return }
        speak(word)
    }

    /// The go, where a clock rolls into work.
    func go() { play(.go, secondsLeft: 0) }

    private func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        speech.speak(u)
    }
}

/// Settings on the watch: the lead-in and what it sounds like.
struct WatchSettingsView: View {
    @AppStorage(WatchCueSettings.leadInKey) private var leadIn = true
    @AppStorage(WatchCueSettings.countdownStartKey) private var countdownStart = true
    @AppStorage(WatchCueSettings.voiceKey) private var voice = false

    var body: some View {
        List {
            Section {
                Toggle("Lead-in", isOn: $leadIn)
                Toggle("Countdown Start", isOn: $countdownStart)
            } footer: {
                Text("“Work in 3, 2, 1, go” before work on a clock, and after Start.")
            }
            Section {
                Toggle("Voice", isOn: $voice)
            } footer: {
                Text(voice ? "Says the count, with a tap on each."
                           : "A tap and a click on each count; the start tone on the go.")
            }
            Button("Try it") { tryIt() }
        }
        .navigationTitle("Settings")
    }

    private func tryIt() {
        for left in stride(from: WatchVocab.leadInSeconds, through: 0, by: -1) {
            let delay = Double(WatchVocab.leadInSeconds - left)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let cue = WatchCues.leadIn(secondsLeft: left) {
                    WatchCuePlayer.shared.play(cue, secondsLeft: left)
                }
            }
        }
    }
}
