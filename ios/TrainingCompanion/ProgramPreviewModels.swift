import Foundation

// MARK: - What a program records about what its constraints held back

/// Why a slot is empty, read from the exercise the lifted constraint would
/// give (`selector._explain_unfilled`, the server's `blocked_by`).
struct SlotBlocker: Equatable {
    /// equipment | injury | level | phase | coverage
    let cause: String
    /// The exercise that would be there.
    let exercise: String?
    /// equipment: the items it needs that the athlete lacks.
    let needs: [String]
    /// injury: the flags that rule it out.
    let flags: [String]
    /// level: what it requires that the athlete's level has not reached.
    let requires: [String]
    let level: String?
    /// An injury substitute: the flag it came via.
    let via: String?
}

private extension JSONValue {
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var strings: [String] {
        if case .array(let a) = self { return a.compactMap(\.stringValue) }
        return []
    }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

extension ProgramExerciseAssignment {
    var blockedBy: SlotBlocker? {
        guard let b = extra["blocked_by"]?.object, let cause = b["cause"]?.stringValue else { return nil }
        return SlotBlocker(cause: cause, exercise: b["exercise"]?.stringValue,
                           needs: b["needs"]?.strings ?? [], flags: b["flags"]?.strings ?? [],
                           requires: b["requires"]?.strings ?? [], level: b["level"]?.stringValue,
                           via: b["via"]?.stringValue)
    }
    /// The exercise an injury flag's `modified_exercises` replaced with this one.
    var substitutedForExercise: String? { extra["substituted_for"]?.stringValue }
    var substitutedByFlag: String? { extra["substituted_by_flag"]?.stringValue }
    var equipmentGap: Bool { extra["equipment_gap"]?.bool ?? false }
    var coverageGap: Bool { extra["coverage_gap"]?.bool ?? false }
    /// A structural slot with no exercise (BJJ rounds, a circuit's wrapper).
    var skipsExercise: Bool { extra["skip_exercise"]?.bool ?? false }
}

extension ProgramSession {
    /// The modality this session was scheduled in place of (no archetype for it).
    var substitutedFor: String? { extra["substituted_for"]?.stringValue }
    /// level | phase: why no archetype of that modality fit.
    var substitutionCause: String? { extra["substitution_cause"]?.stringValue }
    /// The equipment its archetype asks for that the athlete lacks; it runs scaled.
    var equipmentScaled: [String] { extra["equipment_scaled"]?.strings ?? [] }
    /// A session no archetype could fill says why.
    var unfilledReason: String? { archetype == nil ? extra["error"]?.stringValue : nil }
}

extension ProgramWeek {
    /// Why a test the phase called for did not run this week.
    var testsSkippedReasons: [String] {
        guard case .array(let items)? = extra["tests_skipped"] else { return [] }
        return items.compactMap { $0.object?["reason"]?.stringValue }
    }
}

/// The validator's answer on a generated program.
struct ProgramValidation: Equatable {
    struct Message: Equatable, Identifiable {
        let code: String
        let message: String
        var id: String { code + message }
    }
    let feasible: Bool
    let errors: [Message]
    let warnings: [Message]
    let info: [Message]
}

extension GeneratedProgram {
    var validation: ProgramValidation? {
        guard let v = extra["validation"]?.object else { return nil }
        func messages(_ key: String) -> [ProgramValidation.Message] {
            guard case .array(let items)? = v[key] else { return [] }
            return items.compactMap { item in
                guard let o = item.object, let code = o["code"]?.stringValue,
                      let message = o["message"]?.stringValue else { return nil }
                return .init(code: code, message: message)
            }
        }
        return ProgramValidation(feasible: v["feasible"]?.bool ?? true, errors: messages("errors"),
                                 warnings: messages("warnings"), info: messages("info"))
    }

    /// A generate the server could not build — the validator's refusal, or a
    /// training contract that cannot run as written. Shown, never saved.
    var isInfeasible: Bool { weeks.isEmpty || validation?.feasible == false }

