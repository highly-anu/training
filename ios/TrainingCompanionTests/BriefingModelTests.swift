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

    // MARK: - Rows (§6.61): one exercise, one strip

    private let run = """
    {"items": [
      {"id": "module:swing", "title": "Nerd Math Two-Hand Swing", "times": 4,
       "today": {"text": "10 × 18 · on the minute", "values": {"total_reps": 180}},
       "metric": {"id": "total_reps", "label": "Total reps", "unit": "reps"},
       "cycle": {"step": 7, "of": 32, "text": "Step 7 of 32"},
       "suggestion": {"kind": "next_step", "text": "2 more a round than Thursday."},
       "history": [{"date": "2026-11-12", "dayText": "Thursday", "text": "10 × 16", "status": "clean", "values": {"total_reps": 160}}],
       "exercises": [{"exerciseId": "swing", "name": "Kettlebell Swing", "times": 4, "timesText": "4 sessions",
         "today": {"text": "10 × 18 · on the minute", "value": 180},
         "metric": {"id": "total_reps", "label": "Total reps", "unit": "reps"},
         "history": [{"date": "2026-11-12", "dayText": "Thursday", "text": "10 × 16", "status": "clean"}],
         "run": [
          {"date": "2026-11-02", "dayText": "2 Nov", "text": "10 × 10", "status": "clean", "value": 100},
          {"date": "2026-11-05", "dayText": "5 Nov", "text": "10 × 12", "status": "missed", "value": 120, "isDeload": true},
          {"date": "2026-11-09", "dayText": "9 Nov", "text": "10 × 14", "status": "unconfirmed", "sessionKey": "3-Monday-0"},
          {"date": "2026-11-12", "dayText": "Thursday", "text": "10 × 16", "status": "clean", "value": 160}]}]},
      {"id": "module:clean_press", "title": "Clean and Press", "times": 1,
       "today": {"text": "5 × 3"}, "suggestion": {"kind": "next_step", "text": "1 more a round than Saturday."},
       "exercises": [
        {"exerciseId": "clean", "name": "Clean", "today": {"text": "5 × 3 each side"}, "times": 1, "timesText": "1 session",
         "run": [{"date": "2026-11-07", "dayText": "7 Nov", "text": "5 × 2 each side", "status": "clean", "value": 10}]},
        {"exerciseId": "press", "name": "Press", "today": {"text": "5 × 3 each side"}, "times": 0, "timesText": "First time", "run": []}]},
      {"id": "exercise:row", "title": "Row", "today": {"text": "2 km"}, "times": 0,
       "exercises": [{"exerciseId": "row", "name": "Rowing", "today": {"text": "2 km"}, "run": [], "times": 0, "timesText": "First time"}]}]}
    """

    private func rows() throws -> [SessionBriefing.Row] {
        try JSONDecoder().decode(SessionBriefing.self, from: Data(run.utf8)).rows
    }

    func testARowIsOneExerciseWithItsWholeRun() throws {
        let rows = try rows()
        XCTAssertEqual(rows.map(\.name), ["Nerd Math Two-Hand Swing", "Clean", "Press", "Row"])
        let swing = rows[0]
        // The run is every time, not the listed history's one.
        XCTAssertEqual(swing.run.count, 4)
        XCTAssertEqual(swing.marks.map(\.value), [100, 120, nil, 160])
        XCTAssertEqual(swing.marks.map(\.status), [.clean, .missed, .unconfirmed, .clean])
        XCTAssertEqual(swing.marks.map(\.isDeload), [false, true, false, false])
        XCTAssertEqual(swing.todayValue, 180)
        XCTAssertEqual(swing.caption, "Step 7 of 32")           // the short cycle label; the count is the strip
        XCTAssertEqual(swing.accessibilityLabel,
                       "Nerd Math Two-Hand Swing. Today: 10 × 18 · on the minute. Step 7 of 32. 4 earlier sessions. Last, Thursday: 10 × 16, clean. 2 more a round than Thursday.")
    }

    func testAnItemOfSeveralExercisesIsHeadedOnce() throws {
        let rows = try rows()
        XCTAssertEqual(rows.map(\.header), [nil, "Clean and Press", nil, nil])
        // The item's one suggestion closes its last row.
        XCTAssertEqual(rows.map { $0.suggestion?.text },
                       ["2 more a round than Thursday.", nil, "1 more a round than Saturday.", nil])
        XCTAssertEqual(rows.map(\.caption), ["Step 7 of 32", "1 session", "First time", "First time"])
        XCTAssertEqual(Set(rows.map(\.id)).count, 4)
    }

    func testASessionToConfirmIsSaidOnce() throws {
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [
          {"id": "module:a", "title": "A", "today": {"text": "1"}, "suggestion": {"kind": "confirm_pending", "text": "Confirm Thursday first."}},
          {"id": "module:b", "title": "B", "today": {"text": "2"}, "suggestion": {"kind": "confirm_pending", "text": "Confirm Thursday first."}},
          {"id": "module:c", "title": "C", "today": {"text": "3"}, "suggestion": {"kind": "next_step", "text": "1 more."}},
          {"id": "module:d", "title": "D", "today": {"text": "4"}, "suggestion": {"kind": "next_step", "text": "1 more."}}]}
        """.utf8))
        // Only the session to confirm: two lifts with the same step each say theirs.
        XCTAssertEqual(b.rows.map { $0.suggestion?.text }, ["Confirm Thursday first.", nil, "1 more.", "1 more."])
    }

    func testAStripShowsTheNewestThatFit() throws {
        let swing = try rows()[0]
        XCTAssertEqual(swing.marks(fitting: 2).map(\.value), [nil, 160])
        XCTAssertEqual(swing.marks(fitting: 40).count, 4)
        XCTAssertTrue(swing.marks(fitting: 0).isEmpty)
    }

    func testAMarksHeightIsItsPlaceInTheRun() {
        let values: [Double] = [100, 120, 160, 180]
        XCTAssertEqual(SessionBriefing.markHeight(100, in: values), 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(SessionBriefing.markHeight(180, in: values), 1, accuracy: 0.001)
        XCTAssertEqual(SessionBriefing.markHeight(140, in: values), 2.0 / 3, accuracy: 0.001)
        // No number, or a run that never moves: every mark the same.
        XCTAssertEqual(SessionBriefing.markHeight(nil, in: values), 0.6)
        XCTAssertEqual(SessionBriefing.markHeight(10, in: [10, 10]), 0.6)
        XCTAssertEqual(SessionBriefing.markHeight(nil, in: []), 0.6)
    }

    func testTheSheetsChartIsTheRunThenToday() throws {
        let rows = try rows()
        XCTAssertEqual(rows[0].series.map(\.value), [100, 120, 160, 180])
        XCTAssertEqual(rows[0].series.map(\.planned), [false, false, false, true])
        XCTAssertEqual(rows[0].seriesSummary, "3 earlier sessions, from 100 to 160 reps; today 180.")
        // Fewer than three points is a list, not a chart.
        XCTAssertTrue(rows[1].series.isEmpty)
        XCTAssertNil(rows[1].seriesSummary)
    }

    func testAnOlderServersHistoryStandsInForTheRun() throws {
        // No `exercises` at all: the item is its own row, its history the run.
        let swing = try decoded().rows[0]
        XCTAssertEqual(swing.name, "Nerd Math Two-Hand Swing")
        XCTAssertEqual(swing.marks.map(\.value), [120, 140, 160, nil])
        XCTAssertEqual(swing.todayValue, 180)
        XCTAssertEqual(swing.caption, "Step 7 of 32")
        // `exercises` without `run`: each exercise's history.
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [{"id": "module:clean_press", "title": "Clean and Press", "today": {"text": "10 × 1"}, "times": 3,
          "exercises": [
            {"exerciseId": "clean", "name": "Clean", "today": {"text": "10 × 1 · on the minute"},
             "history": [{"date": "2026-11-08", "dayText": "8 Nov", "text": "5 × 5 · 20 kg · RPE 6", "status": "clean"}]},
            {"exerciseId": "press", "name": "Press", "today": {"text": "10 × 1 · on the minute"},
             "history": [{"date": "2026-11-08", "dayText": "8 Nov", "text": "5 × 5 · 16 kg · RPE 6", "status": "clean"}]},
            {"name": "an exercise without an id is left out"}]}]}
        """.utf8))
        XCTAssertEqual(b.rows.map(\.name), ["Clean", "Press"])
        XCTAssertEqual(b.rows[1].run.first?.text, "5 × 5 · 16 kg · RPE 6")
        XCTAssertEqual(b.rows.map(\.caption), ["1 session", "1 session"])
    }

    func testAPrescriptionAloneSaysNothing() throws {
        let b = try JSONDecoder().decode(SessionBriefing.self, from: Data("""
        {"items": [{"id": "exercise:x", "title": "X", "today": {"text": "3 × 5"}, "history": [], "times": 0}]}
        """.utf8))
        XCTAssertFalse(b.saysSomething)
        XCTAssertTrue(b.pending.isEmpty)
    }
}
