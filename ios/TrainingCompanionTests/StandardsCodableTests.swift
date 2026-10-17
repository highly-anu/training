import XCTest
@testable import TrainingCompanion

/// `GET /api/standards` and `GET /api/standards/results`, as the server sends
/// them. Profile ▸ Benchmarks once showed nothing at all: `AppBenchmark`
/// required `higher_is_better`, a key the server never sent, so every row
/// failed and `try?` turned the failure into an empty list. These fixtures are
/// the server's real rows (`benchmarks_data.to_client`).
final class StandardsCodableTests: XCTestCase {

    private let catalog = """
    [{"id": "wod_fran_minutes", "name": "Fran (time in minutes)", "category": "benchmark_wod",
      "categoryName": "Benchmark workouts", "categoryOrder": 4, "unit": " min",
      "standards": {"entry": 12.0, "intermediate": 8.0, "advanced": 5.0, "elite": 3.5}, "lower_is_better": true,
      "standardsText": {"entry": "12:00", "intermediate": "8:00", "advanced": "5:00", "elite": "3:30"},
      "inputHint": "m:ss", "domain": "mixed_modal_conditioning", "metricType": "time_minutes",
      "sources": ["crossfit"], "goalRelevance": ["crossfit_performance"],
      "femaleStandards": {"entry": 13.0, "intermediate": 9.0, "advanced": 6.0, "elite": 4.0},
      "testProtocol": "Record total time."},
     {"id": "cell_work_capacity_thruster", "name": "Thruster", "category": "cell", "categoryName": "The Cell",
      "categoryOrder": 6, "unit": "×BW", "standards": {"entry": 0.4, "intermediate": 0.5, "advanced": 0.6, "elite": 0.7},
      "lower_is_better": false, "standardsText": {"entry": "0.4×BW", "intermediate": "0.5×BW", "advanced": "0.6×BW", "elite": "0.7×BW"},
      "inputHint": "×BW", "domain": "strength_endurance", "metricType": "bw_ratio", "sources": ["the_cell"],
      "goalRelevance": [], "femaleStandards": {}, "notes": "Load as ×BW for 21 reps (30 reps at elite)."},
     {"id": "an_old_row", "name": "From a server before the text", "category": "strength",
      "unit": "×BW", "standards": {"entry": 1, "intermediate": 1.5, "advanced": 2, "elite": 2.5}},
     {"name": "no id — dropped, not the list"}]
    """.data(using: .utf8)!

    func testTheRealCatalogDecodesRowByRow() throws {
        let rows = try JSONDecoder().decode([Lossy<AppBenchmark>].self, from: catalog).compactMap(\.value)
        XCTAssertEqual(rows.map(\.id), ["wod_fran_minutes", "cell_work_capacity_thruster", "an_old_row"],
                       "a malformed row is dropped, never the list")
        let fran = rows[0]
        XCTAssertTrue(fran.lowerIsBetter)
        XCTAssertEqual(fran.groupName, "Benchmark workouts")
        XCTAssertEqual(fran.thresholdTexts["advanced"], "5:00", "thresholds print as the server says")
        XCTAssertEqual(fran.inputHint, "m:ss")
        XCTAssertEqual(rows[1].notes, "Load as ×BW for 21 reps (30 reps at elite).")
        XCTAssertFalse(rows[2].lowerIsBetter)
        XCTAssertEqual(rows[2].thresholdTexts["intermediate"], "1.5×BW", "number + unit without standardsText")
        XCTAssertEqual(rows[2].groupName, "Strength")
    }

