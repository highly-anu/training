import SwiftUI
import WatchKit

/// The watch's cues (WorkoutCueOutput): the wrist's haptics, and the lead-in
/// (WatchCues.leadIn) as a click on each count and the start haptic on the
/// go — a haptic sounds as well unless the watch is silenced — with the
/// vocabulary's words spoken when Voice is on (CueSpeaker).
@MainActor
final class WatchCueOutput: WorkoutCueOutput {
    static let shared = WatchCueOutput()

    func haptic(_ cue: CueHaptic) {
        WKInterfaceDevice.current().play(Self.type(cue))
    }

    func leadIn(_ cue: WatchCues.LeadIn, secondsLeft: Int) {
        WKInterfaceDevice.current().play(cue == .go ? .start : .click)
        CueSpeaker.shared.leadInWord(secondsLeft)
    }

    static func type(_ cue: CueHaptic) -> WKHapticType {
        switch cue {
        case .start: return .start
        case .stop: return .stop
        case .click: return .click
        case .notification: return .notification
        case .success: return .success
        case .directionUp: return .directionUp
        case .turnLeft: return .navigationLeftTurn
        case .turnRight: return .navigationRightTurn
        }
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
                    WatchCueOutput.shared.leadIn(cue, secondsLeft: left)
                }
            }
        }
    }
}
