import ActivityKit
import Foundation

/// The workout player's Live Activity (design-system §6.44): the step and its
/// countdown on the Lock Screen and in the Dynamic Island while the phone is
/// locked or in another app. Compiled into the app, which starts and updates
/// it (WorkoutLockScreen), and the widget extension, which draws it
/// (TrainingWidgets/WorkoutLiveActivity.swift).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// What the athlete is doing: "Back Squat — set 2 of 5", "Rest · up next Bench".
        var title: String
        /// The phase: work, rest, or a step that waits for the athlete.
        var phase: Phase
        /// When the phase ends by the clock; nil when it waits for the athlete.
        var endsAt: Date?
        /// What comes after it: "Round 3 of 8 · Swing".
        var next: String?
        /// Step n of N.
        var step: Int
        var steps: Int
        /// A timed step, whose clock the athlete may hold: the Pause button.
        var canPause: Bool = false
        /// Held: the clock stands, the button says Resume.
        var paused: Bool = false

        enum Phase: String, Codable, Hashable { case work, rest, waiting, done }
    }

    /// The session: "Strength A".
    var sessionName: String
    /// Its modality, for its colour.
    var modalityId: String
}