    var compromises: [String] { extra["compromises"]?.strings ?? [] }
}

// MARK: - Plain words (the phone's copy of the web's lib/heldBack.ts)

enum HeldBack {
    struct Names {
        var exercise: (String) -> String? = { _ in nil }
        var flag: (String) -> String? = { _ in nil }
    }

    static func label(_ id: String) -> String { id.replacingOccurrences(of: "_", with: " ") }

    /// "Back Squat needs barbell, rack" — what emptied one slot.
    static func blockerText(_ b: SlotBlocker, names: Names = Names()) -> String {
        let ex = b.exercise.map { names.exercise($0) ?? label($0) }
        let flags = b.flags.map { names.flag($0) ?? label($0) }.joined(separator: ", ")
        switch b.cause {
        case "equipment":
            let needs = b.needs.map(label).joined(separator: ", ")
            return "\(ex ?? "It") needs \(needs.isEmpty ? "equipment you have not listed" : needs)"
        case "injury":
            return "\(ex ?? "It") is ruled out by \(flags.isEmpty ? "an injury flag" : flags)"
        case "level":
            let needs = b.requires.map { names.exercise($0) ?? label($0) }
            return "\(ex ?? "It") is not unlocked at \(b.level ?? "your level")"
                + (needs.isEmpty ? "" : " (needs \(needs.joined(separator: ", ")))")
        case "phase":
            return "\(ex ?? "Its lift") comes in a later phase"
        default:
            return "The methodology's own library has nothing for this slot"
        }
    }

    /// Why an empty slot is empty, from its blocker or the older flags; nil
    /// for a filled or structural slot.
    static func emptySlotText(_ ea: ProgramExerciseAssignment, names: Names = Names()) -> String? {
        if ea.exercise != nil || ea.meta || ea.skipsExercise { return nil }
        if let b = ea.blockedBy { return blockerText(b, names: names) }
        if ea.injurySkip { return "Ruled out by an injury flag" }
        if ea.equipmentGap { return "Nothing fits your equipment" }
        if ea.coverageGap { return "The methodology's own library has nothing for this slot" }
        return nil
    }

    static func heldBackSlots(_ session: ProgramSession) -> Int {
        session.exercises.filter { emptySlotText($0) != nil }.count
    }

    /// Session-level notes: another modality in its place, or scaled for missing equipment.
    static func sessionNotes(_ session: ProgramSession) -> [String] {
        var out: [String] = []
        if let was = session.substitutedFor {
            let why = session.substitutionCause == "level" ? " (none written for your level)"
                : session.substitutionCause == "phase" ? " (none for this phase)" : ""
            out.append("In place of \(label(was))\(why)")
        }
        if !session.equipmentScaled.isEmpty {
            out.append("Scaled: written for \(session.equipmentScaled.map(label).joined(separator: ", "))")
        }
        if let reason = session.unfilledReason { out.append(reason) }
        return out
    }

    /// How much of a program its constraints held back: the server's count
    /// (`held_back`, src/blockers.held_back, on every generate), else — a
    /// program stored before it, or a draft edited since — counted here.
    static func summary(_ program: GeneratedProgram) -> (slots: Int, sessions: Int) {
        if case .object(let o)? = program.extra["held_back"],
           case .int(let slots)? = o["slots"], case .int(let sessions)? = o["sessions"] {
            return (slots, sessions)
        }
        return counts(program)
    }

    /// The same count from the weeks, for a program without the server's.
    static func counts(_ program: GeneratedProgram) -> (slots: Int, sessions: Int) {
        var slots = 0, sessions = 0
        for week in program.weeks {
            for list in week.schedule.values {
                for s in list {
                    let n = heldBackSlots(s)
                    slots += n
                    if n > 0 || !sessionNotes(s).isEmpty { sessions += 1 }
                }
            }
        }
        return (slots, sessions)
    }

    private static let scheduleCodes = ["SCHEDULE_", "INSUFFICIENT_DAYS", "MINIMAL_DAYS",
                                        "PHASE_DAYS_MISMATCH", "SESSION_TIME_", "SESSION_TOO_SHORT"]

