import XCTest
@testable import TrainingCompanion

/// A session the athlete adds on the fly (a rest day's mobility): the request
/// asks the server for an extra, the edit appends it marked `added` and only an
/// added one can be removed, and the week's dots count it once it is done
/// (design-system §6.43; the server's rule is `analytics.context.Context.sessions`).
final class AddedSessionTests: XCTestCase {

    private func session(_ modality: String, added: Bool = false) -> ProgramSession {
        ProgramSession(modality: modality, archetype: nil, isDeload: false, exercises: [],
                       extra: added ? ["added": .bool(true)] : [:])
    }

    private var program: GeneratedProgram {
        GeneratedProgram(weeks: [ProgramWeek(weekNumber: 1, weekInPhase: 1, isDeload: false, phase: "base",
                                             schedule: ["Monday": [session("max_strength")]])])
    }

    func testTheServersAddedFlagDecodes() throws {
        let json = #"{"modality":"mobility","is_deload":false,"exercises":[],"added":true,"provenance":{"package":"kelly_starrett","borrowed":true,"label":"Kelly Starrett / Built to Move"}}"#
        let s = try JSONDecoder().decode(ProgramSession.self, from: Data(json.utf8))
        XCTAssertTrue(s.isAdded)
        XCTAssertEqual(ReplaceWorkoutSheet.borrowedLabel(s), "Kelly Starrett / Built to Move")
        let plain = try JSONDecoder().decode(ProgramSession.self, from: Data(#"{"modality":"mobility"}"#.utf8))
        XCTAssertFalse(plain.isAdded)
        XCTAssertNil(ReplaceWorkoutSheet.borrowedLabel(plain))
    }

    func testTheRequestAsksForAnExtra() throws {
        var request = GenerateSessionRequest(
            primarySources: [], modality: "mobility", phase: "base", weekInPhase: 1, isDeload: false,
            constraints: GenerateSessionConstraints(sessionTimeMinutes: 30, fatigueState: "normal"),
            archetypeId: nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(json["add"], "a replace sends no add")
        request.add = true
        request.currentArchetypeId = "btm_d08"
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["add"] as? Bool, true)
        XCTAssertEqual(json["current_archetype_id"] as? String, "btm_d08")
    }

    func testAddingAppendsAMarkedSessionAndKeepsTheOthersPlace() {
        let out = ProgramEdits.addingSession(in: program, weekIndex: 0, day: "Monday", session: session("mobility"))
        let monday = out.weeks[0].schedule["Monday"] ?? []
        XCTAssertEqual(monday.map(\.modality), ["max_strength", "mobility"])
        XCTAssertTrue(monday[1].isAdded)
        XCTAssertFalse(monday[0].isAdded)
        let rest = ProgramEdits.addingSession(in: program, weekIndex: 0, day: "Friday", session: session("mobility"))
        XCTAssertEqual(rest.weeks[0].schedule["Friday"]?.count, 1, "a rest day's first")
        XCTAssertEqual(ProgramEdits.addingSession(in: program, weekIndex: 5, day: "Monday",
                                                  session: session("mobility")).weeks[0].schedule["Monday"]?.count, 1,
                       "no such week: unchanged")
    }

    func testOnlyAnAddedSessionIsRemoved() {
        let added = ProgramEdits.addingSession(in: program, weekIndex: 0, day: "Monday", session: session("mobility"))
        XCTAssertEqual(ProgramEdits.removingSession(in: added, weekIndex: 0, day: "Monday", sessionIndex: 1)
                        .weeks[0].schedule["Monday"]?.count, 1)
        XCTAssertEqual(ProgramEdits.removingSession(in: program, weekIndex: 0, day: "Monday", sessionIndex: 0)
                        .weeks[0].schedule["Monday"]?.count, 1, "the plan's own session stays")
    }

    func testWeekDotsCountAnExtraOnceDone() {
        let week = ProgramWeek(weekNumber: 1, weekInPhase: 1, isDeload: false, phase: "base",
                               schedule: ["Monday": [session("max_strength")],
                                          "Friday": [session("mobility", added: true)]])
        XCTAssertEqual(WorkoutCompletion.weekDots(week, isComplete: { _ in false }).count, 1)
        let done = WorkoutCompletion.weekDots(week, isComplete: { $0.hasSuffix("Friday-0") })
        XCTAssertEqual(done.count, 2)
        XCTAssertTrue(done.last?.done ?? false)
    }
}
