import XCTest
import SwiftUI
@testable import TrainingCompanion

/// `GET /analytics/program` on the phone. The fixture mirrors a real response
/// from the engine (Starting Strength, two weeks in, nothing logged) with one
/// entry given a series so the chart path is covered, one section answered
/// with the server's `{"error": ...}` shape, and one malformed progress row.
final class ProgramAnalyticsCodableTests: XCTestCase {

    private let fixture = """
    {
      "status": "ok", "revision": "2026-10-01T09:10:07", "generatedAt": "2026-10-01T09:30:00",
      "frame": {
        "status": "active", "startDate": "2026-09-21", "today": "2026-10-01", "plannedWeeks": 4, "elapsedWeeks": 2,
        "deloadWeeks": [4],
        "philosophies": [{"id": "starting_strength", "name": "Starting Strength / Mark Rippetoe",
                          "progressionPhilosophy": null, "intensityModel": null, "corePrinciples": [], "weight": 1.0, "analytics": "declared"}],
        "framework": {"id": "linear_progression", "name": "Linear Progression (SS)", "progressionModel": "linear_load",
                      "intensityDistribution": null, "sessionsPerWeek": null, "modalityPriority": null, "notes": null},
        "phase": {"name": "base", "weekInPhase": 2, "weekInProgram": 2, "totalWeeks": 4, "focus": null, "isDeload": false},
        "phaseSequence": [{"phase": "base", "weeks": 8, "frameworkId": null, "focus": null}],
        "planFidelity": [{"field": "days_per_week", "ideal": 3, "minimum": 3, "actual": 3, "unit": "days", "status": "meets_ideal"},
                         {"field": "session_time_minutes", "ideal": 75, "minimum": 45, "actual": 60, "unit": "min", "status": "below_ideal"}]
      },
      "scorecard": {
        "headline": "off_plan", "overallPct": 20.0,
        "tiers": {"committed": {"planned": 5, "completed": 1, "pct": 20.0}},
        "elapsedWeeks": 2,
        "modalities": [{"modality": "max_strength", "family": "strength", "tier": "committed", "priority": 1.0,
                        "plannedSessions": 5, "completedSessions": 1, "completionPct": 20.0, "plannedMinutes": 355,
                        "actualMinutes": 70, "weeklyPlannedMinutes": 178, "weeklyActualMinutes": 35,
                        "minWeeklyMinutes": 60, "maxWeeklyMinutes": 270, "doseStatus": "under", "planDoseStatus": "on",
                        "minutesSource": {}}]
      },
      "intensity": {"status": "insufficient_data", "coverage": {"inScope": 0, "measured": 0, "pct": 0.0, "reason": null},
                    "maxHr": 185, "methods": {}, "weeks": [], "byFramework": [], "maxDeviationPts": 0.0},
      "methodologies": [{"philosophy": "starting_strength", "weight": 1.0, "analytics": "declared", "headlineId": "bar_load",
                         "entryIds": ["bar_load", "novice_completion"], "measurable": 1, "total": 2}],
      "progress": [
        {"id": "bar_load", "label": "Load on the bar", "primitive": "set_load", "philosophy": "starting_strength",
         "weight": 1.0, "headline": true, "source": "declared", "metric": "best_set_kg", "unit": "kg",
         "series": [{"week": 1, "x": 1, "value": 100, "date": "2026-09-22", "isDeload": false, "reps": 5},
                    {"week": 1, "x": 2, "value": 102.5, "date": "2026-09-24", "isDeload": false}],
         "expected": [{"week": 1, "x": 1, "value": 100}, {"week": 1, "x": 2, "value": 102.5}, {"week": 2, "x": 3, "value": 105}],
         "status": "on_track", "trend": {"direction": "improving", "slopePct": 2.5, "pointsUsed": 2},
         "coverage": {"inScope": 1, "measured": 1, "pct": 100.0, "reason": null},
         "evidence": ["Back Squat: 100 → 102.5 kg over 2 sessions"],
         "exercises": [{"exerciseId": "back_squat", "name": "Back Squat",
                        "series": [{"week": 1, "x": 1, "value": 100, "isDeload": false}, {"week": 1, "x": 2, "value": 102.5, "isDeload": true}],
                        "expected": [{"week": 1, "x": 1, "value": 100}], "trend": {"direction": "improving", "slopePct": 2.5, "pointsUsed": 2},
                        "status": "on_track", "stalled": false, "increment": 2.5, "prescribedNow": 105, "latest": null, "bestEst1rm": 119.4},
                       {"exerciseId": "press", "name": "Press", "series": [], "expected": [], "trend": {"direction": "insufficient_data", "slopePct": 0, "pointsUsed": 0},
                        "status": "insufficient_data", "stalled": false}],
         "leadExerciseId": "back_squat", "stallRule": {"sessions": 3, "tolerancePct": 0}},
        {"id": "novice_completion", "label": "Novice completion standard", "primitive": "benchmark_level", "philosophy": "starting_strength",
         "weight": 1.0, "headline": false, "source": "declared", "metric": "benchmark_level", "unit": "level", "series": [], "expected": [],
         "status": "insufficient_data", "trend": {"direction": "insufficient_data", "slopePct": 0.0, "pointsUsed": 0},
         "coverage": {"inScope": 3, "measured": 0, "pct": 0.0, "reason": "no_pr_logged"}, "evidence": [],
         "benchmarks": [{"benchmarkId": "back_squat_bw_ratio", "name": "Back Squat (bodyweight ratio)", "unit": "×BW", "lowerIsBetter": false,
                         "metricType": "bw_ratio", "latest": null, "latestDate": null, "level": null, "levelIndex": 0, "next": "entry",
                         "gapToNext": null, "target": "intermediate", "targetValue": 1.5, "met": null,
                         "standards": {"entry": 0.75, "intermediate": 1.5, "advanced": 2.0, "elite": 2.5}, "history": []}]},
        {"label": "no id, so not an entry", "primitive": "rounds"}
      ],
      "movement": {"error": "movement_patterns.yaml missing"},
      "archetypes": [], "benchmarks": {"sex": "male", "bodyweightKg": null, "bodyweightDate": null, "benchmarks": []},
      "load": {"readiness": {"score": 60, "status": "yellow", "flags": ["insufficient_data"]}, "phase": "base", "isDeload": false,
               "tsb": -4.2, "reading": "loading_as_expected",
               "note": "A negative training-stress balance is expected while the block is loading; it becomes a flag in a taper."}
    }
    """.data(using: .utf8)!

