import Foundation

/// A session's steps as the Garmin walks them (Steps.mc and the step logic
/// of WorkoutController.mc): what a step is called in the "Next:" line, what
/// comes next, and the AMRAP's movements, which are part of its round rather
/// than steps of their own. Pure, and compiled into the app and the watch so
/// TrainingCompanionTests runs it.
enum WatchSteps {

    /// One step's prescription, for the "Next:" line: "5 Reps @ 100 kg",
    /// "Hold :30", "8 x 0:20 / 0:10", "20 min AMRAP", "20:00  Z2". A double's
    /// load reads as the total here, as the athlete lifts it: "5 Reps @ 48 kg".
    static func preview(_ ex: WatchExercise, _ screen: WatchScreen) -> String {
        let at = ex.weightKg.map {
            " @ " + WatchSpecText.kg($0 * Double(WatchSpecText.bells(ex))) + " kg"
        } ?? ""
        let mmss = WatchSpecText.mmss
        switch screen.template {
        case .sets:
            return (ex.reps ?? "?") + " Reps" + at
        case .hold:
            return "Hold " + WatchSpecText.secs(ex.holdSeconds ?? 30) + at
        case .distance:
            if let km = ex.distanceKm {
                return WatchSpecText.kg(km) + " km" + (ex.packLoadKg.map { "  pack \(WatchSpecText.kg($0)) kg" } ?? "")
            }
            if let m = ex.distanceM { return "\(m) m" + at }
        case .interval:
            var line = ex.targetRounds.map { "\($0) x " } ?? ""
            line += (ex.workSec ?? 0) > 0 ? mmss(ex.workSec!) : "EMOM"
            if let r = WatchSpecText.rpm(ex, screen) { return line + " @ \(r) RPM" }
            if ex.prescribedZoneLower != nil { return line + "  " + zoneText(ex) }
            if let rest = ex.intervalRestSec, rest > 0 { line += " / " + mmss(rest) }
            return line + at
        case .rounds where ex.parentSlotRole == nil:
            return (ex.timeMinutes.map { "\($0) min " } ?? "") + "AMRAP"
        case .forTime:
            if let scheme = ex.repScheme, !scheme.isEmpty {
                return scheme.map(String.init).joined(separator: "-") + " for time"
            }
            return (ex.targetRounds.map { "\($0) Rounds " } ?? "") + "for time"
        default:
            break
        }
        if let mins = ex.durationMinutes {
            return mmss(mins * 60) + (ex.prescribedZoneLower.map { "  Z\($0)" } ?? "")
        }
        return ex.loadDescription
    }

    /// "Z3-4" / "Z2".
    static func zoneText(_ ex: WatchExercise) -> String {
        guard let z = ex.prescribedZoneLower else { return "" }
        let hi = ex.prescribedZoneUpper
        return "Z\(z)" + ((hi != nil && hi != z) ? "-\(hi!)" : "")
    }

    /// Sets and holds are counted set by set, with a rest after each.
    static func isSetBased(_ screen: WatchScreen) -> Bool {
        screen.template == .sets || screen.template == .hold
    }

    /// The rest after a set (the server's, which carries the modality's
    /// default); none for a step that is not set by set.
    static func restSec(_ ex: WatchExercise, _ screen: WatchScreen) -> Int {
        isSetBased(screen) ? max(0, ex.restSeconds ?? 0) : 0
    }

    // MARK: - An AMRAP's movements

    /// The movements of the AMRAP or for-time piece at `index`: the
    /// `amrap_movement` steps that name it as their parent — or, from a payload
    /// before `parentSlotRole`, those after it. They arrive as siblings of the
    /// piece; drawn as steps of their own they turned one 20-minute AMRAP into
    /// unrelated blocks, and Fran's pull-ups into a step after every thruster
    /// (the Garmin always folded them).
    static func components(of session: WatchSession, at index: Int) -> [WatchExercise] {
        let list = session.exercises
        guard index < list.count, !list[index].slotRole.isEmpty,
              [.rounds, .forTime].contains(session.screen(for: list[index]).template),
              list[index].slotType != "amrap_movement" else { return [] }
        let role = list[index].slotRole
        return list.enumerated().compactMap { i, c in
            guard c.slotType == "amrap_movement" else { return nil }
            if let parent = c.parentSlotRole { return parent == role ? c : nil }
            return i > index ? c : nil
        }
    }

