import XCTest
@testable import TrainingCompanion

/// The review explains its own score (`src/analytics/review.py`): the phone
/// decodes the explanation, takes the band from the server, and still reads
/// a review from a server that predates it.
final class ProgressionScoreTests: XCTestCase {
    /// Production's review on 2026-10-16, trimmed.
    private let explained = """
    {"period_key": "2026-W42", "period_type": "weekly", "generated_at": null, "overall_score": 100,
     "readiness_trend": "stable", "avg_readiness": null, "compliance_pct": 100,
     "exercise_findings": [{"exercise_id": "skills", "name": "Movements earned", "metric_type": "complexity",
       "expected_value": null, "actual_value": 0, "unit": "exercises", "status": "insufficient_data",
       "trend": "stable", "change_summary": "+0 exercises over 1 wk",
       "description": "Movements practised enough to count, and what they unlock next",
       "waiting_for": "1 of 2 sessions logged — the trend starts at 2."}],
     "flags": [], "recommendations": [], "adjustments": [],
     "score_breakdown": {"basis": "compliance_only",
       "summary": "Sessions only for now: 2 of 2 done. Trends count once a measure has data from 2 sessions.",
       "parts": [{"id": "compliance", "label": "Sessions done", "value": 100, "weight": 1.0, "points": 100}],
       "completed": 2, "scheduled": 2, "measured": 0, "waiting": 1,
       "measures": [{"id": "skills", "name": "Movements earned", "status": "insufficient_data", "points": null,
                     "detail": "1 of 2 sessions logged — the trend starts at 2."}]},
     "score_status": {"id": "on_track", "label": "On Track",
       "reason": "Every session due so far is done; no lift or skill trend yet.",
       "bands": [{"id": "on_track", "label": "On Track", "min": 70}, {"id": "mixed", "label": "Mixed", "min": 45},
                 {"id": "off_track", "label": "Off Track", "min": 0}],
       "counts": [{"status": "stalled", "count": 3, "label": "stalled"}, {"status": "on_track", "count": 1, "label": "on track"}]},
     "scope_label": "2 of 2 sessions so far · week 1",
     "pending_measures": [{"id": "ballistic_load", "label": "Ballistic load", "description": "Best working set",
       "reason": "None of the sessions it measures has come up yet — the next is Mon 19 Oct.",
       "needs": [{"label": "Reps and kg per set", "where": "The session logger"}]}],
     "purpose": "Is the training working?"}
    """

    private let older = """
    {"period_key": "2026-W42", "period_type": "weekly", "generated_at": null, "overall_score": 52,
     "readiness_trend": "stable", "avg_readiness": null, "compliance_pct": 50,
     "exercise_findings": [], "flags": [], "recommendations": [], "adjustments": []}
    """

    private func decode(_ json: String) throws -> ProgressionReview {
        try JSONDecoder().decode(ProgressionReview.self, from: Data(json.utf8))
    }

    func testDecodesTheExplanation() throws {
        let r = try decode(explained)
        XCTAssertEqual(r.scoreBreakdown?.basis, "compliance_only")
        XCTAssertEqual(r.scoreBreakdown?.parts.first?.points, 100)
        XCTAssertEqual(r.scopeLabel, "2 of 2 sessions so far · week 1")
        XCTAssertEqual(r.pendingMeasures?.first?.needs.first?.where, "The session logger")
        XCTAssertEqual(r.exerciseFindings.first?.waitingFor, "1 of 2 sessions logged — the trend starts at 2.")
        XCTAssertEqual(ProgressionScore.band(r)?.label, "On Track")
    }

    func testTheBreakdownNamesEachMeasure() throws {
        let measures = try XCTUnwrap(try decode(explained).scoreBreakdown?.measures)
        XCTAssertEqual(measures.map(\.name), ["Movements earned"])
        XCTAssertNil(measures.first?.points, "a measure still collecting adds no points")
        XCTAssertEqual(measures.first?.detail, "1 of 2 sessions logged — the trend starts at 2.")
    }

    func testTheCardCountsEachStatus() throws {
        let counts = try XCTUnwrap(try decode(explained).scoreStatus?.counts)
        XCTAssertEqual(counts.map(\.status), ["stalled", "on_track"], "worst first, as the server orders them")
        XCTAssertEqual(counts.map(\.count), [3, 1])
        XCTAssertEqual(AnalyticsStatusStyle.symbol("behind"), "tortoise")
        XCTAssertEqual(AnalyticsStatusStyle.symbol("stalled"), "pause.circle")
    }

    func testOlderServerStillReads() throws {
        let r = try decode(older)
        XCTAssertNil(r.scoreStatus)
        XCTAssertNil(r.exerciseFindings.first?.description)
        XCTAssertEqual(ProgressionScore.band(r)?.id, "mixed", "the thresholds the server uses")
    }

    func testBandRanges() throws {
        let bands = try XCTUnwrap(try decode(explained).scoreStatus?.bands)
        XCTAssertEqual((0..<3).map { ProgressionScore.range(bands, at: $0) }, ["70 and up", "45–69", "below 45"])
    }
}
