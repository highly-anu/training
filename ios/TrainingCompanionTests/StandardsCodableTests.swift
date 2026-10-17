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

    func testDeepLinkRenamedSection() {
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://profile?section=benchmarks")!),
                       .profile(.standards), "an old link lands on Standards")
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://profile?section=standards")!),
                       .profile(.standards))
    }
}
