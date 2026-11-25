import XCTest
@testable import TrainingCompanion

/// A shared link on the phone (docs/roadmap.md item 25): the route, the
/// server's documents as it recorded them (`frontend/src/mocks/fixtures/shares.json`,
/// written by `test_sharing.py --write`, which fails when the routes stop
/// answering them), what the reader is told, and how a recipe opens the builder.
@MainActor
final class SharedLinkTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func document(_ name: String) throws -> ShareDocument {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("frontend/src/mocks/fixtures/shares.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let one = try JSONSerialization.data(withJSONObject: try XCTUnwrap(all[name]))
        return try JSONDecoder().decode(ShareDocument.self, from: one)
    }

    // MARK: The route

    func testTheLinkTheWebPageOffersOpensTheSheet() {
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://share?token=abc-123_X")!), .share("abc-123_X"))
        XCTAssertNil(DeepLink.parse(URL(string: "trainingcompanion://share")!))
        XCTAssertNil(DeepLink.parse(URL(string: "trainingcompanion://share?token=")!))
    }

    func testOnlyASharedLinkIsKeptAcrossSignIn() {
        XCTAssertTrue(DeepLink.share("t").survivesSignIn)
        XCTAssertFalse(DeepLink.tab(.dashboard).survivesSignIn)
        XCTAssertFalse(DeepLink.session("1-Monday-0").survivesSignIn)
    }

    func testTheRouterPresentsEachRequestAnew() async {
        let router = AppRouter()
        router.open(.share("t"))
        let first = router.pendingShare
        XCTAssertEqual(first?.token, "t")
        router.open(.share("t"))
        XCTAssertNotEqual(router.pendingShare?.id, first?.id)
    }

    // MARK: The server's documents

    func testASharedSessionDecodesWithItsBlocks() throws {
        let doc = try document("session")
        XCTAssertEqual(doc.kind, "session")
        let shared = try XCTUnwrap(doc.session)
        XCTAssertEqual(shared.name, doc.title)
        XCTAssertFalse(shared.session.exercises.isEmpty)
        let blocks = shared.session.blocks
        XCTAssertFalse(blocks.isEmpty)
        // Every movement of a block names a slot the session has an exercise for.
        let roles = Set(shared.session.exercises.compactMap(\.slotRole))
        for movement in blocks.flatMap(\.movements) {
            XCTAssertTrue(roles.contains(movement.role), "\(movement.role) has no exercise")
        }
        XCTAssertEqual(SessionBlock.stages(blocks).map(\.label), ["Start", "Main work"])
        XCTAssertNotNil(shared.week?.weekNumber)
        XCTAssertNotNil(shared.method?.name)
        XCTAssertNil(doc.availability, "a session has nothing to save")
    }

    func testASharedMethodDecodesWithWhatTheReaderHas() throws {
        let doc = try document("method")
        let method = try XCTUnwrap(doc.method)
        XCTAssertFalse(method.shipped)
        let describe = try XCTUnwrap(method.describe)
        XCTAssertFalse(describe.tracks?.first?.phases?.isEmpty ?? true)
        let sessions = try XCTUnwrap(describe.sessions)
        let listed = (describe.groups ?? []).flatMap(\.sessions)
        XCTAssertFalse(listed.isEmpty)
        for id in listed { XCTAssertNotNil(sessions[id], "\(id) is grouped but not described") }
        XCTAssertFalse(sessions.values.first?.blocks?.isEmpty ?? true)
        let a = try XCTUnwrap(doc.availability)
        XCTAssertFalse(a.yours)
        XCTAssertFalse(a.ready)
        XCTAssertEqual(a.toSave, a.methods.count)
        XCTAssertTrue(a.methods.allSatisfy { $0.state == "missing" && $0.savable })
    }

    func testASharedProgramDecodesAsAShapeAndARecipe() throws {
        let doc = try document("program")
        let program = try XCTUnwrap(doc.program)
        XCTAssertEqual(program.phases.map(\.weeks).reduce(0, +), program.weeks)
        let recipe = try XCTUnwrap(doc.recipe)
        XCTAssertEqual(recipe.numWeeks, program.weeks)
        let start = try XCTUnwrap(BuilderStart(recipe: recipe))
        XCTAssertEqual(start.lanes.map(\.philosophyId), [recipe.philosophyId])
        XCTAssertEqual(start.lanes.first?.trackId, recipe.trackId)
        XCTAssertEqual(start.numWeeks, program.weeks)
    }

    // MARK: A recipe into the builder

    private func recipe(_ json: String) throws -> ShareRecipe {
        try JSONDecoder().decode(ShareRecipe.self, from: Data(json.utf8))
    }

