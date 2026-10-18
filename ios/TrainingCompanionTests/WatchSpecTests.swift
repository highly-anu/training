import XCTest
@testable import TrainingCompanion

/// The Apple Watch's screens against `data/watch_fixtures.json` — the same
/// cases the Garmin's SpecRenderer runs (garmin/core/test/SpecFixtures.mc,
/// generated from that file) — so the two watches draw one step alike.
@MainActor
final class WatchSpecTests: XCTestCase {
    private struct Fixtures: Decodable { let cases: [Case] }
    private struct Case: Decodable {
        let name: String
        let exercise: WatchExercise
        let screen: WatchScreenSpec?
        let state: WatchStepState
        let expect: Expect
    }
    private struct Expect: Decodable {
        let title: String
        let a: [String]?
        let b: [String]?
        let gauge: [String]?
        let lines: [String?]
        let lap: String
        let outcome: String
    }

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func cases() throws -> [Case] {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("data/watch_fixtures.json"))
        return try JSONDecoder().decode(Fixtures.self, from: data).cases
    }

    /// The screen a case's step is drawn with, as a session would resolve it.
    private func screen(_ c: Case) -> WatchScreen {
        WatchScreen.forExercise(slotType: c.exercise.slotType, key: c.screen == nil ? nil : "s0",
                                screens: c.screen.map { ["s0": $0] })
    }

    private func pair(_ f: WatchSpecText.Field?) -> [String]? { f.map { [$0.label, $0.value] } }

    func testEveryCaseDrawsItsPage() throws {
        let all = try cases()
        XCTAssertGreaterThan(all.count, 20)
        for c in all {
            let s = screen(c), ex = c.exercise, st = c.state
            XCTAssertEqual(WatchSpecText.title(ex, s, st), c.expect.title, "\(c.name): title")
            XCTAssertEqual(pair(WatchSpecText.fieldA(ex, s, st)), c.expect.a, "\(c.name): field a")
            XCTAssertEqual(pair(WatchSpecText.fieldB(ex, s, st)), c.expect.b, "\(c.name): field b")
            XCTAssertEqual(pair(WatchSpecText.gauge(ex, s, st)), c.expect.gauge, "\(c.name): gauge")
            let lines = WatchSpecText.lines(ex, s, st)
            XCTAssertEqual([lines.0, lines.1], c.expect.lines, "\(c.name): lines")
            XCTAssertEqual(s.lap.rawValue, c.expect.lap, "\(c.name): the spec's LAP")
            XCTAssertEqual(WatchSpecText.lap(ex, s, st).rawValue, c.expect.outcome, "\(c.name): what LAP does")
        }
    }

    /// Every id in the vocabulary is drawn by some case — an id added to
    /// watch_vocabulary.json needs a case here as well as a Swift branch (the
    /// exhaustive switches) and a Monkey C one.
    func testTheCasesCoverTheVocabulary() throws {
        let screens = try cases().map(screen)
        let templates = Set(screens.map(\.template))
        let fields = Set(screens.flatMap { [$0.a, $0.b, $0.gauge].compactMap { $0 } })
        let titles = Set(screens.flatMap(\.title))
        let lines = Set(screens.compactMap(\.lines))
        let actions = Set(screens.map(\.lap))
        XCTAssertEqual(templates, Set(WatchVocab.Template.allCases), "templates")
        XCTAssertEqual(fields, Set(WatchVocab.Field.allCases), "fields")
        XCTAssertEqual(titles, Set(WatchVocab.TitlePart.allCases), "title parts")
        XCTAssertEqual(lines, Set(WatchVocab.Line.allCases), "lines")
        XCTAssertEqual(actions, Set(WatchVocab.Action.allCases), "actions")

        var behaviours = Set<WatchVocab.Behaviour>()
        for b in screens.map(\.behaviours) {
            if b.sideTracked != nil { behaviours.insert(.sideTracked) }
            if b.cumulativeTarget != nil { behaviours.insert(.cumulativeTarget) }
            if b.ladderPeak != nil { behaviours.insert(.ladder) }
            if b.loadWave != nil { behaviours.insert(.loadWave) }
            if b.metronomeRpm != nil { behaviours.insert(.metronomeRpm) }
        }
        XCTAssertEqual(behaviours, Set(WatchVocab.Behaviour.allCases), "behaviours")
    }

    /// A real day's screens decode and resolve: the server-written fixture's
    /// BJJ class runs both its blocks on the package's round timer.
    func testTheServersScreensResolve() throws {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("data/watch_day_fixture.json"))
        let day = try JSONDecoder().decode(WatchDay.self, from: data)
        let bjj = try XCTUnwrap(day.sessions?.first { $0.archetypeName == "BJJ Class" })
        XCTAssertNotNil(bjj.screens?["s0"])
        XCTAssertEqual(bjj.exercises.map { bjj.screen(for: $0).template }, [.roundTimer, .roundTimer])
        let squat = try XCTUnwrap(day.sessions?.first?.exercises.first)
        let s = try XCTUnwrap(day.sessions?.first).screen(for: squat)
        XCTAssertEqual(s.template, .sets)
        XCTAssertEqual(s.lines, .lastThenNext)
    }

    func testLaddersClimbAndComeDown() {
        XCTAssertEqual(Ladder.rung(0, peak: 20), 1)
        XCTAssertEqual(Ladder.rung(19, peak: 20), 20)
        XCTAssertEqual(Ladder.rung(20, peak: 20), 19)
        XCTAssertEqual(Ladder.rung(60, peak: 20), 1)
        XCTAssertEqual(Ladder.total(3, peak: 20), 6)
        XCTAssertEqual(Ladder.total(5, peak: 3), 1 + 2 + 3 + 2 + 1)
    }

    func testTimesAndWeightsReadLikeTheGarmins() {
        XCTAssertEqual(WatchSpecText.mmss(247), "4:07")
        XCTAssertEqual(WatchSpecText.mmss(3753), "1:02:33")
        XCTAssertEqual(WatchSpecText.mmss(-5), "0:00")
        XCTAssertEqual(WatchSpecText.secs(47), ":47")
        XCTAssertEqual(WatchSpecText.secs(75), "1:15")
        XCTAssertEqual(WatchSpecText.kg(82.5), "82.5")
        XCTAssertEqual(WatchSpecText.kg(80), "80")
    }
}