    func testResultsCarryTheServersLevels() throws {
        let json = """
        {"sex": "male",
         "standards": {
           "wod_fran_minutes": {
             "current": {"value": 5.5, "valueText": "5:30", "date": "2026-10-01", "level": "intermediate",
                         "levelIndex": 2, "next": "advanced", "nextText": "5:00", "gap": 0.5, "gapText": "0:30"},
             "best": {"value": 4.97, "valueText": "4:58", "date": "2026-09-01", "level": "advanced",
                      "levelIndex": 3, "next": "elite", "nextText": "3:30", "gap": 1.47, "gapText": "1:28"},
             "count": 2,
             "entries": [{"id": 2, "value": 4.97, "date": "2026-09-01", "valueText": "4:58", "level": "advanced", "levelIndex": 3},
                         {"id": 3, "value": 5.5, "date": "2026-10-01", "valueText": "5:30", "level": "intermediate", "levelIndex": 2}]},
           "pull_up_reps": {
             "current": {"value": 0, "valueText": "0 reps", "date": "2026-10-01", "level": null, "levelIndex": 0,
                         "next": "entry", "nextText": "1 rep", "gap": 1, "gapText": "1 rep"},
             "best": {"value": 0, "valueText": "0 reps", "date": "2026-10-01", "level": null, "levelIndex": 0,
                      "next": "entry", "nextText": "1 rep", "gap": 1, "gapText": "1 rep"},
             "count": 1, "entries": []},
           "broken": {"current": "nope"}
         },
         "bodyweight": {"value": 81.5, "valueText": "81.5 kg", "date": "2026-10-01"}}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(StandardResults.self, from: json)
        XCTAssertEqual(Set(r.standards.keys), ["wod_fran_minutes", "pull_up_reps"], "a bad standard is dropped alone")
        let fran = try XCTUnwrap(r.standards["wod_fran_minutes"])
        XCTAssertEqual(fran.current.valueText, "5:30")
        XCTAssertEqual(fran.best.level, "advanced", "best and current are both the server's")
        XCTAssertEqual(fran.entries.map(\.entryId), [2, 3])
        XCTAssertEqual(StandardLevel.name(r.standards["pull_up_reps"]?.current.level), "Below entry",
                       "the phone has a below-entry level now")
        XCTAssertEqual(r.bodyweight?.valueText, "81.5 kg")
    }

    func testEntriesCarryTheirDaySourceAndBlock() throws {
        let json = """
        {"sex": "male",
         "standards": {"back_squat_bw_ratio": {
           "current": {"value": 1.787, "valueText": "1.79×BW", "date": "2026-10-14", "level": "intermediate",
                       "levelIndex": 2, "next": "advanced", "nextText": "2×BW", "gap": 0.213, "gapText": "0.21×BW"},
           "best": {"value": 1.787, "valueText": "1.79×BW", "date": "2026-10-14", "level": "intermediate",
                    "levelIndex": 2, "next": "advanced", "nextText": "2×BW", "gap": 0.213, "gapText": "0.21×BW"},
           "count": 1,
           "entries": [{"id": 11, "value": 1.787, "date": "2026-10-14", "valueText": "1.79×BW", "level": "intermediate",
                        "levelIndex": 2, "source": "manual", "note": "belt", "inputText": "130 kg × 3 at 80 kg · est.",
                        "sessionUid": null, "workoutId": null, "block": {"id": 7, "name": "Mark Wildman Kettlebell"}}]}},
         "blocks": [{"id": 3, "name": "Marcus Filly", "from": "2026-10-05", "to": "2026-10-10"},
                    {"id": 7, "name": "Mark Wildman Kettlebell", "from": "2026-10-11", "to": null}],
         "bodyweight": {"value": 80, "valueText": "80 kg", "date": "2026-09-07",
                        "entries": [{"id": 2, "value": 80, "date": "2026-09-07", "valueText": "80 kg", "level": null,
                                     "levelIndex": 0, "source": "manual", "note": null, "inputText": null, "block": null}]}}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(StandardResults.self, from: json)
        let e = try XCTUnwrap(r.standards["back_squat_bw_ratio"]?.entries.first)
        XCTAssertEqual(e.entryId, 11)
        XCTAssertEqual(e.sourceText, "Typed in")
        XCTAssertEqual(e.block?.name, "Mark Wildman Kettlebell")
        XCTAssertEqual(e.inputText, "130 kg × 3 at 80 kg · est.")
        XCTAssertEqual(r.blocks.map(\.id), [3, 7])
        XCTAssertNil(r.blocks[1].to, "the current block runs to today")
        XCTAssertEqual(r.bodyweight?.entries.map(\.entryId), [2], "bodyweight entries, so one can be corrected")
        XCTAssertEqual(StandardLevel.isoDay(try XCTUnwrap(StandardLevel.date("2026-10-14"))), "2026-10-14",
                       "a server day survives the round trip through a local date")
    }

