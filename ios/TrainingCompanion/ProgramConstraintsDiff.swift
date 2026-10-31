import Foundation

/// What the profile says now versus what the active program was built for —
/// the phone's copy of the web's `lib/programConstraintsDiff.ts`.
///
/// The program carries the constraints it was generated from (`constraints`
/// in `GeneratedProgram.extra`, kept since saves round-trip the envelope);
/// the profile moves on. Until the two were compared, the phone's only
/// regenerate replaced the whole program.
struct ConstraintDifference: Equatable, Identifiable {
    let field: String
    let label: String
    /// What the program was built for.
    let program: String
    /// What the profile says now.
    let profile: String
    var id: String { field }
}

enum ProgramConstraintsDiff {

    /// Days with at least one non-rest session; nil without a schedule.
    static func daysPerWeek(_ schedule: WeeklySchedule?) -> Int? {
        guard let schedule, !schedule.isEmpty else { return nil }
        return schedule.values.filter { d in
            [d.session1, d.session2, d.session3, d.session4].contains { $0 != .rest }
        }.count
    }

    static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    static func string(_ value: JSONValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }

    static func int(_ value: JSONValue?) -> Int? {
        switch value {
        case .int(let i)?: return i
        case .double(let d)?: return Int(d.rounded())
        default: return nil
        }
    }

    /// Ids that are never equipment: a web-built program carries `open_space`
    /// and the profile has none, which read as a difference on every program.
    static func realEquipment(_ ids: [String]) -> [String] {
        ids.filter { $0 != "open_space" && $0 != "none" }
    }

    private static func setChange(from: [String], to: [String]) -> String {
        let added = Set(to).subtracting(from).count
        let removed = Set(from).subtracting(to).count
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        return parts.isEmpty ? "unchanged" : parts.joined(separator: ", ")
    }

    /// `program` is the stored program's `constraints` object.
    static func differences(program: [String: JSONValue], profile: UserProfile) -> [ConstraintDifference] {
        guard !program.isEmpty else { return [] }
        var out: [ConstraintDifference] = []
        if let level = string(program["training_level"]), !profile.trainingLevel.isEmpty, level != profile.trainingLevel {
            out.append(ConstraintDifference(field: "training_level", label: "Training level",
                                            program: level, profile: profile.trainingLevel))
        }
        let equipment = realEquipment(strings(program["equipment"]))
        let kit = realEquipment(profile.equipment)
        if !kit.isEmpty, Set(equipment) != Set(kit) {
            out.append(ConstraintDifference(field: "equipment", label: "Equipment",
                                            program: "\(equipment.count) items",
                                            profile: setChange(from: equipment, to: kit)))
        }
        if let days = daysPerWeek(profile.weeklySchedule), days > 0,
           let planned = int(program["days_per_week"]), planned != days {
            out.append(ConstraintDifference(field: "days_per_week", label: "Days per week",
                                            program: String(planned), profile: String(days)))
        }
        let injuries = strings(program["injury_flags"])
        if Set(injuries) != Set(profile.injuryFlags) {
            out.append(ConstraintDifference(field: "injury_flags", label: "Injuries",
                                            program: "\(injuries.count) flagged",
                                            profile: setChange(from: injuries, to: profile.injuryFlags)))
        }
        return out
    }

    /// The program's constraints with the profile's current values applied,
    /// continuing the phase the regenerated week is in.
    ///
    /// `phaseId` and `trackId` are the week's own (`ProgramWeek.phaseId`,
    /// `.trackId`). Without them the server starts the tail on the
    /// methodology's primary track at the first phase of the week's kind — a
    /// Wildman Pentathlon Prep program came back as General Practice. They are
    /// nil for weeks generated before phases had ids; `phase` (the kind) is
    /// still sent for those.
    static func merged(program: [String: JSONValue], profile: UserProfile,
                       weekInPhase: Int?, phase: String?,
                       phaseId: String? = nil, trackId: String? = nil) -> GenerateConstraints {
        var c = GenerateConstraints()
        c.trainingLevel = profile.trainingLevel.isEmpty
            ? (string(program["training_level"]) ?? c.trainingLevel) : profile.trainingLevel
        c.daysPerWeek = int(program["days_per_week"]) ?? c.daysPerWeek
        if let days = daysPerWeek(profile.weeklySchedule), days > 0 { c.daysPerWeek = days }
        c.sessionTimeMinutes = int(program["session_time_minutes"]) ?? c.sessionTimeMinutes
        let programEquipment = strings(program["equipment"])
        c.equipment = profile.equipment.isEmpty ? programEquipment : profile.equipment
        c.injuryFlags = profile.injuryFlags
        c.phase = phase ?? string(program["training_phase"])
        c.trainingPhase = c.phase
        c.startPhase = phaseId
        c.trackId = trackId ?? string(program["track_id"])
        c.periodizationWeek = weekInPhase
        // What a training contract's athlete confirmed: without them a
        // rebuild of a contract program asks again and is refused.
        c.masteredExercises = strings(program["mastered_exercises"])
        c.kettlebellCount = int(program["kettlebell_count"])
        for (key, value) in program where key.hasSuffix("_count") && key != "kettlebell_count" {
            if let count = int(value) { c.implementCounts[key] = count }
        }
        return c
    }

