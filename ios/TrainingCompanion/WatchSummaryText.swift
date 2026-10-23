import Foundation

/// The end of a session on the Apple Watch, as the Garmin's SummaryView.mc
/// lays it out: the package's summary pages in its order, the session's sets
/// and volume, and what was logged per step. Pure, and compiled into the app
/// and the watch so TrainingCompanionTests reads it.
enum WatchSummaryText {

    /// The pages this watch draws, in the package's order (the vocabulary's
    /// `summary_pages`). Training effect and training status are the Garmin's
    /// own measures — shown only where the watch has them, and the Apple Watch
    /// has neither. HR zones is this watch's heart-rate page, which already
    /// shows the minutes in each zone, so it is drawn once.
    static func pages(_ session: WatchSession) -> [String] {
        let drawn: Set<String> = ["summary", "heart_rate", "exercises"]
        let wanted = session.watch?.summary?.pages ?? WatchVocab.summaryPages
        var pages: [String] = []
        for page in wanted.map({ $0 == "hr_zones" ? "heart_rate" : $0 })
        where drawn.contains(page) && !pages.contains(page) {
            pages.append(page)
        }
        return pages.isEmpty ? ["summary"] : pages
    }

    static func totalSets(_ logs: [String: [WatchSetLog]]) -> Int {
        logs.values.reduce(0) { $0 + $1.count }
    }

    /// Reps × kg over every set, a double's bells both counted.
    static func volumeKg(_ session: WatchSession, _ logs: [String: [WatchSetLog]]) -> Double {
        logs.reduce(0) { total, entry in
            let bells = session.exercises.first { $0.exerciseId == entry.key }.map(WatchSpecText.bells) ?? 1
            return total + entry.value.reduce(0) { sum, set in
                guard let r = set.repsActual, let w = set.weightKg else { return sum }
                return sum + Double(r) * w * Double(bells)
            }
        }
    }

    /// What a step logged: "3x5 @ 100", "3x5 @ 2x24" (the last set's reps and
    /// load, as the Garmin writes it), "2x— @ 24" for holds; with no sets,
    /// what it produced — "7 rounds", "4:51", "3.4 km"; nil for nothing.
    static func loggedText(_ ex: WatchExercise, sets: [WatchSetLog], outcome: WatchOutcome?) -> String? {
        if let last = sets.last {
            let reps = last.repsActual.map(String.init) ?? "-"
            return "\(sets.count)x\(reps)" + (last.weightKg.map { " @ " + WatchSpecText.loadText(ex, $0) } ?? "")
        }
        guard let o = outcome else { return nil }
        if let r = o.rounds { return "\(r) round\(r == 1 ? "" : "s")" }
        if let km = o.distanceKm { return WatchSpecText.kg(km) + " km" }
        if let s = o.durationSec { return WatchSpecText.mmss(s) }
        return nil
    }

    /// The Exercises page: each step's name and what it logged, past the
    /// movements folded into an AMRAP.
    static func exerciseLines(_ session: WatchSession, logs: [String: [WatchSetLog]],
                              outcomes: [String: WatchOutcome]) -> [(name: String, logged: String?)] {
        session.exercises.indices
            .filter { !WatchSteps.isFolded(session, $0) }
            .map { i in
                let ex = session.exercises[i]
                return (ex.name, loggedText(ex, sets: logs[ex.exerciseId] ?? [], outcome: outcomes[ex.exerciseId]))
            }
    }
}