    func testDocumentDecodesEverySectionOnItsOwn() throws {
        let doc = try JSONDecoder().decode(ProgramAnalytics.self, from: fixture)
        XCTAssertTrue(doc.hasProgram)
        XCTAssertEqual(doc.revision, "2026-10-01T09:10:07")

        let frame = try XCTUnwrap(doc.frame)
        XCTAssertEqual(frame.philosophies.first?.name, "Starting Strength / Mark Rippetoe")
        XCTAssertEqual(frame.framework?.name, "Linear Progression (SS)")
        XCTAssertEqual(frame.phase?.weekInProgram, 2)
        XCTAssertEqual(frame.phase?.totalWeeks, 4)
        XCTAssertEqual(frame.deloadWeeks, [4])
        XCTAssertEqual(frame.planFidelity.map(\.status), ["meets_ideal", "below_ideal"])

        let scorecard = try XCTUnwrap(doc.scorecard)
        XCTAssertEqual(scorecard.headline, "off_plan")
        XCTAssertEqual(scorecard.tiers["committed"]?.planned, 5)
        XCTAssertEqual(scorecard.modalities.first?.doseStatus, "under")
        XCTAssertEqual(scorecard.modalities.first?.completionPct, 20)

        XCTAssertEqual(doc.intensity?.status, "insufficient_data")
        XCTAssertEqual(doc.intensity?.maxHr, 185)
        XCTAssertEqual(doc.methodologies.first?.measurable, 1)
        XCTAssertEqual(doc.load?.reading, "loading_as_expected")
        XCTAssertEqual(doc.load?.tsb, -4.2)
        XCTAssertEqual(doc.load?.readiness?.score, 60)
    }

