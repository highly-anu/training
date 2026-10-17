import XCTest
@testable import TrainingCompanion

/// A workout against its session's programming (`analysis.planned`,
/// src/analytics/hr_plan.py): the payload decodes, and each exercise's line
/// and the sentence for each way of counting read as the web's
/// (lib/zonePlan.test.ts has the same cases).
final class ZonePlanTests: XCTestCase {

    /// What the server returns for Fran with a Zone 2 row warm-up the watch
    /// timed (test_workout_analysis.py's route case, max HR 180).
    private let payload = """
    {"track": true, "mode": "exercises", "source": "slots", "timing": "timeline",
     "plannedMinutes": [0.0, 15.0, 0.0, 0.0, 0.0], "zoneMinutes": [0.0, 15.0, 0.0, 0.0, 0.0],
     "countedMinutes": 15.0, "method": "samples", "notZoned": ["fran: max_effort"],
     "slots": [{"role": "warm_up", "intensity": "zone2", "zones": [2], "prescribes": "zones",
                "exercises": ["Row"], "plannedMinutes": 15.0, "recordedMinutes": [0.0, 15.0, 0.0, 0.0, 0.0],
                "counted": true},
               {"role": "fran", "intensity": "max_effort", "zones": [], "prescribes": "load",
                "exercises": ["Thruster"], "plannedMinutes": 0.0, "recordedMinutes": [0.0, 5.67, 0.0, 0.0, 0.0],
                "counted": false}],
     "sessionUid": "v:w0-Saturday-0", "sessionName": "Fran", "modality": "mixed_modal_conditioning",
     "date": "2026-10-01"}
    """.data(using: .utf8)!

    private func slot(role: String = "warm_up", intensity: String? = "zone2", zones: [Int] = [2],
                      prescribes: String = "zones", exercises: [String] = ["Row"], planned: Double = 15,
                      recorded: [Double]? = nil, counted: Bool = false) -> WorkoutAnalysis.Planned.Slot {
        .init(role: role, intensity: intensity, zones: zones, prescribes: prescribes, exercises: exercises,
              plannedMinutes: planned, recordedMinutes: recorded, counted: counted)
    }

    private func plan(timing: String = "none", source: String = "slots",
                      notZoned: [String] = ["main: heavy"]) -> WorkoutAnalysis.Planned {
        .init(track: false, mode: "none", source: source, timing: timing, plannedMinutes: [0, 0, 0, 0, 0],
              zoneMinutes: [0, 0, 0, 0, 0], countedMinutes: 0, notZoned: notZoned, slots: [],
              sessionName: "Workout A", modality: "max_strength")
    }

    func testTheServersPayloadDecodes() throws {
        let p = try JSONDecoder().decode(WorkoutAnalysis.Planned.self, from: payload)
        XCTAssertEqual(p.timing, "timeline")
        XCTAssertTrue(p.counts)
        XCTAssertEqual(p.zoneMinutes[1], 15)
        XCTAssertEqual(p.slots.map(\.role), ["warm_up", "fran"])
        XCTAssertEqual(p.slots[1].recordedMinutes?[1], 5.67)
        XCTAssertEqual(ZonePlan.row(p.slots[0], timing: p.timing).detail, "15 of 15 min")
    }

    func testAnOlderShapeStillDecodes() throws {
        // PR #152's first cut sent track and plannedMinutes only.
        let old = #"{"track": true, "source": "slots", "plannedMinutes": [7.5, 12.5, 15, 10, 0]}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(WorkoutAnalysis.Planned.self, from: old)
        XCTAssertEqual(p.timing, "whole")
        XCTAssertTrue(p.slots.isEmpty)
    }

    func testATimedZonedExerciseReadsRecordedOfPlanned() {
        XCTAssertEqual(ZonePlan.row(slot(recorded: [3, 9.4, 0, 0, 0], counted: true), timing: "timeline"),
                       .init(title: "Row", prescription: "Zone 2", detail: "12 of 15 min", counted: true))
    }

    func testALoadExerciseNeverCounts() {
        let heavy = slot(role: "fran", intensity: "max_effort", zones: [], prescribes: "load",
                         exercises: ["Thruster", "Pull-up"], planned: 0)
        XCTAssertEqual(ZonePlan.row(heavy, timing: "timeline").detail, "not counted")
        var timed = heavy
        timed.recordedMinutes = [0, 1, 3, 2, 0]
        XCTAssertEqual(ZonePlan.row(timed, timing: "timeline").detail, "6 min · not counted")
        XCTAssertEqual(ZonePlan.row(heavy, timing: "timeline").prescription, "max effort")
    }

    func testUntimedAndWholeSessionsSaySo() {
        XCTAssertEqual(ZonePlan.row(slot(), timing: "untimed").detail, "not timed")
        XCTAssertEqual(ZonePlan.row(slot(counted: true), timing: "whole").detail, "15 min planned")
        XCTAssertEqual(ZonePlan.row(slot(exercises: []), timing: "whole").title, "Warm up")
        XCTAssertEqual(ZonePlan.prescription(slot(zones: [1, 2])), "Zones 1–2")
    }

    func testTheNoteSaysWhatCountedOrWhyNothingDid() {
        XCTAssertNil(ZonePlan.note(plan(timing: "whole")))
        XCTAssertTrue(ZonePlan.note(plan(timing: "timeline"))!.contains("inside the times the watch logged"))
        XCTAssertTrue(ZonePlan.note(plan(timing: "untimed"))!.contains("didn't time them"))
        XCTAssertEqual(ZonePlan.note(plan(timing: "unrecorded")), "No heart rate was recorded to compare.")
        XCTAssertTrue(ZonePlan.note(plan())!.contains("(main: heavy)"))
        XCTAssertTrue(ZonePlan.untrackedText(plan(source: "declared", notZoned: [])).contains("doesn't track heart rate"))
    }
}
