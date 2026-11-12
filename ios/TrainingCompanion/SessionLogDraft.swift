import Foundation

/// One exercise of the session log form (design-system §6.16): what the form
/// shows for it and what it would save.
///
/// A sets × reps or hold slot has one row per set — reps (or seconds), kg,
/// RPE, done; any other slot has its currency fields. Both start from what
/// was logged before, else from the prescription. Only an **included**
/// exercise is saved: one already logged, the one the form was opened at,
/// and any the athlete touches — so a prefilled prescription nobody looked
/// at is never written as a result.
struct ExerciseLogDraft: Identifiable, Equatable {
    struct SetRow: Identifiable, Equatable {
        var id = UUID()
        var reps: Int
        var seconds: Int
        var kg: Double?
        var rpe: Int          // 0 = not rated
        var completed: Bool
    }

    /// Everything the athlete can change; a change includes the exercise.
    struct Values: Equatable {
        var sets: [SetRow] = []
        var minutes: Double? = nil
        /// A for-time clock as typed ("7:32"); never prefilled from the cap,
        /// which would otherwise be saved as the result of a test nobody changed.
        var clock = ""
        var km: Double? = nil
        var rounds: Int? = nil
        var reps: Int? = nil
        var holdSeconds: Int? = nil
        var clean = false
        var moduleRpe = 0
        var moduleWeight: Double? = nil
    }

    /// Position in the session plus the exercise, as the session's rows are keyed.
    let id: String
    let exerciseId: String
    let name: String
    let prescription: String
    let slotType: String
    let fields: [OutcomeField]
    /// A training-contract block: clean, RPE and the bell ride on the log.
    let isModule: Bool
    /// The cap as a hint, never as a value.
    let timePlaceholder: String
    /// A test's scored slot: what is logged comes back as a result to save.
    let isTest: Bool
    /// There was a log for it when the form opened.
    let wasLogged: Bool

    var values: Values
    var included: Bool

    var logsSets: Bool { fields.isEmpty }
    var isHold: Bool { slotType == "static_hold" }
    var asksClean: Bool { slotType == "skill_practice" || isModule }

    /// A clock that does not read as one keeps Save off rather than saving something else.
    var clockInvalid: Bool {
        fields.contains(.time) && !values.clock.trimmingCharacters(in: .whitespaces).isEmpty
            && SessionLogging.parseClock(values.clock) == nil
    }

    init?(index: Int, assignment: ProgramExerciseAssignment, existing: ExercisePerformanceLog?) {
        guard let exercise = assignment.exercise, !assignment.injurySkip else { return nil }
        let load = assignment.load
        id = "\(index)-\(exercise.id)"
        exerciseId = exercise.id
        name = exercise.name
        prescription = LoadFormat.describe(assignment)
        slotType = LoadFormat.resolvedSlotType(assignment)
        fields = SessionLogging.outcomeFields(for: slotType, category: exercise.category,
                                              patterns: SessionLogging.patterns(of: exercise),
                                              standardResult: assignment.standardResult)
        isModule = load.extra["module_id"] != nil
        timePlaceholder = load.timeMinutes.map { "cap \($0):00" } ?? "m:ss"
        isTest = assignment.standardId != nil
        wasLogged = existing != nil
        included = existing != nil

        var v = Values()
        v.clean = existing?.clean ?? false
        v.moduleRpe = existing?.rpe ?? 0
        v.moduleWeight = existing?.weightKg ?? load.weightKg
        if fields.isEmpty {
            if let existing, !existing.sets.isEmpty {
                v.sets = existing.sets.sorted { $0.setIndex < $1.setIndex }.map {
                    SetRow(reps: $0.repsActual ?? 0, seconds: $0.durationSeconds ?? load.holdSeconds ?? 30,
                           kg: $0.weightKg, rpe: $0.rpe ?? 0, completed: $0.completed)
                }
            } else {
                let count = max(1, load.sets ?? 3)
                let reps = load.reps?.intValue ?? 5
                v.sets = (0..<count).map { _ in
                    SetRow(reps: reps, seconds: load.holdSeconds ?? 30, kg: load.weightKg, rpe: 0, completed: true)
                }
            }
        } else {
            v.minutes = existing?.durationSec.map { Double($0) / 60 }
                ?? (load.durationMinutes ?? load.timeMinutes).map(Double.init)
            v.clock = existing?.durationSec.map(SessionLogging.formatClock) ?? ""
            v.km = existing?.distanceKm ?? load.distanceKm
            v.rounds = existing?.rounds ?? load.targetRounds
            v.reps = existing?.sets.first?.repsActual
            v.holdSeconds = existing?.sets.first?.durationSeconds ?? load.holdSeconds
        }
        values = v
    }

