import XCTest
@testable import TrainingCompanion

/// The program preview on the phone: what the server records about what was
/// held back, in words (the web's `lib/heldBack.ts`); the two comparisons it
/// answers decoded; a draft edited without touching the active program; and
/// the requests the regenerate check sends.
final class ProgramPreviewTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// One week, Monday: a filled squat and a slot equipment emptied.
    private let programJSON = """
    {"weeks": [{"week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base",
      "tests_skipped": [{"reason": "equipment_gap"}],
      "schedule": {"Monday": [{"modality": "max_strength", "is_deload": false,
        "archetype": {"id": "a", "name": "Workout A"},
        "substituted_for": "power", "substitution_cause": "level",
        "exercises": [
          {"exercise": {"id": "back_squat", "name": "Back Squat"}, "load": {"sets": 3, "reps": 5},
           "slot_role": "main", "meta": false, "injury_skip": false},
          {"exercise": null, "load": {}, "slot_role": "press", "meta": false, "injury_skip": false,
           "equipment_gap": true, "gap_reason": "EQUIPMENT_UNAVAILABLE",
           "blocked_by": {"cause": "equipment", "exercise": "strict_press", "needs": ["barbell", "rack"]}}
        ]}]}}],
     "validation": {"feasible": true, "errors": [], "warnings": [
        {"code": "MINIMAL_DAYS", "message": "Running at minimum 3 day(s)/week"}], "info": []},
     "compromises": ["Dropped mobility (tier 3) - needs 4+ training days"]}
    """

    func testHeldBackReadsTheServersBlocker() throws {
        let program = try decode(GeneratedProgram.self, programJSON)
        let session = try XCTUnwrap(program.weeks[0].schedule["Monday"]?.first)
        let names = HeldBack.Names(exercise: { $0 == "strict_press" ? "Strict Press" : nil })
        XCTAssertNil(HeldBack.emptySlotText(session.exercises[0]), "a filled slot holds nothing back")
        XCTAssertEqual(HeldBack.emptySlotText(session.exercises[1], names: names),
                       "Strict Press needs barbell, rack")
        XCTAssertEqual(HeldBack.heldBackSlots(session), 1)
        XCTAssertEqual(HeldBack.sessionNotes(session), ["In place of power (none written for your level)"])
        XCTAssertEqual(HeldBack.counts(program).slots, 1)
        XCTAssertEqual(HeldBack.counts(program).sessions, 1)
        XCTAssertEqual(program.weeks[0].testsSkippedReasons, ["equipment_gap"])
        XCTAssertEqual(HeldBack.scheduleFindings(program),
                       ["Running at minimum 3 day(s)/week", "Dropped mobility (tier 3) - needs 4+ training days"])
    }

    func testTheServersHeldBackCountWins() throws {
        var program = try decode(GeneratedProgram.self, programJSON)
        XCTAssertEqual(HeldBack.summary(program).slots, 1, "without the server's count, counted here")
        program.extra["held_back"] = .object(["slots": .int(7), "sessions": .int(3)])
        XCTAssertEqual(HeldBack.summary(program).slots, 7)
        XCTAssertEqual(HeldBack.summary(program).sessions, 3)
    }

    func testHeldBackAsksAboutTheDraftItself() throws {
        let draft = try decode(GeneratedProgram.self, """
        {"weeks": [{"week_number": 1, "week_in_phase": 3, "is_deload": false, "phase": "build",
                    "phase_id": "uphill_specific", "track_id": "uphill_main", "schedule": {}}]}
        """)
        var c = GenerateConstraints()
        c.trainingPhase = "base"
        let request = GenerateProgramRequest(philosophyId: "uphill_athlete", constraints: c, numWeeks: nil,
                                             startDate: "2026-10-20", eventDate: "2027-03-01")
        let impact = request.impactRequest(for: draft)
        XCTAssertNil(impact.eventDate, "the event date would size another program")
        XCTAssertEqual(impact.numWeeks, 1, "the draft's own length")
        XCTAssertEqual(impact.constraints.startPhase, "uphill_specific")
        XCTAssertEqual(impact.constraints.trackId, "uphill_main")
        XCTAssertEqual(impact.constraints.periodizationWeek, 3)
        XCTAssertNil(impact.constraints.trainingPhase)
    }

    func testBlockerWordsForEachCause() {
        let flag = HeldBack.Names(flag: { $0 == "knee_meniscus_post_op" ? "Knee (post-op)" : nil })
        XCTAssertEqual(HeldBack.blockerText(SlotBlocker(cause: "injury", exercise: "back_squat", needs: [],
                                                        flags: ["knee_meniscus_post_op"], requires: [],
                                                        level: nil, via: nil), names: flag),
                       "back squat is ruled out by Knee (post-op)")
        XCTAssertEqual(HeldBack.blockerText(SlotBlocker(cause: "level", exercise: "muscle_up", needs: [], flags: [],
                                                        requires: ["strict_pull_up"], level: "novice", via: nil)),
                       "muscle up is not unlocked at novice (needs strict pull up)")
    }

    func testAnInfeasibleDraftIsNeverAProgram() throws {
        let refused = try decode(GeneratedProgram.self, """
        {"weeks": [], "validation": {"feasible": false, "errors": [
          {"code": "TRAINING_CONTRACT_UNFULFILLED", "message": "novice_lp: equipment for back_squat is unavailable."}],
          "warnings": [], "info": []}}
        """)
        XCTAssertTrue(refused.isInfeasible)
        XCTAssertEqual(refused.validation?.errors.first?.code, "TRAINING_CONTRACT_UNFULFILLED")
        XCTAssertFalse(try decode(GeneratedProgram.self, programJSON).isInfeasible)
    }

    func testADraftSwapEditsOnlyTheDraft() throws {
        let program = try decode(GeneratedProgram.self, programJSON)
        let front = try decode(ProgramExerciseAssignment.self, """
        {"exercise": {"id": "front_squat", "name": "Front Squat"}, "load": {}, "meta": false, "injury_skip": false}
        """)
        let edited = ProgramEdits.replacingExercise(in: program, weekIndex: 0, day: "Monday", sessionIndex: 0,
                                                    exerciseIndex: 0, with: front)
        XCTAssertEqual(edited.weeks[0].schedule["Monday"]?[0].exercises[0].exercise?.id, "front_squat")
        XCTAssertEqual(program.weeks[0].schedule["Monday"]?[0].exercises[0].exercise?.id, "back_squat")
        XCTAssertEqual(edited.weeks[0].schedule["Monday"]?[0].substitutedFor, "power", "the session keeps its extras")
        let same = ProgramEdits.replacingExercise(in: program, weekIndex: 4, day: "Monday", sessionIndex: 0,
                                                  exerciseIndex: 0, with: front)
        XCTAssertEqual(same.weeks[0].schedule["Monday"]?[0].exercises[0].exercise?.id, "back_squat",
                       "an address that names nothing changes nothing")
    }

    func testConstraintChangeDecodes() throws {
        let unaffected = try decode(ConstraintChangeResult.self, """
        {"affected": false, "comparable": true, "sessions": {"total": 9, "changed": 0},
         "first_week_number": null, "changes": []}
        """)
        XCTAssertFalse(unaffected.affected)
        XCTAssertNil(unaffected.program)
        let affected = try decode(ConstraintChangeResult.self, """
        {"affected": true, "comparable": true, "sessions": {"total": 9, "changed": 2}, "first_week_number": 2,
         "changes": [{"week_index": 1, "week_number": 2, "day": "Monday", "session_index": 0, "change": "slots"}],
         "program": \(programJSON)}
        """)
        XCTAssertEqual(affected.firstWeekNumber, 2)
        XCTAssertEqual(affected.changes.map(\.id), ["1|Monday|0"])
        XCTAssertEqual(affected.program?.weeks.count, 1)
    }

    func testImpactDecodesAndFilesChangesByCause() throws {
        let impact = try decode(ConstraintImpact.self, """
        {"feasible": true, "lifts": {"equipment": "add barbell, rack"}, "lifted": ["equipment"],
         "reference": {"equipment": ["barbell", "rack", "open_space"], "training_level": "novice"},
         "sessions": {"total": 6, "changed": 2, "direct": 1},
         "restore": {"equipment": [{"id": "barbell", "changes": 4}]},
         "changes": [
          {"week_index": 0, "week_number": 1, "day": "Monday", "session_index": 0, "change": "slots",
           "reference": {"modality": "max_strength", "archetype": {"id": "a", "name": "Workout A"}},
           "actual": {"modality": "max_strength", "archetype": {"id": "a", "name": "Workout A"}},
           "knock_on": false,
           "slots": [{"index": 1, "role": "press", "kind": "emptied", "from": {"id": "strict_press", "name": "Strict Press"},
                      "to": null, "causes": ["equipment"], "why": [{"cause": "equipment", "text": "Strict Press needs barbell, rack"}],
                      "knock_on": false}]},
          {"week_index": 1, "week_number": 2, "day": "Monday", "session_index": 0, "change": "archetype",
           "reference": {"modality": "max_strength", "archetype": {"id": "b", "name": "Workout B"}},
           "actual": {"modality": "max_strength", "archetype": {"id": "a", "name": "Workout A"}},
           "causes": ["equipment"], "why": [], "knock_on": true}]}
        """)
        XCTAssertEqual(impact.restore.first?.id, "barbell")
        XCTAssertEqual(impact.sessionsTotal, 6, "the total the changes are drawn from")
        XCTAssertEqual(impact.direct.count, 1)
        XCTAssertEqual(impact.knockOn.count, 1)
        XCTAssertEqual(impact.direct[0].primaryCause, "equipment")
        XCTAssertEqual(impact.direct[0].line.detail, ["Strict Press left empty — Strict Press needs barbell, rack"])
        XCTAssertEqual(impact.knockOn[0].line.title, "Week 2 · Monday · Workout B → Workout A")

        let refused = try decode(ConstraintImpact.self, """
        {"feasible": false, "unblocked_by": [{"cause": "equipment", "text": "add barbell, plates, rack"}],
         "reference_generates": true, "lifted": ["equipment"], "lifts": {}}
        """)
        XCTAssertEqual(refused.unblockedBy.map(\.cause), ["equipment"])
    }

    func testOpenSpaceIsNeverAnEquipmentDifference() {
        var p = UserProfile.default
        p.trainingLevel = "novice"
        p.equipment = ["barbell", "rack"]
        let program: [String: JSONValue] = [
            "training_level": .string("novice"), "injury_flags": .array([]),
            "equipment": .array([.string("barbell"), .string("rack"), .string("open_space")]),
        ]
        XCTAssertEqual(ProgramConstraintsDiff.differences(program: program, profile: p), [])
    }

    func testTheBaselineIsTheProgramsOwnAndBothCarryTheContractsConfirmations() {
        var p = UserProfile.default
        p.trainingLevel = "novice"
        p.equipment = ["barbell", "rack", "rings"]
        p.injuryFlags = ["lumbar_disc"]
        let program: [String: JSONValue] = [
            "training_level": .string("novice"), "days_per_week": .int(3), "session_time_minutes": .int(75),
            "equipment": .array([.string("barbell"), .string("rack")]), "injury_flags": .array([]),
            "mastered_exercises": .array([.string("kb_swing")]), "kettlebell_count": .int(2),
        ]
        let after = ProgramConstraintsDiff.merged(program: program, profile: p, weekInPhase: 2, phase: "base",
                                                  phaseId: "lp", trackId: "novice")
        let before = ProgramConstraintsDiff.baseline(program: program, weekInPhase: 2, phase: "base",
                                                     phaseId: "lp", trackId: "novice")
        XCTAssertEqual(after.equipment, ["barbell", "rack", "rings"])
        XCTAssertEqual(after.injuryFlags, ["lumbar_disc"])
        XCTAssertEqual(before.equipment, ["barbell", "rack"])
        XCTAssertEqual(before.injuryFlags, [])
        for c in [before, after] {
            XCTAssertEqual(c.masteredExercises, ["kb_swing"], "a contract's confirmations ride along")
            XCTAssertEqual(c.kettlebellCount, 2)
            XCTAssertEqual(c.startPhase, "lp")
            XCTAssertEqual(c.periodizationWeek, 2)
        }
    }

    func testARequestCopiesWithOtherConstraintsAndNeverPersists() {
        var c = GenerateConstraints()
        c.equipment = ["kettlebell"]
        let request = GenerateProgramRequest(philosophyId: "starting_strength", constraints: c, numWeeks: 12,
                                             startDate: "2026-10-20", eventDate: nil)
        XCTAssertFalse(request.persist, "every generate is a draft")
        var more = c
        more.equipment.append("barbell")
        let next = request.with(constraints: more)
        XCTAssertEqual(next.constraints.equipment, ["kettlebell", "barbell"])
        XCTAssertEqual(next.numWeeks, 12)
        XCTAssertEqual(next.sourceIds, ["starting_strength"])
    }
}