    /// The same request with the program's own constraints and none of the
    /// profile's — what `POST /programs/constraint-change` compares the
    /// profile's version with.
    static func baseline(program: [String: JSONValue], weekInPhase: Int?, phase: String?,
                         phaseId: String? = nil, trackId: String? = nil) -> GenerateConstraints {
        var own = UserProfile.default
        own.trainingLevel = string(program["training_level"]) ?? ""
        own.equipment = strings(program["equipment"])
        own.injuryFlags = strings(program["injury_flags"])
        own.weeklySchedule = nil
        return merged(program: program, profile: own, weekInPhase: weekInPhase, phase: phase,
                      phaseId: phaseId, trackId: trackId)
    }
}

/// Splicing a regenerated tail onto the weeks already behind the athlete —
/// what the web's `useRegenerateFromWeek` does on success.
enum Regeneration {
    /// Keeps `weeks[0..<start]`, appends the generated weeks, takes the
    /// generated program's goal, constraints, validation and coverage report,
    /// and drops `volume_summary` so the server recomputes it for the whole
    /// program on save.
    ///
    /// With `programStartDate` and `keepBefore` (both YYYY-MM-DD, the
    /// athlete's day), no session dated before `keepBefore` is replaced: the
    /// week the tail starts at keeps the days already behind the athlete.
    /// Splicing whole weeks rewrote them, so the sessions done and matched
    /// this week left the plan, and the week's adherence with them; with the
    /// past unchanged the server carries the block on instead of switching
    /// program (`program_history.carry_over_until`). The web's
    /// `spliceRegenerated` is the same rule.
    static func splice(current: GeneratedProgram, from start: Int, generated: GeneratedProgram,
                       programStartDate: String? = nil, keepBefore: String? = nil) -> GeneratedProgram {
        let keep = max(0, min(start, current.weeks.count))
        var extra = current.extra
        for key in ["goal", "constraints", "validation", "coverage_report"] {
            if let value = generated.extra[key] { extra[key] = value }
        }
        extra.removeValue(forKey: "volume_summary")
        var weeks = Array(current.weeks.prefix(keep)) + generated.weeks
        if let programStartDate, let keepBefore {
            for i in keep..<min(weeks.count, current.weeks.count) {
                let kept = dayOrder.enumerated().filter { offset, _ in
                    (dayDate(programStartDate, days: i * 7 + offset) ?? keepBefore) < keepBefore
                }.map(\.element)
                guard !kept.isEmpty else { continue }
                let new = weeks[i], old = current.weeks[i]
                var schedule = new.schedule
                for day in kept { schedule[day] = old.schedule[day]?.isEmpty == false ? old.schedule[day] : nil }
                weeks[i] = ProgramWeek(weekNumber: new.weekNumber, weekInPhase: new.weekInPhase,
                                       isDeload: new.isDeload, phase: new.phase, schedule: schedule,
                                       extra: new.extra)
            }
        }
        return GeneratedProgram(weeks: weeks, extra: extra)
    }

    /// The regenerated tail as it will be saved: the days already behind the
    /// athlete in its first week are the program's own (`splice`), so the
    /// preview shows what Apply keeps — the web's `regeneratePreviewDraft`.
    static func previewTail(current: GeneratedProgram, from start: Int, generated: GeneratedProgram,
                            programStartDate: String?, keepBefore: String) -> GeneratedProgram {
        guard !generated.isInfeasible else { return generated }
        let spliced = splice(current: current, from: start, generated: generated,
                             programStartDate: programStartDate, keepBefore: keepBefore)
        let keep = max(0, min(start, current.weeks.count))
        return GeneratedProgram(weeks: Array(spliced.weeks.dropFirst(keep)), extra: generated.extra)
    }

    /// The sessions a regenerated tail plans differently from the weeks it
    /// replaces, as ProgramPreviewView's "week|day|index" ids (tail-relative)
    /// — the web's `changedSessionKeys`. A day the tail leaves emptier is
    /// marked on its last session, so a removed session is never silent.
    static func changedSessions(current: GeneratedProgram, tail: GeneratedProgram, from start: Int) -> Set<String> {
        func signature(_ s: ProgramSession) -> String {
            "\(s.modality)|\(s.archetype?.id ?? "")|\(s.archetype?.name ?? "")|"
                + s.exercises.map { $0.exercise?.id ?? "" }.joined(separator: ",")
        }
        var ids: Set<String> = []
        for (i, week) in tail.weeks.enumerated() {
            let old = start + i < current.weeks.count ? current.weeks[start + i] : nil
            for day in dayOrder {
                let now = week.schedule[day] ?? [], was = old?.schedule[day] ?? []
                for s in 0..<max(now.count, was.count) {
                    let a = s < now.count ? signature(now[s]) : nil
                    let b = s < was.count ? signature(was[s]) : nil
                    if a != b { ids.insert("\(i)|\(day)|\(min(s, max(0, now.count - 1)))") }
                }
            }
        }
        return ids
    }

    static let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// `start` + `days` as YYYY-MM-DD — `workout_matcher.session_calendar_date`'s
    /// arithmetic, in UTC so a daylight-saving change cannot move a day.
    static func dayDate(_ start: String, days: Int) -> String? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(start.prefix(10))) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f.timeZone
        return cal.date(byAdding: .day, value: days, to: d).map(f.string(from:))
    }
}