    /// A step drawn inside its AMRAP's round, never on its own.
    static func isFolded(_ session: WatchSession, _ index: Int) -> Bool {
        let list = session.exercises
        guard index < list.count, list[index].slotType == "amrap_movement" else { return false }
        return (0..<list.count).contains { i in
            i != index && components(of: session, at: i).contains { $0.exerciseId == list[index].exerciseId }
        }
    }

    /// The step after `index`, past the movements folded into an AMRAP; the
    /// exercise count when there is none.
    static func indexAfter(_ session: WatchSession, _ index: Int) -> Int {
        var i = index + 1
        while i < session.exercises.count && isFolded(session, i) { i += 1 }
        return i
    }

    // MARK: - What comes next

    /// The "Next:" line's title and value (WorkoutController.nextStep): the
    /// next set over a rest, "Rest" before one, else the next step — or
    /// "Finish".
    static func nextStep(_ session: WatchSession, index: Int, setsDone: Int,
                         resting: Bool) -> (title: String, value: String?) {
        let list = session.exercises
        guard index < list.count else { return ("Finish", nil) }
        let ex = list[index], screen = session.screen(for: ex)
        let n = WatchSpecText.setCount(ex, screen)
        let following = indexAfter(session, index)
        let upcoming = following < list.count ? list[following] : nil
        func stepOf(_ e: WatchExercise?) -> (String, String?) {
            e.map { ($0.name, preview($0, session.screen(for: $0))) } ?? ("Finish", nil)
        }
        if resting {
            // A rest after the last set leads on to the next step.
            if setsDone >= n { return stepOf(upcoming) }
            return (ex.name, "Set \(setsDone + 1)/\(n)  " + preview(ex, screen))
        }
        let rest = restSec(ex, screen)
        if isSetBased(screen) && rest > 0 && (setsDone + 1 < n || upcoming != nil) {
            return ("Rest", WatchSpecText.mmss(rest))
        }
        return stepOf(upcoming)
    }
}

/// The cues a step's clock fires, as the Garmin's updateIntervalTiming does:
/// the hand switch `switchAtSec` into the work (a timed block's, or each
/// interval's), and an interval rest that ends on heart rate.
enum WatchCues {
    /// The work second at which the hands switch.
    static func switchDue(_ ex: WatchExercise, workSecond: Int) -> Bool {
        guard let at = ex.switchAtSec, at > 0 else { return false }
        return workSecond == at
    }

    /// The lead-in before work that starts on a clock (watch_vocabulary.json
    /// `cues`, the Garmin's Cues.leadIn): a tick on each of the last
    /// `WatchVocab.leadInSeconds` seconds, then the go at 0.
    enum LeadIn: Equatable { case tick, go }

    static func leadIn(secondsLeft: Int) -> LeadIn? {
        guard secondsLeft >= 0, secondsLeft <= WatchVocab.leadInSeconds else { return nil }
        return secondsLeft == 0 ? .go : .tick
    }

    /// The vocabulary's word for `secondsLeft` ("Work in 3", "2", "1", "Go"):
    /// what the screen shows while counting and what Voice says.
    static func leadInWord(secondsLeft: Int) -> String? {
        let i = WatchVocab.leadInSeconds - secondsLeft
        return WatchVocab.leadInWords.indices.contains(i) ? WatchVocab.leadInWords[i] : nil
    }

    /// A rest with `restUntilHr`: over once the heart rate has stayed under
    /// it for five seconds; the rest's own time is then only its cap.
    struct RestGate: Equatable {
        static let holdSec = 5
        var below = 0

        /// One second of the rest; true once it is over.
        mutating func tick(heartRate: Int?, target: Int) -> Bool {
            if let hr = heartRate, hr > 0, hr < target { below += 1 } else { below = 0 }
            return below >= Self.holdSec
        }
    }
}
