import XCTest
import SwiftUI
@testable import TrainingCompanion

/// `GET /analytics/development` on the phone. The fixture mirrors a real
/// response from the local API (two blocks, a lift logged across the first,
/// a currency, two weeks of load, one standard) with one malformed lift the
/// decoder must drop rather than fail on.
final class DevelopmentCodableTests: XCTestCase {

    private let fixture = """
    {
      "status": "ok", "generatedAt": "2026-10-01T10:00:00",
      "window": {"from": "2025-10-01", "to": "2026-10-01"},
      "blocks": [
        {"id": 6, "versionId": "46d295ba", "label": "Starting Strength / Mark Rippetoe · 8 wk · from 2026-09-07",
         "methodologies": [{"id": "starting_strength", "name": "Starting Strength / Mark Rippetoe"}],
         "from": "2026-09-07", "to": "2026-09-30", "isActive": false, "weeks": 8,
         "plannedTotal": 24, "planned": 11, "completed": 8, "completionPct": 73, "source": "generate"},
        {"id": 8, "versionId": "9f1c", "label": "Wildman · 4 wk · from 2026-10-01",
         "methodologies": [{"id": "wildman", "name": "Wildman"}, {"id": "ss", "name": "SS"}],
         "from": "2026-10-01", "to": null, "isActive": true, "weeks": 4,
         "plannedTotal": 12, "planned": 0, "completed": 0, "completionPct": null, "source": "put"}
      ],
      "lifts": [
        {"exerciseId": "front_squat", "name": "Front Squat", "unit": "kg",
         "points": [{"date": "2026-09-08", "blockId": 6, "weight": 30.0, "reps": 5, "est1rm": 35.0, "isDeload": false},
                    {"date": "2026-09-16", "blockId": 6, "weight": 47.5, "reps": null, "est1rm": null, "isDeload": true},
                    {"date": "2026-09-25", "blockId": 6, "weight": 55.0, "reps": 5, "est1rm": 64.2, "isDeload": false}],
         "perBlock": [{"blockId": 6, "sessions": 3, "first": 35.0, "last": 64.2, "best": 64.2, "delta": 29.2}],
         "trend": {"direction": "improving", "slopePct": 25.03, "pointsUsed": 2}, "blocks": 1},
        {"name": "No id, dropped", "points": []}
      ],
      "currencies": [
        {"exerciseId": "row_erg", "name": "Row", "metric": "minutes",
         "points": [{"date": "2026-09-10", "blockId": 6, "value": 20, "isDeload": false}],
         "perBlock": [{"blockId": 6, "sessions": 1, "first": 20, "last": 20, "best": 20, "delta": 0}],
         "trend": {"direction": "insufficient_data", "slopePct": 0, "pointsUsed": 1}}
      ],
      "load": {"weekly": [{"week": "2026-W37", "trimp": 120.5, "sessions": 3, "blockId": 6},
                          {"week": "2026-W40", "trimp": 40, "sessions": 1, "blockId": null}],
               "pmc": []},
      "benchmarks": [
        {"benchmarkId": "back_squat_bw_ratio", "name": "Back Squat (bodyweight ratio)", "unit": "×BW", "lowerIsBetter": false,
         "history": [{"date": "2026-09-08", "value": 0.9, "level": null, "levelIndex": -1},
                     {"date": "2026-09-25", "value": 1.25, "level": "novice", "levelIndex": 0}],
         "latestLevel": "novice", "latestLevelIndex": 0, "levelsGained": 1}
      ]
    }
    """

    private func decode(_ json: String) throws -> DevelopmentAnalytics {
        try JSONDecoder().decode(DevelopmentAnalytics.self, from: json.data(using: .utf8)!)
    }

    func testDocumentDecodesAndShapes() throws {
        let doc = try decode(fixture)
        XCTAssertTrue(doc.hasHistory)
        XCTAssertEqual(doc.windowTo, "2026-10-01")

        XCTAssertEqual(doc.blocks.map(\.id), [6, 8], "oldest first, as the server orders them")
        XCTAssertEqual(doc.blocks[1].name, "Wildman + SS", "named by its methodologies")
        XCTAssertNil(doc.blocks[1].completionPct)
        XCTAssertEqual(doc.blocks[0].completionPct, 73)
        XCTAssertEqual(doc.paletteIndex(of: 6), 0)
        XCTAssertEqual(doc.paletteIndex(of: 8), 1)
        XCTAssertNil(doc.paletteIndex(of: 99), "an unknown block has no colour of its own")

        let active = try XCTUnwrap(doc.span(of: doc.blocks[1]))
        XCTAssertEqual(active.upperBound, DevelopmentAnalytics.day("2026-10-01"), "the active block runs to the window's end")
        XCTAssertGreaterThan(doc.share(of: doc.blocks[0]), doc.share(of: doc.blocks[1]))

        XCTAssertEqual(doc.lifts.map(\.id), ["front_squat"], "the malformed lift is dropped, not fatal")
        let points = DevelopmentAnalytics.chartPoints(doc.lifts[0])
        XCTAssertEqual(points.map(\.value), [35.0, 47.5, 64.2], "est-1RM where there is one, else the weight")
        XCTAssertEqual(points.map(\.isDeload), [false, true, false])
        XCTAssertEqual(points[0].detail, "30 kg × 5")
        XCTAssertNil(points[1].detail)
        XCTAssertEqual(doc.lifts[0].perBlock.first?.delta, 29.2)

        XCTAssertEqual(doc.currencies.first?.unit, "min")
        XCTAssertEqual(DevelopmentAnalytics.chartPoints(doc.currencies[0]).first?.value, 20)

        XCTAssertEqual(doc.weeklyLoad.count, 2)
        let monday = try XCTUnwrap(doc.weeklyLoad[0].weekStart)
        XCTAssertEqual(Calendar(identifier: .iso8601).component(.weekday, from: monday), 2, "an ISO week starts on its Monday")
        XCTAssertNil(doc.weeklyLoad[1].blockId, "a week outside every block keeps no block")

        XCTAssertEqual(doc.benchmarks.first?.levelsGained, 1)
        XCTAssertEqual(doc.benchmarks.first?.history.map(\.level), [nil, "novice"])
    }

    func testDeltaFormatting() {
        XCTAssertEqual(DevelopmentAnalytics.formatDelta(12.5), "+12.5")
        XCTAssertEqual(DevelopmentAnalytics.formatDelta(-3), "−3")
        XCTAssertEqual(DevelopmentAnalytics.formatDelta(0), "0")
    }

    func testNoHistoryAndSparseDocuments() throws {
        let empty = try decode("""
        {"status": "no_history", "window": {"from": "2025-10-01", "to": "2026-10-01"},
         "blocks": [], "lifts": [], "currencies": [], "load": {"weekly": [], "pmc": []}, "benchmarks": []}
        """)
        XCTAssertFalse(empty.hasHistory)
        XCTAssertEqual(empty.color(of: nil), Color.secondary)

        // A field the engine adds later, a section that fails, a block with only the essentials.
        let sparse = try decode("""
        {"status": "ok", "blocks": [{"id": 1, "from": "2026-09-07"}], "lifts": {"error": "boom"},
         "load": {"error": "boom"}, "future": {"x": 1}}
        """)
        XCTAssertTrue(sparse.hasHistory)
        XCTAssertEqual(sparse.blocks.first?.name, "", "no methodologies and no label: nothing to name it by")
        XCTAssertTrue(sparse.lifts.isEmpty)
        XCTAssertTrue(sparse.weeklyLoad.isEmpty)
    }
}
