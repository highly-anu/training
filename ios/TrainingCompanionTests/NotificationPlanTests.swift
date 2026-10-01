import XCTest
@testable import TrainingCompanion

/// The reminder plan is pure: given the stored program and a clock, which
/// days get a notification and what it says. The notification center is not
/// involved, so the rules that matter — array-index weeks, today's time
/// already passed, completed sessions — can be pinned without permission
/// prompts.
final class NotificationPlanTests: XCTestCase {

    private let cal = Calendar.current

    /// Two weeks: Monday strength and Wednesday Zone 2, starting Monday 5 Oct 2026.
    private func program() throws -> GeneratedProgram {
        try JSONDecoder().decode(GeneratedProgram.self, from: Data("""
        {"weeks": [
            {"week_number": 16, "week_in_phase": 1, "is_deload": false, "phase": "base", "schedule": {
                "Monday": [{"modality": "max_strength", "is_deload": false,
                            "archetype": {"id": "hlm", "name": "Back Squat 5×5", "duration_estimate_minutes": 60},
                            "exercises": []}],
                "Wednesday": [{"modality": "aerobic_base", "is_deload": false,
                               "archetype": {"id": "z2", "name": "Zone 2 Run", "duration_estimate_minutes": 45},
                               "exercises": []},
                              {"modality": "mobility", "is_deload": false, "exercises": []}]
            }},
            {"week_number": 17, "week_in_phase": 2, "is_deload": true, "phase": "base", "schedule": {
                "Monday": [{"modality": "max_strength", "is_deload": true,
                            "archetype": {"id": "hlm", "name": "Back Squat 5×5", "duration_estimate_minutes": 60},
                            "exercises": []}]
            }}
        ]}
        """.utf8))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testOneReminderPerTrainingDayWithinTheHorizon() throws {
        let plan = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                              now: date(2026, 10, 5, 6, 0), reminderMinutes: 7 * 60)
        XCTAssertEqual(plan.map(\.dateKey), ["2026-10-05", "2026-10-07", "2026-10-12"],
                       "Mon, Wed of week one and Mon of week two; the horizon ends before week three")
        XCTAssertEqual(plan.first?.identifier, "session-reminder-2026-10-05")
        XCTAssertEqual(plan.first?.title, "Training today")
        XCTAssertEqual(plan.map(\.body), ["Back Squat 5×5 · 60 min",
                                          "Zone 2 Run + Mobility · 45 min",
                                          "Back Squat 5×5 · 60 min (deload)"],
                       "a session without an archetype is named by its modality")
        XCTAssertEqual(plan.first?.fireDate.hour, 7)
        XCTAssertEqual(plan.first?.fireDate.minute, 0)
        XCTAssertEqual(plan.first?.fireDate.day, 5)
    }

    func testTodayIsSkippedOnceItsTimeHasPassed() throws {
        let plan = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                              now: date(2026, 10, 5, 7, 30), reminderMinutes: 7 * 60)
        XCTAssertEqual(plan.first?.dateKey, "2026-10-07")
    }

    func testCompletedSessionsCancelTheirDay() throws {
        // Keys use the week's stored number (16, not 1) — the same key the
        // session logs are stored under.
        let plan = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                              now: date(2026, 10, 5, 6, 0), reminderMinutes: 7 * 60,
                                              completedKeys: ["16-Monday-0", "16-Wednesday-0"])
        XCTAssertEqual(plan.map(\.dateKey), ["2026-10-07", "2026-10-12"])
        XCTAssertEqual(plan.first?.body, "Mobility", "the one Wednesday session still to do")
    }

    func testWeeksAreAddressedByPositionFromTheStartDate() throws {
        // Five days in, on the Saturday of week one: the next training day is
        // the Monday of array index 1 — the deload week — whatever that week
        // is numbered, and the horizon ends before a third week would start.
        let plan = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                              now: date(2026, 10, 10, 6, 0), reminderMinutes: 9 * 60 + 15)
        XCTAssertEqual(plan.map(\.dateKey), ["2026-10-12"], "Monday of the deload week is the last session")
        XCTAssertEqual(plan.first?.body, "Back Squat 5×5 · 60 min (deload)")
        XCTAssertEqual(plan.first?.fireDate.hour, 9)
        XCTAssertEqual(plan.first?.fireDate.minute, 15)

        // Two weeks in, the program is over: nothing to remind.
        let after = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                               now: date(2026, 10, 19, 6, 0))
        XCTAssertTrue(after.isEmpty)
    }

    func testNothingBeforeTheStartOrWithoutAProgram() throws {
        XCTAssertTrue(NotificationPlan.reminders(program: nil, startDate: "2026-10-05").isEmpty)
        XCTAssertTrue(NotificationPlan.reminders(program: try program(), startDate: nil).isEmpty)
        // Three weeks before the start, no day of the horizon is in the program.
        let early = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                               now: date(2026, 9, 10, 6, 0))
        XCTAssertTrue(early.isEmpty)
        // Two days before the start, the horizon reaches into it.
        let close = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                               now: date(2026, 10, 3, 6, 0))
        XCTAssertEqual(close.first?.dateKey, "2026-10-05")
    }

    func testIdentifiersShareThePrefixTheManagerClearsBy() throws {
        let plan = NotificationPlan.reminders(program: try program(), startDate: "2026-10-05",
                                              now: date(2026, 10, 5, 6, 0))
        XCTAssertTrue(plan.allSatisfy { $0.identifier.hasPrefix(NotificationPlan.identifierPrefix) })
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count, "one per day")
    }
}