    func testResultInputSendsOnlyWhatIsSet() throws {
        let note = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StandardResultInput(note: "belt"))) as? [String: Any]
        XCTAssertEqual(note?.keys.sorted(), ["note"], "an edit of the note sends nothing else")
        let load = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            StandardResultInput(kg: 140, reps: 2, loggedOn: "2026-10-01"))) as? [String: Any]
        XCTAssertEqual(load?.keys.sorted(), ["kg", "loggedOn", "reps"])
    }

    func testRelevanceAndTheBlockReadFromTheServer() throws {
        let results = try JSONDecoder().decode(StandardResults.self, from: Data("""
        {"sex": "male", "standards": {}, "bodyweight": null, "blocks": [],
         "programStandards": [{"id": "ssst_reps", "why": ["declared"]}, {"id": "kb_test", "why": ["tested"]}, {"x": 1}]}
        """.utf8))
        XCTAssertEqual(results.programStandards, ["ssst_reps", "kb_test"], "Profile's This program, in order")

        let doc = try JSONDecoder().decode(ProgramAnalytics.self, from: Data("""
        {"benchmarks": {"sex": "male", "blockStart": "2026-10-05", "bodyweightKg": null, "benchmarks": [
          {"benchmarkId": "ssst_reps", "name": "SSST", "unit": " reps", "why": ["declared"], "primary": true,
           "standards": {"entry": 100, "intermediate": 150, "advanced": 200, "elite": 250}, "value": 162,
           "valueText": "162 reps", "level": "intermediate", "levelIndex": 2, "levelChange": 1,
           "atBlockStart": {"value": 140, "valueText": "140 reps", "date": "2026-09-20", "level": "entry", "levelIndex": 1},
           "blockHistory": [{"date": "2026-09-20", "value": 140, "valueText": "140 reps", "level": "entry"},
                            {"date": "2026-10-15", "value": 162, "valueText": "162 reps", "level": "intermediate"}]}]}}
        """.utf8))
        let row = try XCTUnwrap(doc.benchmarks?.rows.first)
        XCTAssertEqual(row.levelChange, 1)
        XCTAssertEqual(row.atBlockStart?.valueText, "140 reps")
        XCTAssertEqual(row.blockHistory.map(\.valueText), ["140 reps", "162 reps"])
        XCTAssertEqual(StandardLevel.blockChange(levelChange: 1, hasStart: true, points: 2), "+1 level this block")
        XCTAssertEqual(StandardLevel.blockChange(levelChange: -2, hasStart: true, points: 3), "−2 levels this block")
        XCTAssertEqual(StandardLevel.blockChange(levelChange: nil, hasStart: false, points: 1), "first result this block")
        XCTAssertEqual(StandardLevel.blockChange(levelChange: nil, hasStart: true, points: 1), "not retested this block")
        XCTAssertNil(StandardLevel.blockChange(levelChange: nil, hasStart: false, points: 0))

        let dev = try JSONDecoder().decode(DevelopmentAnalytics.self, from: Data("""
        {"status": "ok", "window": {"from": "2025-10-01", "to": "2026-10-17"}, "blocks": [], "lifts": [],
         "currencies": [], "load": {"weekly": [], "pmc": []},
         "benchmarks": [{"benchmarkId": "wod_fran_minutes", "name": "Fran", "unit": " min", "domain": "mixed_modal_conditioning",
                         "lowerIsBetter": true, "standards": {"entry": 12, "elite": 3.5},
                         "standardsText": {"entry": "12:00", "elite": "3:30"}, "inCurrentProgram": true,
                         "history": [{"date": "2026-10-12", "value": 4.97, "valueText": "4:58", "level": "advanced",
                                      "levelIndex": 3, "blockId": 7}],
                         "latestLevel": "advanced", "latestLevelIndex": 3, "levelsGained": 0}]}
        """.utf8))
        let fran = try XCTUnwrap(dev.benchmarks.first)
        XCTAssertTrue(fran.inCurrentProgram)
        XCTAssertEqual(fran.history.first?.blockId, 7)
        XCTAssertEqual(StandardChartLevel.from(standards: fran.standards, texts: fran.standardsText).map(\.text),
                       ["12:00", "3:30"], "the level lines in order, with the server's text")
    }

    func testATestSessionSaysWhatItMeasures() throws {
        let json = Data("""
        {"modality": "strength_endurance", "is_deload": false,
         "archetype": {"id": "kb_pentathlon_test", "name": "KB Pentathlon (IKMF) — Test", "duration_estimate_minutes": 60},
         "test": {"archetype": "kb_pentathlon_test", "standards": ["kb_pentathlon_clean_reps", "kb_pentathlon_jerk_reps"],
                  "phase_id": "competition", "week_in_phase": 2, "in_place_of": "strength_endurance",
                  "instead_of": {"archetype": "kb_pentathlon_training", "name": "KB Pentathlon Timed Sets", "minutes": 50}},
         "exercises": [{"exercise": {"id": "wk_kb_clean_single", "name": "Clean"}, "load": {"duration_minutes": 6, "test": true},
                        "slot_role": "clean", "slot_type": "time_domain", "meta": false, "injury_skip": false,
                        "standard": {"id": "kb_pentathlon_clean_reps", "result": "reps"}}]}
        """.utf8)
        let session = try JSONDecoder().decode(ProgramSession.self, from: json)
        let test = try XCTUnwrap(session.testInfo)
        XCTAssertEqual(test.standards, ["kb_pentathlon_clean_reps", "kb_pentathlon_jerk_reps"])
        XCTAssertEqual(test.insteadOf, "KB Pentathlon Timed Sets")
        XCTAssertEqual(session.exercises.first?.standardId, "kb_pentathlon_clean_reps")
        let again = try JSONDecoder().decode(ProgramSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(again.testInfo?.standards.count, 2, "the test round-trips through a save")
        XCTAssertEqual(again.exercises.first?.standardId, "kb_pentathlon_clean_reps")
    }

    /// `GET /standards/suggestions` and a session-log save's `standards`, as
    /// src/standard_results.describe writes them; one bad row is dropped, not
    /// the list.
    func testSuggestionsDecodeAndFindTheirSession() throws {
        let json = """
        {"suggestions": [
          {"id": 4, "benchmarkId": "row_2km_minutes", "name": "2km Row (time in minutes)",
           "domain": "anaerobic_intervals", "value": 7.5333, "valueText": "7:32", "level": "intermediate",
           "levelIndex": 2, "next": "advanced", "nextText": "7:00", "inputText": null,
           "current": {"value": 7.75, "valueText": "7:45", "date": "2026-09-01", "level": "intermediate",
                       "levelIndex": 2, "next": "advanced", "nextText": "7:00", "gapText": "0:45"},
           "bestText": "7:45", "isBest": true, "origin": "test_slot", "status": "pending",
           "loggedOn": "2026-10-17", "sessionUid": "v:w0-Friday-0", "sessionKey": "1-Friday",
           "sessionName": "2 km Row — Test"},
          {"id": "not a number"}
        ]}
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode(StandardSuggestionList.self, from: json).suggestions
        XCTAssertEqual(list.count, 1)
        let s = try XCTUnwrap(list.first)
        XCTAssertEqual(s.valueText, "7:32")
        XCTAssertEqual(s.current?.valueText, "7:45")
        XCTAssertTrue(s.isBest)
        XCTAssertTrue(s.isFromTest(sessionKey: "1-Friday-0"), "the phone's key finds the web's day-level log")
        XCTAssertFalse(s.isFromTest(sessionKey: "2-Friday-0"))

        let saved = """
        {"saved": "1-Friday-0", "standards": {"pending": [{"id": 4, "benchmarkId": "row_2km_minutes",
          "value": 7.5333, "valueText": "7:32"}], "confirmed": [], "skipped": [], "problems": [], "error": null}}
        """.data(using: .utf8)!
        struct Saved: Decodable { let standards: SessionLogStandards? }
        let st = try XCTUnwrap(try JSONDecoder().decode(Saved.self, from: saved).standards)
        XCTAssertEqual(st.pending.map(\.benchmarkId), ["row_2km_minutes"])
        XCTAssertNil(st.error)
    }

    /// A run standard says which distance an imported run's fastest window
    /// reads as; the detail sheet says so (and no other standard does).
    func testARunStandardCarriesItsBestEffort() throws {
        let json = """
        [{"id": "run_1mile_minutes", "name": "1-Mile Run (time in minutes)", "category": "conditioning",
          "lower_is_better": true, "standardsText": {"entry": "8:00"}, "bestEffort": {"km": 1.609344, "label": "1 mile"}},
         {"id": "row_2km_minutes", "name": "2km Row", "category": "conditioning", "lower_is_better": true}]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([AppBenchmark].self, from: json)
        XCTAssertEqual(rows[0].bestEffort?.label, "1 mile")
        XCTAssertEqual(rows[0].bestEffort?.km ?? 0, 1.609344, accuracy: 1e-9)
        XCTAssertNil(rows[1].bestEffort)
    }

    func testDeepLinkRenamedSection() {
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://profile?section=benchmarks")!),
                       .profile(.standards), "an old link lands on Standards")
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://profile?section=standards")!),
                       .profile(.standards))
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://profile?section=standards&standard=wod_fran_minutes")!),
                       .standard("wod_fran_minutes"), "a standard's sheet")
    }
}
