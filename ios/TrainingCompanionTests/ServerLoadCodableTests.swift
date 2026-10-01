import XCTest
@testable import TrainingCompanion

/// The server shapes the Analytics tab and the exercise sheet read:
/// `/health/load/pmc`, `/health/load/weekly`, `/exercises/<id>/media` and the
/// catalog row. The phone used to compute PMC itself and disagreed with the
/// web by whatever the two TRIMP implementations differed; now both read the
/// same endpoint, so decoding it is the whole contract.
final class ServerLoadCodableTests: XCTestCase {

    func testPMCEntryDecodesAndLandsOnLocalMidnight() throws {
        let body = """
        [{"date": "2026-09-30", "ctl": 31.4, "atl": 45.0, "tsb": -12.5, "trimp": 88.0}]
        """
        let entries = try JSONDecoder().decode([ServerPMCEntry].self, from: Data(body.utf8))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.tsb, -12.5)

        let converted = try XCTUnwrap(entry.pmcEntry())
        XCTAssertEqual(converted.ctl, 31.4)
        XCTAssertEqual(converted.trimp, 88.0)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: converted.date)
        XCTAssertEqual([comps.year, comps.month, comps.day, comps.hour], [2026, 9, 30, 0],
                       "a plain date is local midnight, never shifted by the zone")
    }

    func testWeeklyLoadWeekStartIsTheISOMonday() throws {
        let body = """
        [{"week": "2026-W40", "trimp": 312, "sessions": 4}, {"week": "2026-W01", "trimp": 0, "sessions": 0}]
        """
        let weeks = try JSONDecoder().decode([ServerWeeklyLoadEntry].self, from: Data(body.utf8))
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].sessions, 4)

        let monday = try XCTUnwrap(weeks[0].weekStart)
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .weekday], from: monday)
        XCTAssertEqual([comps.year, comps.month, comps.day], [2026, 9, 28], "ISO week 40 of 2026 starts on 28 Sep")
        XCTAssertEqual(comps.weekday, 2, "Monday")

        // ISO week 1 of 2026 starts in 2025.
        let first = try XCTUnwrap(weeks[1].weekStart)
        let firstComps = cal.dateComponents([.year, .month, .day], from: first)
        XCTAssertEqual([firstComps.year, firstComps.month, firstComps.day], [2025, 12, 29])

        XCTAssertNil(ServerWeeklyLoadEntry(week: "garbage", trimp: 0, sessions: 0).weekStart)
    }

    func testExerciseMediaDecodesAPackageEntry() throws {
        let body = """
        {
            "animation": {"type": "gif", "external_id": "Box_Squat", "gif_alt": "Box Squat",
                          "gif_source": "free_exercise_db",
                          "gif_url": "https://example.com/Box_Squat/0.jpg"},
            "coaching_focus": "Sit back to the box.",
            "common_errors": ["Rocking forward off the box"],
            "cue_points": ["Actively sit back", "Pause completely"],
            "description": "A posterior-chain emphasis variant.",
            "muscle_diagram": {"front": [1, 2]},
            "muscles_primary": ["glutes", "hamstrings"],
            "muscles_secondary": []
        }
        """
        let media = try JSONDecoder().decode(ExerciseMedia.self, from: Data(body.utf8))
        XCTAssertFalse(media.isEmpty)
        XCTAssertEqual(media.gifURL?.absoluteString, "https://example.com/Box_Squat/0.jpg")
        XCTAssertEqual(media.cuePoints?.count, 2)
        XCTAssertEqual(media.commonErrors, ["Rocking forward off the box"])
        XCTAssertEqual(media.musclesPrimary, ["glutes", "hamstrings"])
        XCTAssertEqual(media.coachingFocus, "Sit back to the box.")
    }

    func testExerciseMediaWithoutADemoHasNoURLAndAnEmptyEntryIsEmpty() throws {
        let none = try JSONDecoder().decode(ExerciseMedia.self, from: Data("""
        {"animation": {"type": "none"}, "description": "Text only.", "cue_points": []}
        """.utf8))
        XCTAssertNil(none.gifURL, "type none means no demo even if a url were present")
        XCTAssertFalse(none.isEmpty)

        let empty = try JSONDecoder().decode(ExerciseMedia.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isEmpty, "the server answers {} for an exercise without media")
    }

    func testOneOddMediaFieldDoesNotBlankTheRest() throws {
        let media = try JSONDecoder().decode(ExerciseMedia.self, from: Data("""
        {"cue_points": "not a list", "description": "Still here."}
        """.utf8))
        XCTAssertNil(media.cuePoints)
        XCTAssertEqual(media.description, "Still here.")
    }

    func testCatalogRowDecodesPrerequisitesAndIgnoresMergedMedia() throws {
        // `/api/exercises` merges the media keys into each row; the model
        // reads what the sheet needs and ignores the rest.
        let rows = try JSONDecoder().decode([AppExercise].self, from: Data("""
        [{"id": "back_squat", "name": "Back Squat", "category": "barbell",
          "modality": ["max_strength"], "equipment": ["barbell", "rack", "plates"],
          "effort": "high", "movement_patterns": ["squat", "hip_hinge"],
          "requires": ["hip_hinge", "bracing_mechanics"], "unlocks": ["front_squat"],
          "animation": {"type": "gif"}, "cue_points": ["x"], "sources": ["Starting Strength"]},
         {"id": "run_easy", "name": "Easy Run", "requires": []}]
        """.utf8))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].requires, ["hip_hinge", "bracing_mechanics"])
        XCTAssertEqual(rows[0].unlocks, ["front_squat"])
        XCTAssertEqual(rows[0].equipment?.count, 3)
        XCTAssertEqual(rows[0].effort, "high")
        XCTAssertEqual(rows[1].requires, [])
        XCTAssertNil(rows[1].equipment)
    }
}