    func testACompositionKeepsEachTracksStartAndWeight() throws {
        let r = try recipe(#"{"num_weeks": 12, "lanes": [{"philosophy_id": "alpha", "track_id": "t1", "weight": 0.6, "start_phase": "a"}, {"philosophy_id": "beta", "track_id": null, "weight": 0.4}]}"#)
        let lanes = r.builderLanes
        XCTAssertEqual(lanes.map(\.philosophyId), ["alpha", "beta"])
        XCTAssertEqual(lanes.map(\.weight), [60, 40])
        XCTAssertEqual(lanes.map(\.startPhaseId), ["a", nil])
        XCTAssertEqual(lanes.map(\.trackId), ["t1", nil])
    }

    func testARecipeThatNamesNoMethodOpensNothing() throws {
        XCTAssertNil(BuilderStart(recipe: try recipe(#"{"num_weeks": 4}"#)))
        XCTAssertNil(BuilderStart(recipe: nil))
    }

    func testTheBuilderStartsOnTheRecipeAndKeepsItsLength() async throws {
        let card = try JSONDecoder().decode(PhilosophyCard.self, from: Data(#"""
        {"id": "alpha", "name": "Alpha", "tracks": [{"id": "t1", "name": "Main", "phases": [
          {"id": "p1", "name": "One", "kind": "base", "weeks": 4}, {"id": "p2", "name": "Two", "kind": "build", "weeks": 4}]}]}
        """#.utf8))
        let builder = BuilderState()
        let start = try XCTUnwrap(BuilderStart(recipe: try recipe(
            #"{"philosophy_id": "alpha", "track_id": "t1", "start_phase": "p2", "num_weeks": 6, "contract_options": {"swing": "c"}}"#)))
        builder.apply(start, philosophies: [card])
        XCTAssertEqual(builder.selectedPhilosophyId, "alpha")
        XCTAssertEqual(builder.selectedTrackId, "t1")
        XCTAssertEqual(builder.startPhaseId, "p2")
        XCTAssertEqual(builder.numWeeks, 6)
        XCTAssertEqual(builder.constraints.contractOptions, ["swing": "c"])
        // The schedule step sets a track's own length once: not over the recipe's.
        builder.applyLength(of: builder.track(in: card))
        XCTAssertEqual(builder.numWeeks, 6)

        let unknown = BuilderState()
        unknown.apply(start, philosophies: [])
        XCTAssertFalse(unknown.isStep1Valid, "a method the athlete does not have is not picked")
    }

    // MARK: Words

    func testASaveIsToldInTheReadersWords() {
        func outcome(_ status: Int, _ json: String) -> ShareSaveOutcome { ShareWords.saveOutcome(status: status, body: Data(json.utf8)) }
        XCTAssertEqual(outcome(200, #"{"ok": true, "installed": [{"id": "a", "name": "Blocks"}]}"#), .saved(["Blocks"]))
        XCTAssertEqual(outcome(409, #"{"error": "different", "methods": [{"id": "a", "name": "Blocks"}]}"#), .different(["Blocks"]))
        XCTAssertEqual(outcome(429, #"{"busy": true}"#), .refused("The server is busy with another check. Try again in a moment."))
        XCTAssertEqual(outcome(422, #"{"error": "not_installable", "olderEngine": true, "name": "Blocks", "problems": []}"#),
                       .refused("Blocks was written for an earlier version of the app and no longer passes its checks. Ask for a new link."))
        XCTAssertEqual(outcome(422, #"{"error": "not_installable", "name": "Blocks", "problems": [{"message": "no track"}]}"#),
                       .refused("Blocks did not pass the app's checks: no track"))
        XCTAssertEqual(outcome(409, #"{"error": "too_many_packages"}"#),
                       .refused("You keep the most methods an account can hold. Remove one, then save this."))
        XCTAssertEqual(outcome(503, "not json"), .refused("The method could not be saved. Try again."))
    }

    func testStatesAndPlacesAreWorded() {
        XCTAssertEqual(ShareWords.state("missing"), "Not saved yet")
        XCTAssertEqual(ShareWords.state("different"), "You have another version")
        XCTAssertEqual(ShareWords.place(week: 3, day: "Monday"), "Week 3 · Monday")
        XCTAssertEqual(ShareWords.place(week: nil, day: "Monday"), "Monday")
        XCTAssertEqual(ShareWords.kind("package"), "Shared method")
    }

    func testTheRequestBodiesAreTheServers() {
        XCTAssertEqual(ShareRequest.package("m").body, ["kind": "package", "package_id": "m"])
        XCTAssertEqual(ShareRequest.program.body, ["kind": "program"])
        XCTAssertEqual(ShareRequest.session(key: "3-Monday-0", date: "2026-11-23").body,
                       ["kind": "session", "key": "3-Monday-0", "date": "2026-11-23"])
        XCTAssertEqual(ShareRequest.session(key: "3-Monday-0", date: nil).body, ["kind": "session", "key": "3-Monday-0"])
    }
}
