import XCTest
@testable import TrainingCompanion

/// The briefing document as the server writes it (src/briefing.py), read
/// field by field.
final class BriefingModelTests: XCTestCase {
    private let json = """
    {"session": {"key": "4-Monday-0", "date": "2026-11-16"}, "spec": "declared",
     "headline": "Nerd Math Two-Hand Swing · 10 × 18 · on the minute",
     "items": [
      {"id": "module:swing", "entry": "density", "kind": "module", "title": "Nerd Math Two-Hand Swing",
       "exerciseIds": ["wk_kb_swing_two_hand"],
       "today": {"text": "10 × 18 · on the minute", "conditional": true,
                 "values": {"rounds": 10, "reps_per_round": 18, "interval": 60, "total_reps": 180},
                 "lines": [{"exerciseId": "wk_kb_swing_two_hand", "name": "Kettlebell Swing", "text": "10 × 18 · on the minute"}]},
       "history": [
        {"date": "2026-11-05", "dayText": "5 Nov", "text": "10 × 12 · on the minute · RPE 6", "status": "clean",
         "isDeload": false, "sessionKey": "2-Thursday-0", "values": {"total_reps": 120}},
        {"date": "2026-11-09", "dayText": "9 Nov", "text": "10 × 14 · on the minute · RPE 6", "status": "clean",
         "isDeload": false, "sessionKey": "3-Monday-0", "values": {"total_reps": 140}},
        {"date": "2026-11-12", "dayText": "Thursday", "text": "10 × 16 · on the minute", "status": "unconfirmed",
         "isDeload": false, "sessionKey": "3-Thursday-0", "values": {"total_reps": 160}},
        {"date": "2026-11-13", "status": "a status from the future"}],
       "last": null, "times": 6,
       "metric": {"id": "total_reps", "label": "Total reps", "unit": "reps"},
       "cycle": {"step": 7, "of": 32, "stage": 1, "stages": 4, "text": "Step 7 of 32 · stage 1 of 4"},
       "suggestion": {"kind": "confirm_pending", "text": "Thursday's session is not confirmed as clean."},
       "notes": "One step a clean session.", "a key from the future": 1},
      {"title": "an item without an id is left out"},
      {"id": "exercise:row", "title": "Row", "today": {"text": "2 km"}, "history": [], "times": 0,
       "standard": {"id": "row_2k", "name": "2 km row", "best": "7:40", "target": "7:30 for intermediate"}}],
     "pending": [{"sessionKey": "3-Thursday-0", "date": "2026-11-12", "text": "Thursday: done as written?"}]}
    """

    private func decoded() throws -> SessionBriefing {
        try JSONDecoder().decode(SessionBriefing.self, from: Data(json.utf8))
    }

    func testReadsTheDocument() throws {
        let b = try decoded()
        XCTAssertEqual(b.items.map(\.id), ["module:swing", "exercise:row"])
        let swing = b.items[0]
        XCTAssertEqual(swing.todayText, "10 × 18 · on the minute")
        XCTAssertTrue(swing.conditional)
        XCTAssertEqual(swing.cycleStep, 7)
        XCTAssertEqual(swing.cycleOf, 32)
        XCTAssertEqual(swing.cycleText, "Step 7 of 32 · stage 1 of 4")
        XCTAssertEqual(swing.suggestion?.kind, "confirm_pending")
        XCTAssertEqual(swing.history.map(\.status), [.clean, .clean, .unconfirmed, .logged])
        XCTAssertEqual(swing.times, 6)
        XCTAssertEqual(b.pending.map(\.sessionKey), ["3-Thursday-0"])
        XCTAssertEqual(b.items[1].standard?.best, "7:40")
        XCTAssertTrue(b.saysSomething)
    }

    func testTheSeriesIsTheMetricAcrossOccurrencesThenToday() throws {
        let swing = try decoded().items[0]
        XCTAssertEqual(swing.series.map(\.value), [120, 140, 160, 180])
        XCTAssertEqual(swing.series.map(\.planned), [false, false, false, true])
        XCTAssertEqual(SessionBriefing.seriesSummary(swing), "3 earlier sessions, from 120 to 160 reps; today 180.")
    }

    func testFewerThanThreePointsIsNoSeries() throws {
        let row = try decoded().items[1]
        XCTAssertTrue(row.series.isEmpty)
        XCTAssertNil(SessionBriefing.seriesSummary(row))
    }

    func testAnItemOfSeveralExercisesIsReadExerciseByExercise() throws {
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [{"id": "module:clean_press", "title": "Clean and Press",
          "today": {"text": "10 × 1", "values": {"total_reps": 10}},
          "metric": {"id": "total_reps", "label": "Total reps", "unit": "reps"}, "times": 3,
          "history": [{"date": "2026-11-01", "status": "clean", "values": {"total_reps": 15}},
                      {"date": "2026-11-04", "status": "clean", "values": {"total_reps": 20}},
                      {"date": "2026-11-08", "status": "clean", "values": {"total_reps": 25}}],
          "exercises": [
            {"exerciseId": "clean", "name": "Clean", "today": {"text": "10 × 1 · on the minute"},
             "history": [{"date": "2026-11-08", "dayText": "8 Nov", "text": "5 × 5 · 20 kg · RPE 6", "status": "clean"}]},
            {"exerciseId": "press", "name": "Press", "today": {"text": "10 × 1 · on the minute"},
             "history": [{"date": "2026-11-08", "dayText": "8 Nov", "text": "5 × 5 · 16 kg · RPE 6", "status": "clean"}]},
            {"name": "an exercise without an id is left out"}]}]}
        """.utf8))
        let item = b.items[0]
        XCTAssertEqual(item.exercises.map(\.name), ["Clean", "Press"])
        XCTAssertEqual(item.exercises[1].history.first?.text, "5 × 5 · 16 kg · RPE 6")
        XCTAssertEqual(item.exercises[0].todayText, "10 × 1 · on the minute")
        XCTAssertTrue(item.series.isEmpty)   // two runs are not one chart
    }

    func testARunThatNeverChangesIsNoSeries() throws {
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [{"id": "module:getup", "title": "Get-up", "today": {"text": "10 × 1", "values": {"total_reps": 10}},
          "metric": {"id": "total_reps", "label": "Total reps", "unit": "reps"}, "times": 2,
          "history": [{"date": "2026-11-09", "status": "clean", "values": {"total_reps": 10}},
                      {"date": "2026-11-12", "status": "clean", "values": {"total_reps": 10}}]}]}
        """.utf8))
        XCTAssertTrue(b.items[0].series.isEmpty)
    }

    func testAPrescriptionAloneSaysNothing() throws {
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [{"id": "exercise:x", "title": "X", "today": {"text": "3 × 5"}, "history": [], "times": 0}]}
        """.utf8))
        XCTAssertFalse(b.saysSomething)
        XCTAssertTrue(b.pending.isEmpty)
    }
}