    func testProgressEntriesKeepSeriesExercisesAndBenchmarks() throws {
        let doc = try JSONDecoder().decode(ProgramAnalytics.self, from: fixture)
        XCTAssertEqual(doc.progress.map(\.id), ["bar_load", "novice_completion"], "the row without an id is dropped, the rest kept")

        let load = doc.progress[0]
        XCTAssertTrue(load.headline)
        XCTAssertEqual(load.status, "on_track")
        XCTAssertEqual(load.series.map(\.value), [100, 102.5])
        XCTAssertEqual(load.expected.count, 3)
        XCTAssertEqual(load.trend?.direction, "improving")
        XCTAssertEqual(load.coverage?.pct, 100)
        XCTAssertEqual(load.evidence.count, 1)
        XCTAssertEqual(load.exercises.map(\.exerciseId), ["back_squat", "press"])
        XCTAssertEqual(load.leadExercise?.exerciseId, "back_squat", "the lead lift opens the card")
        XCTAssertEqual(load.leadExercise?.series.last?.isDeload, true)
        XCTAssertEqual(load.leadExercise?.bestEst1rm, 119.4)

        let novice = doc.progress[1]
        XCTAssertEqual(novice.primitive, "benchmark_level")
        XCTAssertEqual(novice.coverage?.reason, "no_pr_logged")
        XCTAssertEqual(novice.benchmarks.first?.target, "intermediate")
        XCTAssertNil(novice.benchmarks.first?.latest)
        XCTAssertNil(novice.leadExercise)
    }

    func testAFailedSectionIsReportedNotFatal() throws {
        let doc = try JSONDecoder().decode(ProgramAnalytics.self, from: fixture)
        XCTAssertNil(doc.movement)
        XCTAssertEqual(doc.sectionErrors["movement"], "movement_patterns.yaml missing")
        XCTAssertNotNil(doc.scorecard, "the other sections still decode")
    }

    func testNoProgramAndEmptyBodies() throws {
        let none = try JSONDecoder().decode(ProgramAnalytics.self, from: #"{"status": "no_program"}"#.data(using: .utf8)!)
        XCTAssertFalse(none.hasProgram)
        XCTAssertNil(none.scorecard)
        let empty = try JSONDecoder().decode(ProgramAnalytics.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(empty.hasProgram)
        XCTAssertEqual(empty.progress.count, 0)
        XCTAssertEqual(empty.methodologies.count, 0)
    }

    func testStatusStyleMatchesTheWebsMapping() {
        XCTAssertEqual(AnalyticsStatusStyle.color("on_plan"), .green)
        XCTAssertEqual(AnalyticsStatusStyle.color("on_track"), .green)
        XCTAssertEqual(AnalyticsStatusStyle.color("behind"), .yellow)
        XCTAssertEqual(AnalyticsStatusStyle.color("off_plan"), .red)
        XCTAssertEqual(AnalyticsStatusStyle.color("stalled"), .red)
        XCTAssertEqual(AnalyticsStatusStyle.color("insufficient_data"), .secondary)
        XCTAssertEqual(AnalyticsStatusStyle.color("something_new"), .secondary, "an unknown status degrades to neutral")
        XCTAssertEqual(AnalyticsStatusStyle.label("stable_by_design"), "Holding")
        XCTAssertEqual(AnalyticsStatusStyle.label("insufficient_data"), "Not enough data")
        XCTAssertEqual(AnalyticsStatusStyle.label("something_new"), "something new")
        XCTAssertTrue(AnalyticsStatusStyle.coverageReason("no_pr_logged").contains("No PR logged"))
        XCTAssertEqual(AnalyticsStatusStyle.coverageReason("unheard_of"), "Nothing logged for this metric yet.")
        XCTAssertEqual(AnalyticsStatusStyle.coverageReason(nil), "Nothing logged for this metric yet.")
    }

    func testFidelityLabelsAndNumbers() {
        XCTAssertEqual(AnalyticsProgramTab.fidelityLabel("days_per_week"), "Days per week")
        XCTAssertEqual(AnalyticsProgramTab.fidelityLabel("session_time_minutes"), "Session length")
        XCTAssertEqual(AnalyticsProgramTab.fidelityLabel("some_other_field"), "Some Other Field")
        XCTAssertEqual(AnalyticsProgramTab.number(75), "75")
        XCTAssertEqual(AnalyticsProgramTab.number(2.5), "2.5")
    }
}