    /// Another set like the last one.
    mutating func addSet() {
        let last = values.sets.last
        values.sets.append(SetRow(reps: last?.reps ?? 5, seconds: last?.seconds ?? 30,
                                  kg: last?.kg, rpe: 0, completed: true))
    }

    /// What the form would save for this exercise, in the server's shape.
    func performance() -> ExercisePerformanceLog {
        var perf = ExercisePerformanceLog()
        if logsSets {
            perf.sets = values.sets.enumerated().map { i, d in
                WatchSetLog(setIndex: i, repsActual: isHold ? nil : d.reps, weightKg: d.kg,
                            rpe: d.rpe > 0 ? d.rpe : nil, completed: d.completed,
                            durationSeconds: isHold ? d.seconds : nil, startOffset: nil, endOffset: nil)
            }
        } else {
            if fields.contains(.minutes), let m = values.minutes, m > 0 { perf.durationSec = Int((m * 60).rounded()) }
            if fields.contains(.time), let sec = SessionLogging.parseClock(values.clock) { perf.durationSec = sec }
            if fields.contains(.km), let k = values.km, k > 0 { perf.distanceKm = k }
            if fields.contains(.rounds), let r = values.rounds, r > 0 { perf.rounds = r }
            // Reps in a window and a hold's seconds sit on the first set, where
            // the rate and hold primitives read them.
            let r = fields.contains(.reps) ? values.reps.flatMap { $0 > 0 ? $0 : nil } : nil
            let s = fields.contains(.seconds) ? values.holdSeconds.flatMap { $0 > 0 ? $0 : nil } : nil
            if r != nil || s != nil {
                perf.sets = [WatchSetLog(setIndex: 0, repsActual: r, weightKg: nil, rpe: nil, completed: true,
                                         durationSeconds: s, startOffset: nil, endOffset: nil)]
            }
        }
        if asksClean { perf.clean = values.clean }
        if isModule && values.moduleRpe > 0 { perf.rpe = values.moduleRpe }
        // With set rows the sets say the weight; a block-level one would overrule them.
        if isModule && !logsSets, let weight = values.moduleWeight, weight > 0 { perf.weightKg = weight }
        return perf
    }
}

/// The whole form: every loggable exercise of a session, saved in one go.
enum SessionLogDraft {
    /// One draft per exercise the session logs, in the session's order. The
    /// log is keyed by exercise id, so a movement the session lists twice is
    /// one entry — its first. `openAt` (an exercise id) is included from the
    /// start: the athlete asked to log it.
    static func exercises(of session: ProgramSession, log: SessionLogEntry?,
                          openAt: String? = nil) -> [ExerciseLogDraft] {
        var seen = Set<String>()
        return session.exercises.enumerated().compactMap { index, assignment in
            guard let id = assignment.exercise?.id, !seen.contains(id),
                  var draft = ExerciseLogDraft(index: index, assignment: assignment,
                                               existing: log?.exercises[id]) else { return nil }
            seen.insert(id)
            if id == openAt { draft.included = true }
            return draft
        }
    }

    /// What Save writes: the included exercises that say something.
    static func performances(_ drafts: [ExerciseLogDraft]) -> [String: ExercisePerformanceLog] {
        var out: [String: ExercisePerformanceLog] = [:]
        for draft in drafts where draft.included {
            let perf = draft.performance()
            if perf.isEmpty && perf.clean == nil && !draft.wasLogged { continue }
            out[draft.exerciseId] = perf
        }
        return out
    }

    /// An included exercise's clock that is not one keeps Save off.
    static func isInvalid(_ drafts: [ExerciseLogDraft]) -> Bool {
        drafts.contains { $0.included && $0.clockInvalid }
    }
}
