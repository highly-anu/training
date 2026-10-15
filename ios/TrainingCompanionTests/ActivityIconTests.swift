import XCTest
@testable import TrainingCompanion

/// The watch records a session's archetype name as its activity type, so the
/// strings here are real archetype names as well as device activity types.
final class ActivityIconTests: XCTestCase {
    private func icon(_ s: String) -> String? { ActivityIcon.forActivityType(s) }

    func testSkillIsNotSkiing() {
        XCTAssertEqual(icon("KB Movement Skill Session (Wildman)"), "figure.strengthtraining.functional")
        XCTAssertNil(icon("Skill Ladder (10–15 min Progressive Blocks)"))
        XCTAssertEqual(ActivityIcon.forWorkout(activityType: "Skill Ladder", modalityId: "movement_skill"),
                       ModalityStyle.icon(for: "movement_skill"))
    }

    func testSkiingStillSkiing() {
        XCTAssertEqual(icon("cross_country_skiing"), "figure.skiing.crosscountry")
        XCTAssertEqual(icon("SkiErg"), "figure.skiing.crosscountry")
    }

    func testKettlebellArchetypes() {
        XCTAssertEqual(icon("Double KB Strength Session (Wildman)"), "figure.strengthtraining.functional")
        XCTAssertEqual(icon("Kettlebell"), "figure.strengthtraining.functional")
    }

    func testBoxStepUpsAreNotBoxing() {
        XCTAssertEqual(icon("Weighted Box Step-Ups (ME)"), "figure.strengthtraining.traditional")
        XCTAssertEqual(icon("boxing"), "figure.boxing")
    }

    func testDeviceActivityTypes() {
        XCTAssertEqual(icon("Running"), "figure.run")
        XCTAssertEqual(icon("trail_running"), "figure.run")
        XCTAssertEqual(icon("road_biking"), "figure.outdoor.cycle")
        XCTAssertEqual(icon("Cycling"), "figure.outdoor.cycle")
        XCTAssertEqual(icon("indoor_rowing"), "figure.rowing")
        XCTAssertEqual(icon("strength_training"), "figure.strengthtraining.traditional")
        XCTAssertEqual(icon("Weighted Ruck Z2"), "figure.hiking")
        XCTAssertEqual(icon("watch_16-Saturday-0"), "applewatch.watchface")
        XCTAssertNil(icon("workout"))
    }

    func testActivityLabelKeepsWrittenNames() {
        XCTAssertEqual(ImportedWorkout.activityLabel("KB Movement Skill Session (Wildman)"),
                       "KB Movement Skill Session (Wildman)")
        XCTAssertEqual(ImportedWorkout.activityLabel("Weighted Box Step-Ups (ME)"), "Weighted Box Step-Ups (ME)")
        XCTAssertEqual(ImportedWorkout.activityLabel("cross_country_skiing"), "Cross Country Skiing")
        XCTAssertEqual(ImportedWorkout.activityLabel("TRAIL_RUNNING"), "Trail Running")
        XCTAssertEqual(ImportedWorkout.activityLabel("Running"), "Running")
    }
}
