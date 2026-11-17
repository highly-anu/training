import XCTest
@testable import TrainingCompanion

/// The method builder on the phone (roadmap 21.6): what `/api/methods` and a
/// build answer, read from the answers the server's own test recorded for the
/// web (`frontend/src/mocks/fixtures/methods.json`, written by
/// `test_package_builder.py --write`), the request a build is started with,
/// and the words the screens say.
final class MethodBuilderTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func recorded(_ key: String) throws -> Data {
        let file = try Data(contentsOf: Self.repo.appendingPathComponent("frontend/src/mocks/fixtures/methods.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: try XCTUnwrap(all[key]))
    }

    private func build(_ key: String) throws -> MethodBuild {
        struct Envelope: Decodable { let build: MethodBuild }
        return try JSONDecoder().decode(Envelope.self, from: recorded(key)).build
    }

    func testARunningBuildIsOpenAndSaysWhatItIsDoing() throws {
        let running = try build("running")
        XCTAssertTrue(running.isOpen)
        XCTAssertFalse(running.isDone)
        XCTAssertEqual(MethodBuildWords.headline(running), "Writing the method")
        XCTAssertEqual(MethodBuildWords.stepIndex(running), 1)
        XCTAssertEqual(running.progress.detail, "4 files written")
        XCTAssertNil(running.revise)
        XCTAssertFalse((running.description ?? "").isEmpty)
    }

    func testADoneBuildNamesItsMethod() throws {
        let done = try build("done")
        XCTAssertTrue(done.isDone)
        XCTAssertFalse(done.isOpen)
        XCTAssertEqual(done.result?.packageId, "ub544b040_stones")
        XCTAssertFalse((done.result?.summary ?? "").isEmpty)
        XCTAssertEqual(MethodBuildWords.stepIndex(done), MethodBuildWords.steps.count)
    }

    func testAFailedBuildCarriesTheServersWords() throws {
        let failed = try build("failed")
        XCTAssertFalse(failed.isOpen)
        XCTAssertFalse(failed.isDone)
        XCTAssertEqual(failed.error?.code, "budget")
        XCTAssertTrue((failed.error?.message ?? "").hasPrefix("This method took more tries"))
    }

    func testTheListHasTheMethodsAndTheOpenBuild() throws {
        let methods = try JSONDecoder().decode(MethodsAnswer.self, from: recorded("methods"))
        XCTAssertTrue(methods.available)
        XCTAssertTrue(methods.isShown)
        XCTAssertEqual(methods.methods.map(\.id), ["ub544b040_stones"])
        XCTAssertEqual(methods.methods.first?.inUse, false)
        XCTAssertNil(methods.openBuild)
        XCTAssertNil(MethodBuildWords.unavailableReason(methods))

        let running = try JSONDecoder().decode(MethodsAnswer.self, from: recorded("methodsWhileRunning"))
        XCTAssertEqual(running.openBuild?.id, "build-1")
        XCTAssertTrue(running.methods.isEmpty)
    }

    func testAServerThatCannotBuildStillShowsTheMethods() throws {
        let methods = try JSONDecoder().decode(MethodsAnswer.self, from: recorded("unavailable"))
        XCTAssertFalse(methods.available)
        XCTAssertTrue(methods.isShown)
        XCTAssertEqual(methods.methods.count, 1)
        XCTAssertEqual(MethodBuildWords.unavailableReason(methods), "Methods cannot be built right now.")
    }

    func testAnAccountWithoutTheBuilderSeesNothing() throws {
        let body = #"{"available": false, "reason": "not_enabled", "methods": [], "builds": [], "limits": {"daily": 5, "remaining": 5, "kept": 20}}"#
        let methods = try JSONDecoder().decode(MethodsAnswer.self, from: Data(body.utf8))
        XCTAssertFalse(methods.isShown)
        XCTAssertEqual(MethodBuildWords.unavailableReason(methods),
                       "Building your own method is not turned on for this account.")
    }

    func testTheDaysBuildsRunOut() throws {
        let body = #"{"available": true, "reason": null, "methods": [], "builds": [], "limits": {"daily": 5, "remaining": 0, "kept": 20}}"#
        let methods = try JSONDecoder().decode(MethodsAnswer.self, from: Data(body.utf8))
        XCTAssertEqual(MethodBuildWords.unavailableReason(methods), "You have used today's builds. Try again tomorrow.")
    }

    func testEveryStageHasItsWordsAndItsStep() throws {
        func at(_ status: String, _ stage: String?) throws -> MethodBuild {
            let progress = stage.map { #"{"stage": "\#($0)"}"# } ?? "{}"
            return try JSONDecoder().decode(MethodBuild.self,
                                            from: Data(#"{"id": "b", "status": "\#(status)", "progress": \#(progress)}"#.utf8))
        }
        XCTAssertEqual(MethodBuildWords.headline(try at("queued", nil)), "Waiting to start")
        XCTAssertEqual(MethodBuildWords.headline(try at("running", "researching")), "Reading about the method")
        XCTAssertEqual(MethodBuildWords.stepIndex(try at("running", "researching")), 0)
        XCTAssertEqual(MethodBuildWords.headline(try at("running", "fixing")), "Fixing what the checks found")
        XCTAssertEqual(MethodBuildWords.stepIndex(try at("running", "fixing")), 2)
        XCTAssertEqual(MethodBuildWords.stepIndex(try at("running", "installing")), 3)
        XCTAssertEqual(MethodBuildWords.stepIndex(try at("running", "a stage a newer server names")), 0)
    }

    func testTheFormsTextIsHeldToItsLength() {
        XCTAssertNotNil(MethodBuildWords.textProblem("  too short  ", length: MethodBuildWords.descriptionLength, what: "a description"))
        XCTAssertNil(MethodBuildWords.textProblem(String(repeating: "a", count: 20), length: MethodBuildWords.descriptionLength, what: "a description"))
        XCTAssertNotNil(MethodBuildWords.textProblem(String(repeating: "a", count: 8001), length: MethodBuildWords.descriptionLength, what: "a description"))
        XCTAssertNil(MethodBuildWords.textProblem("Longer walks.", length: MethodBuildWords.noteLength, what: "the change"))
    }

    func testANewMethodsRequestCarriesTheWordsAndTheAnswers() throws {
        let request = MethodBuildRequest(text: "  Three strength days and two runs.  ", pastedText: "  ", webSearch: true,
                                         answers: .init(days: 5, minutes: 45, level: "novice", equipment: ["barbell"]),
                                         revises: nil)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(sent["description"] as? String, "Three strength days and two runs.")
        XCTAssertEqual(sent["webSearch"] as? Bool, true)
        XCTAssertNil(sent["pastedText"])
        XCTAssertNil(sent["revise"])
        let answers = try XCTUnwrap(sent["answers"] as? [String: Any])
        XCTAssertEqual(answers["days"] as? Int, 5)
        XCTAssertEqual(answers["minutes"] as? Int, 45)
        XCTAssertEqual(answers["level"] as? String, "novice")
        XCTAssertEqual(answers["equipment"] as? [String], ["barbell"])
    }

    func testARevisionsRequestNamesTheMethodAndTheChange() throws {
        let request = MethodBuildRequest(text: "Make the walks longer.", pastedText: "ignored for a revision", webSearch: false,
                                         answers: .init(days: 4, minutes: 60, level: "intermediate", equipment: []),
                                         revises: "ub544b040_stones")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(sent["description"])
        XCTAssertNil(sent["pastedText"])
        let revise = try XCTUnwrap(sent["revise"] as? [String: Any])
        XCTAssertEqual(revise["packageId"] as? String, "ub544b040_stones")
        XCTAssertEqual(revise["note"] as? String, "Make the walks longer.")
    }

    func testAStartIsABuildOrARefusalInWords() throws {
        let queued = try recorded("running")
        guard case .build(let build) = MethodBuildWords.start(status: 202, body: queued) else {
            return XCTFail("a 202 with a build is a build")
        }
        XCTAssertEqual(build.id, "build-1")

        // The one already running is where the screen goes, not an error.
        var running = try XCTUnwrap(JSONSerialization.jsonObject(with: queued) as? [String: Any])
        running["error"] = "build_running"
        let conflict = try JSONSerialization.data(withJSONObject: running)
        XCTAssertEqual(MethodBuildWords.start(status: 409, body: conflict), .build(build))

        let limit = Data(#"{"error": "daily_limit", "detail": "You have used today's builds. Try again tomorrow."}"#.utf8)
        XCTAssertEqual(MethodBuildWords.start(status: 429, body: limit),
                       .refused("You have used today's builds. Try again tomorrow."))
        XCTAssertEqual(MethodBuildWords.start(status: 404, body: Data(#"{"error": "not_found"}"#.utf8)),
                       .refused("That method is no longer among yours."))
        XCTAssertEqual(MethodBuildWords.start(status: 502, body: Data("<html>".utf8)),
                       .refused("The build could not be started. Try again."))
    }

    func testADeleteSaysWhyItWasRefused() {
        XCTAssertNil(MethodBuildWords.deleteRefusal(status: 200, body: Data("{}".utf8)))
        XCTAssertEqual(MethodBuildWords.deleteRefusal(status: 409, body: Data(#"{"error": "in_use"}"#.utf8)),
                       "Your program is built from this method. Start another program first.")
        XCTAssertEqual(MethodBuildWords.deleteRefusal(status: 500, body: Data()),
                       "The method could not be deleted. Try again.")
    }

    func testADebugLaunchNamesItsScreen() {
        XCTAssertEqual(MethodRoute.describe(revises: nil).id, "describe:")
        XCTAssertNotEqual(MethodRoute.describe(revises: "a").id, MethodRoute.build("a").id)
    }
}
