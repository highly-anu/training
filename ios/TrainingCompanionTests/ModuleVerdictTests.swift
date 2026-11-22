import XCTest
@testable import TrainingCompanion

/// A contract session's verdict: clean moves a module on only at or below the
/// module's own RPE (the server's `clean_shortfall`), and the phone says so
/// with the session's own ceiling.
final class ModuleVerdictTests: XCTestCase {
    private func session(maxRpe: String = "7") throws -> ProgramSession {
        let data = Data(#"""
        {"modality":"power","is_deload":false,
         "modules":[{"id":"swing","max_rpe":\#(maxRpe),"exercise_ids":["wk_kb_swing_two_hand"]}],
         "exercises":[
          {"exercise":{"id":"wk_kb_halo","name":"Halo"},"slot_role":"recovery","slot_type":"skill_practice","meta":false,
           "load":{"module_id":"swing","advances_module":false,"duration_minutes":2}},
          {"exercise":{"id":"wk_kb_swing_two_hand","name":"Swing"},"slot_role":"work","slot_type":"emom","meta":false,
           "load":{"module_id":"swing","advances_module":true,"target_rounds":10}}]}
        """#.utf8)
        return try JSONDecoder().decode(ProgramSession.self, from: data)
    }

    func testTheCeilingIsTheModulesOwn() throws {
        XCTAssertEqual(ModuleVerdict.ceiling(of: try session(), exercise: "wk_kb_swing_two_hand"), 7)
        XCTAssertEqual(ModuleVerdict.ceiling(of: try session(maxRpe: "6.0"), exercise: "wk_kb_swing_two_hand"), 6)
        XCTAssertNil(ModuleVerdict.ceiling(of: try session(), exercise: "wk_kb_halo"),
                     "a block no progress rides on has none")
    }

    func testCleanOverTheCeilingHoldsTheCycle() {
        XCTAssertEqual(ModuleVerdict.read(clean: true, rpe: 7, ceiling: 7), .clean)
        XCTAssertEqual(ModuleVerdict.read(clean: true, rpe: 8, ceiling: 7), .overRpe(ceiling: 7))
        XCTAssertEqual(ModuleVerdict.read(clean: false, rpe: 5, ceiling: 7), .notClean)
        XCTAssertEqual(ModuleVerdict.read(clean: true, rpe: 9, ceiling: nil), .clean,
                       "without a record the flag is all there is")
        XCTAssertEqual(ModuleVerdict.words(clean: true, rpe: 8, ceiling: 7),
                       "Clean · RPE 8 — over RPE 7, the cycle holds here")
        XCTAssertEqual(ModuleVerdict.words(clean: true, rpe: 6, ceiling: 7), "Clean, as written · RPE 6")
    }

    func testTheLogFormKnowsTheCeilingOfTheProgressingBlockOnly() throws {
        let drafts = SessionLogDraft.exercises(of: try session(), log: nil)
        XCTAssertEqual(drafts.map(\.moduleCeiling), [nil, 7])
    }
}
