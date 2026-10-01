import XCTest
@testable import TrainingCompanion

/// The profile against the program it was built for, and the splice a
/// partial regenerate makes.
final class ProgramConstraintsDiffTests: XCTestCase {

    private let programConstraints: [String: JSONValue] = [
        "training_level": .string("intermediate"),
        "equipment": .array([.string("barbell"), .string("rack"), .string("plates")]),
        "days_per_week": .int(3),
        "session_time_minutes": .int(75),
        "injury_flags": .array([]),
        "training_phase": .string("base"),
    ]

    private func profile(level: String = "intermediate", equipment: [String] = ["plates", "rack", "barbell"],
                         injuries: [String] = [], schedule: WeeklySchedule? = nil) -> UserProfile {
        var p = UserProfile.default
        p.trainingLevel = level
        p.equipment = equipment
        p.injuryFlags = injuries
        p.weeklySchedule = schedule
        return p
    }

    private let fourDays: WeeklySchedule = [
        "Monday": DaySchedule(session1: .long, session2: .rest, session3: .rest, session4: .rest),
        "Tuesday": DaySchedule(session1: .rest, session2: .rest, session3: .rest, session4: .rest),
        "Wednesday": DaySchedule(session1: .short, session2: .rest, session3: .rest, session4: .rest),
        "Thursday": DaySchedule(session1: .rest, session2: .mobility, session3: .rest, session4: .rest),
        "Friday": DaySchedule(session1: .long, session2: .rest, session3: .rest, session4: .rest),
        "Saturday": DaySchedule(session1: .rest, session2: .rest, session3: .rest, session4: .rest),
        "Sunday": DaySchedule(session1: .rest, session2: .rest, session3: .rest, session4: .rest),
    ]

    func testNoDifferencesWhenTheProfileMatches() {
        XCTAssertEqual(ProgramConstraintsDiff.differences(program: programConstraints, profile: profile()), [])
        XCTAssertEqual(ProgramConstraintsDiff.differences(program: [:], profile: profile(level: "advanced")), [],
                       "a program without constraints offers nothing")
    }

    func testEachFieldThatMovedOnIsNamed() {
        let diffs = ProgramConstraintsDiff.differences(
            program: programConstraints,
            profile: profile(level: "advanced", equipment: ["barbell", "rack", "kettlebell"],
                             injuries: ["lumbar_disc"], schedule: fourDays))
        XCTAssertEqual(diffs.map(\.field), ["training_level", "equipment", "days_per_week", "injury_flags"])
        XCTAssertEqual(diffs[0].program, "intermediate"); XCTAssertEqual(diffs[0].profile, "advanced")
        XCTAssertEqual(diffs[1].profile, "1 added, 1 removed")
        XCTAssertEqual(diffs[2].program, "3"); XCTAssertEqual(diffs[2].profile, "4")
        XCTAssertEqual(diffs[3].profile, "1 added")
    }

    func testEmptyEquipmentAndMissingScheduleAreNotDifferences() {
        XCTAssertEqual(ProgramConstraintsDiff.differences(program: programConstraints,
                                                          profile: profile(equipment: [])), [])
        XCTAssertNil(ProgramConstraintsDiff.daysPerWeek(nil))
        XCTAssertEqual(ProgramConstraintsDiff.daysPerWeek(fourDays), 4)
    }

    func testMergedConstraintsContinueThePhase() throws {
        let merged = ProgramConstraintsDiff.merged(
            program: programConstraints,
            profile: profile(level: "advanced", equipment: ["kettlebell"], injuries: ["knee_patellar"], schedule: fourDays),
            weekInPhase: 2, phase: "build")
        XCTAssertEqual(merged.trainingLevel, "advanced")
        XCTAssertEqual(merged.equipment, ["kettlebell"])
        XCTAssertEqual(merged.injuryFlags, ["knee_patellar"])
        XCTAssertEqual(merged.daysPerWeek, 4)
        XCTAssertEqual(merged.sessionTimeMinutes, 75, "the program's minutes are kept")
        XCTAssertEqual(merged.phase, "build")
        XCTAssertEqual(merged.periodizationWeek, 2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as? [String: Any])
        XCTAssertEqual(json["periodization_week"] as? Int, 2)
        XCTAssertEqual(json["training_phase"] as? String, "build")
    }

    func testBlendRequestEncodesIdsAndWeights() throws {
        let request = GenerateProgramRequest(philosophyIds: ["a", "b"], philosophyWeights: ["a": 0.6, "b": 0.4],
                                             constraints: GenerateConstraints(), numWeeks: 3, weekInProgram: 2,
                                             startDate: nil, eventDate: nil, persist: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["philosophy_ids"] as? [String], ["a", "b"])
        XCTAssertEqual((json["philosophy_weights"] as? [String: Double])?["a"], 0.6)
        XCTAssertNil(json["philosophy_id"])
        XCTAssertEqual(json["num_weeks"] as? Int, 3)
        XCTAssertEqual(json["week_in_program"] as? Int, 2, "the tail continues the numbering")
        XCTAssertEqual(json["persist"] as? Bool, false)
        let single = GenerateProgramRequest(philosophyId: "starting_strength", constraints: GenerateConstraints(),
                                            numWeeks: nil, startDate: nil, eventDate: nil)
        let sj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(single)) as? [String: Any])
        XCTAssertEqual(sj["philosophy_id"] as? String, "starting_strength")
        XCTAssertNil(sj["philosophy_ids"])
        XCTAssertNil(sj["week_in_program"], "a full generate numbers from 1")
        XCTAssertEqual(sj["persist"] as? Bool, true)
    }

    func testSpliceKeepsTheHeadAndTakesTheNewDocument() throws {
        func week(_ n: Int) -> ProgramWeek {
            ProgramWeek(weekNumber: n, weekInPhase: n, isDeload: false, phase: "base", schedule: [:])
        }
        let current = GeneratedProgram(weeks: [week(1), week(2), week(3), week(4)],
                                       extra: ["goal": .string("old"), "constraints": .object(["days_per_week": .int(3)]),
                                               "volume_summary": .array([]), "custom": .string("kept")])
        let generated = GeneratedProgram(weeks: [week(3), week(4)],
                                         extra: ["goal": .string("new"), "constraints": .object(["days_per_week": .int(4)]),
                                                 "validation": .object(["valid": .bool(true)])])
        let spliced = Regeneration.splice(current: current, from: 2, generated: generated)
        XCTAssertEqual(spliced.weeks.map(\.weekNumber), [1, 2, 3, 4])
        XCTAssertEqual(spliced.weeks.count, 4)
        XCTAssertEqual(spliced.extra["goal"], .string("new"))
        XCTAssertEqual(spliced.extra["constraints"], .object(["days_per_week": .int(4)]))
        XCTAssertEqual(spliced.extra["validation"], .object(["valid": .bool(true)]))
        XCTAssertEqual(spliced.extra["custom"], .string("kept"), "keys the tail does not carry stay")
        XCTAssertNil(spliced.extra["volume_summary"], "recomputed by the server on save")
        XCTAssertEqual(Regeneration.splice(current: current, from: 9, generated: generated).weeks.count, 6,
                       "a start past the end keeps everything and appends")
    }
}
