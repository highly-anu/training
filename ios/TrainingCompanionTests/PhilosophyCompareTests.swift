import XCTest
@testable import TrainingCompanion

/// The comparison's models against what the server sends:
/// `data/philosophy_compare_fixture.json` is `GET /philosophies/compare` for
/// three philosophies and `POST /philosophies/<id>/for-me` for each on a fixed
/// profile, written by `test_explore_compare.py --write` (which fails when the
/// routes stop answering it).
final class PhilosophyCompareTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private struct Recorded: Decodable {
        let compare: PhilosophyCompare
        let forMe: [String: PhilosophyForMe]
    }

    private func recorded() throws -> Recorded {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("data/philosophy_compare_fixture.json"))
        return try JSONDecoder().decode(Recorded.self, from: data)
    }

    func testTheServersComparisonDecodes() throws {
        let doc = try recorded().compare
        XCTAssertEqual(doc.ids, ["uphill_athlete", "gym_jones", "horsemen_gpp"])
        XCTAssertEqual(doc.philosophies.map(\.id), doc.ids, "every column, in the order asked")
        XCTAssertGreaterThan(doc.trackWeeks, 0)
        XCTAssertEqual(doc.pairs.count, 3, "every pair once")
        XCTAssertTrue(doc.isSame("daysPerWeek"))
        XCTAssertFalse(doc.isSame("weeks"))
        XCTAssertFalse(doc.isSame("no such row"), "an unknown row is never hidden")
        let uphill = try XCTUnwrap(doc.philosophies.first)
        XCTAssertNotNil(uphill.primaryTrack)
        XCTAssertFalse(uphill.mix.isEmpty)
        XCTAssertFalse(uphill.intensity.isEmpty)
    }

    func testAColumnShowsItsOwnThenWhatItSharesWithOne() throws {
        let doc = try recorded().compare
        for g in doc.philosophies {
            let mine = Set(g.equipment.map(\.id))
            let shown = Set(doc.equipment.column(g.id).map(\.id)).union(doc.equipment.shared.map(\.id))
            XCTAssertEqual(shown, mine, "\(g.id): shared + its column is all it asks for")
        }
    }

    func testForMeSaysWhyOneCannotRunAndWhatOneGives() throws {
        let forMe = try recorded().forMe
        let refused = try XCTUnwrap(forMe["uphill_athlete"])
        XCTAssertFalse(refused.feasible)
        XCTAssertFalse(refused.reasons.isEmpty)
        XCTAssertNil(refused.perWeek)
        let runs = try XCTUnwrap(forMe["horsemen_gpp"])
        XCTAssertTrue(runs.feasible)
        XCTAssertEqual(runs.weeks, runs.ofWeeks)
        XCTAssertNotNil(runs.perWeek)
        XCTAssertFalse(runs.missingEquipment.isEmpty, "the fixture's kit is a bell and a bar")
        XCTAssertNotNil(runs.intensity?["zone3_pct"], "the glance's bands")
    }

    func testAnOlderOrThinnerAnswerStillDecodes() throws {
        let json = #"{"ids":["a","b"],"philosophies":[]}"#
        let doc = try JSONDecoder().decode(PhilosophyCompare.self, from: Data(json.utf8))
        XCTAssertTrue(doc.philosophies.isEmpty)
        XCTAssertTrue(doc.pairs.isEmpty)
        XCTAssertTrue(doc.equipment.shared.isEmpty)
        XCTAssertEqual(doc.trackWeeks, 0)
    }

    func testShortNames() {
        XCTAssertEqual(PhilosophyCompareView.short("Uphill Athlete — Steve House & Scott Johnston"), "Uphill Athlete")
        XCTAssertEqual(PhilosophyCompareView.short("Gym Jones / Mark Twight"), "Gym Jones")
        XCTAssertEqual(PhilosophyCompareView.short("CrossFit (Glassman)"), "CrossFit")
    }

    func testTheDeepLink() {
        func parse(_ s: String) -> DeepLink? { DeepLink.parse(URL(string: s)!) }
        XCTAssertEqual(parse("trainingcompanion://compare?ids=a,b"), .compare(["a", "b"]))
        XCTAssertEqual(parse("trainingcompanion://compare?ids=a,%20b,a,c"), .compare(["a", "b", "c"]))
        XCTAssertNil(parse("trainingcompanion://compare?ids=a"), "two to three")
        XCTAssertNil(parse("trainingcompanion://compare?ids=a,b,c,d"))
    }

    @MainActor
    func testTheRouterHoldsTheComparison() async {
        let router = AppRouter()
        router.open(.compare(["a", "b"]))
        XCTAssertEqual(router.pendingCompare, ["a", "b"])
    }
}