    /// The validator's schedule and time findings and the scheduler's
    /// compromises — what no lifted run explains.
    static func scheduleFindings(_ program: GeneratedProgram) -> [String] {
        let v = program.validation
        var out = ((v?.errors ?? []) + (v?.warnings ?? []))
            .filter { m in m.code != "SCHEDULE_MEETS_IDEAL" && scheduleCodes.contains { m.code.hasPrefix($0) } }
            .map(\.message)
        for c in program.compromises where c.range(of: "days|volume|minutes|rest", options: .regularExpression) != nil {
            out.append(c)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

// MARK: - Index-addressed edits, shared by the active program and a draft

enum ProgramEdits {
    static func replacingSession(in program: GeneratedProgram, weekIndex: Int, day: String,
                                 sessionIndex: Int, with session: ProgramSession) -> GeneratedProgram {
        var weeks = program.weeks
        guard weeks.indices.contains(weekIndex) else { return program }
        let week = weeks[weekIndex]
        var sessions = week.schedule[day] ?? []
        guard sessions.indices.contains(sessionIndex) else { return program }
        sessions[sessionIndex] = session
        var schedule = week.schedule
        schedule[day] = sessions
        weeks[weekIndex] = ProgramWeek(weekNumber: week.weekNumber, weekInPhase: week.weekInPhase,
                                       isDeload: week.isDeload, phase: week.phase, schedule: schedule,
                                       extra: week.extra)
        return GeneratedProgram(weeks: weeks, extra: program.extra)
    }

    static func replacingExercise(in program: GeneratedProgram, weekIndex: Int, day: String,
                                  sessionIndex: Int, exerciseIndex: Int,
                                  with assignment: ProgramExerciseAssignment) -> GeneratedProgram {
        guard let session = program.weeks[safe: weekIndex]?.schedule[day]?[safe: sessionIndex],
              session.exercises.indices.contains(exerciseIndex) else { return program }
        var exercises = session.exercises
        exercises[exerciseIndex] = assignment
        return replacingSession(in: program, weekIndex: weekIndex, day: day, sessionIndex: sessionIndex,
                                with: ProgramSession(modality: session.modality, archetype: session.archetype,
                                                     isDeload: session.isDeload, exercises: exercises,
                                                     extra: session.extra))
    }
}

extension GenerateProgramRequest {
    /// The same request with other constraints — a re-preview.
    func with(constraints: GenerateConstraints) -> GenerateProgramRequest {
        GenerateProgramRequest(philosophyId: philosophyId, philosophyIds: philosophyIds,
                               philosophyWeights: philosophyWeights, lanes: lanes, constraints: constraints,
                               numWeeks: numWeeks, weekInProgram: weekInProgram,
                               startDate: startDate, eventDate: eventDate, persist: persist)
    }

    /// The methodologies it builds from, in order (a composition's, each once).
    var sourceIds: [String] {
        if let lanes, lanes.count > 1 {
            var ids: [String] = []
            for lane in lanes where !ids.contains(lane.philosophyId) { ids.append(lane.philosophyId) }
            return ids
        }
        return philosophyIds ?? philosophyId.map { [$0] } ?? []
    }

    /// Their weights: a composition's tracks' summed per methodology.
    var sourceWeights: [String: Double] {
        guard let lanes, lanes.count > 1 else { return philosophyWeights ?? [:] }
        let total = lanes.reduce(0) { $0 + $1.weight }
        return lanes.reduce(into: [:]) { $0[$1.philosophyId, default: 0] += $1.weight / (total > 0 ? total : 1) }
    }

    /// Held back's request for `draft`: the draft's own first track, phase and
    /// week in phase and its length (the comparison runs at most 12 weeks),
    /// never the event date. Sent as it was, the impact sized itself by
    /// defaults — 4 weeks from the track's first phase — and described another
    /// program than an event-dated 20-week draft.
    func impactRequest(for draft: GeneratedProgram) -> GenerateProgramRequest {
        var c = constraints
        // A composition: every track from the draft's own first week.
        let resumed = draft.regenerateLanes(from: 0)
        if resumed == nil, let first = draft.weeks.first {
            c.trackId = first.trackId ?? c.trackId
            if let phaseId = first.phaseId { c.startPhase = phaseId; c.trainingPhase = nil }
            c.periodizationWeek = first.weekInPhase
        }
        return GenerateProgramRequest(philosophyId: philosophyId, philosophyIds: philosophyIds,
                                      philosophyWeights: philosophyWeights, lanes: resumed ?? lanes, constraints: c,
                                      numWeeks: min(max(draft.weeks.count, 1), 12), weekInProgram: weekInProgram,
                                      startDate: startDate, eventDate: nil, persist: false)
    }
}

// MARK: - The server's comparisons

/// POST /programs/constraint-change: does a profile change change the program?
struct ConstraintChangeResult: Decodable {
    struct Entry: Decodable, Identifiable {
        let weekIndex: Int
        let weekNumber: Int
        let day: String
        let sessionIndex: Int
        let change: String
        var id: String { "\(weekIndex)|\(day)|\(sessionIndex)" }
        enum CodingKeys: String, CodingKey {
            case weekIndex = "week_index", weekNumber = "week_number", day
            case sessionIndex = "session_index", change
        }
    }
    struct Sessions: Decodable { let total: Int; let changed: Int }

    let affected: Bool
    /// False when the program's own constraints no longer build it: nothing
    /// to compare with, so nothing is adopted.
    let comparable: Bool
    let sessions: Sessions
    let firstWeekNumber: Int?
    let changes: [Entry]
    /// The rest of the program with the new constraints, when affected.
    let program: GeneratedProgram?

    enum CodingKeys: String, CodingKey {
        case affected, comparable, sessions, changes, program
        case firstWeekNumber = "first_week_number"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        affected = try c.decode(Bool.self, forKey: .affected)
        comparable = try c.decodeIfPresent(Bool.self, forKey: .comparable) ?? true
        sessions = try c.decodeIfPresent(Sessions.self, forKey: .sessions) ?? Sessions(total: 0, changed: 0)
        firstWeekNumber = try c.decodeIfPresent(Int.self, forKey: .firstWeekNumber)
        changes = (try? c.decodeIfPresent([Entry].self, forKey: .changes)) ?? []
        program = try? c.decodeIfPresent(GeneratedProgram.self, forKey: .program)
    }
}

/// POST /programs/impact: the preview's Held back (constraint_impact.analyse).
struct ConstraintImpact: Decodable {
    struct Why: Decodable, Hashable { let cause: String; let text: String }
    struct Named: Decodable, Hashable { let id: String?; let name: String? }
    struct SessionView: Decodable {
        let modality: String?
        let archetype: Named?
    }
    struct Slot: Decodable {
        let role: String?
        let kind: String?
        let from: Named?
        let to: Named?
        let causes: [String]
        let why: [Why]
        let knockOn: Bool
        enum CodingKeys: String, CodingKey { case role, kind, from, to, causes, why, knockOn = "knock_on" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            kind = try c.decodeIfPresent(String.self, forKey: .kind)
            from = try c.decodeIfPresent(Named.self, forKey: .from)
            to = try c.decodeIfPresent(Named.self, forKey: .to)
            causes = try c.decodeIfPresent([String].self, forKey: .causes) ?? []
            why = try c.decodeIfPresent([Why].self, forKey: .why) ?? []
            knockOn = try c.decodeIfPresent(Bool.self, forKey: .knockOn) ?? false
        }
    }
    struct Change: Decodable, Identifiable {
        let weekIndex: Int
        let weekNumber: Int
        let day: String
        let sessionIndex: Int
        let change: String
        let reference: SessionView?
        let actual: SessionView?
        let causes: [String]
        let why: [Why]
        let knockOn: Bool
        let slots: [Slot]
        var id: String { "\(weekIndex)|\(day)|\(sessionIndex)" }
        enum CodingKeys: String, CodingKey {
            case weekIndex = "week_index", weekNumber = "week_number", day, sessionIndex = "session_index"
            case change, reference, actual, causes, why, knockOn = "knock_on", slots
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weekIndex = try c.decode(Int.self, forKey: .weekIndex)
            weekNumber = try c.decodeIfPresent(Int.self, forKey: .weekNumber) ?? weekIndex + 1
            day = try c.decode(String.self, forKey: .day)
            sessionIndex = try c.decodeIfPresent(Int.self, forKey: .sessionIndex) ?? 0
            change = try c.decode(String.self, forKey: .change)
            reference = try c.decodeIfPresent(SessionView.self, forKey: .reference)
            actual = try c.decodeIfPresent(SessionView.self, forKey: .actual)
            causes = try c.decodeIfPresent([String].self, forKey: .causes) ?? []
            why = try c.decodeIfPresent([Why].self, forKey: .why) ?? []
            knockOn = try c.decodeIfPresent(Bool.self, forKey: .knockOn) ?? false
            slots = try c.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        }

        /// The cause it is filed under: its first direct one.
        var primaryCause: String {
            let all = causes.isEmpty ? slots.flatMap(\.causes) : causes
            return all.first { $0 != "combined" } ?? all.first ?? "combined"
        }

        /// "Week 2 · Monday · Barbell Complex → Goblet Circuit" and its reasons.
        var line: (title: String, detail: [String]) {
            let at = "Week \(weekNumber) · \(day)"
            if change == "slots" {
                let name = actual?.archetype?.name ?? reference?.archetype?.name ?? ""
                return ("\(at) · \(name)", slots.filter { !$0.knockOn }.map { s in
                    let was = s.from?.name ?? HeldBack.label(s.role ?? "slot")
                    let now = s.kind == "emptied" ? "left empty" : s.to.map { "now \($0.name ?? "")" } ?? ""
                    let why = s.why.map(\.text).joined(separator: "; ")
                    return "\(was) \(now)" + (why.isEmpty ? "" : " — \(why)")
                })
            }
            func name(_ v: SessionView?) -> String {
                v?.archetype?.name ?? v?.modality.map(HeldBack.label) ?? "nothing"
            }
            return ("\(at) · \(name(reference)) → \(name(actual))", why.map(\.text))
        }
    }
    struct Restore: Decodable, Identifiable { let id: String; let changes: Int }
    struct Reference: Decodable {
        let equipment: [String]?
        let trainingLevel: String?
        enum CodingKeys: String, CodingKey { case equipment, trainingLevel = "training_level" }
    }

    let feasible: Bool
    let referenceGenerates: Bool
    let detail: String?
    let lifts: [String: String]
    let lifted: [String]
    let reference: Reference?
    let changes: [Change]
    let restore: [Restore]
    /// A refused request: the one constraint that alone lets it generate.
    let unblockedBy: [Why]
    /// Every position either program has a session at — what `changes` is drawn from.
    let sessionsTotal: Int?

    enum CodingKeys: String, CodingKey {
        case feasible, detail, lifts, lifted, reference, changes, restore, sessions
        case referenceGenerates = "reference_generates", unblockedBy = "unblocked_by"
    }
    private struct RestoreBox: Decodable { let equipment: [Restore]? }
    private struct SessionsBox: Decodable { let total: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feasible = try c.decodeIfPresent(Bool.self, forKey: .feasible) ?? true
        referenceGenerates = try c.decodeIfPresent(Bool.self, forKey: .referenceGenerates) ?? true
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        lifts = (try? c.decodeIfPresent([String: String].self, forKey: .lifts)) ?? [:]
        lifted = try c.decodeIfPresent([String].self, forKey: .lifted) ?? []
        reference = try c.decodeIfPresent(Reference.self, forKey: .reference)
        changes = (try? c.decodeIfPresent([Change].self, forKey: .changes)) ?? []
        restore = (try? c.decodeIfPresent(RestoreBox.self, forKey: .restore))?.equipment ?? []
        unblockedBy = try c.decodeIfPresent([Why].self, forKey: .unblockedBy) ?? []
        sessionsTotal = (try? c.decodeIfPresent(SessionsBox.self, forKey: .sessions))?.total
    }

    var direct: [Change] { changes.filter { !$0.knockOn } }
    var knockOn: [Change] { changes.filter(\.knockOn) }
}
