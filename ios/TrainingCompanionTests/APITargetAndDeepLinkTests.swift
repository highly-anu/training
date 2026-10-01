import XCTest
@testable import TrainingCompanion

/// The developer's API target and the deep links that let a simulator be
/// driven to any section from the command line.
final class APITargetAndDeepLinkTests: XCTestCase {

    private func scratchDefaults() throws -> UserDefaults {
        let name = "APITargetTests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testResolvePrefersEnvironmentThenOverrideThenProduction() throws {
        let d = try scratchDefaults()
        XCTAssertEqual(APITarget.resolve(environment: [:], defaults: d, production: "https://prod/api"), "https://prod/api")
        APITarget.setOverride("http://localhost:8000/api", defaults: d)
        XCTAssertEqual(APITarget.resolve(environment: [:], defaults: d, production: "https://prod/api"), "http://localhost:8000/api")
        XCTAssertEqual(APITarget.resolve(environment: ["API_BASE_URL": "http://127.0.0.1:9000/api"], defaults: d,
                                         production: "https://prod/api"),
                       "http://127.0.0.1:9000/api", "the launch environment wins for one launch")
        APITarget.setOverride("   ", defaults: d)
        XCTAssertEqual(APITarget.resolve(environment: [:], defaults: d, production: "https://prod/api"), "https://prod/api",
                       "a blank override is no override")
        XCTAssertNil(d.string(forKey: APITarget.overrideDefaultsKey))
    }

    func testLocalMeansThisMachine() {
        XCTAssertTrue(APITarget.isLocal("http://localhost:8000/api"))
        XCTAssertTrue(APITarget.isLocal("http://127.0.0.1:8000/api"))
        XCTAssertTrue(APITarget.isLocal("http://cesars-mac.local:8000/api"))
        XCTAssertFalse(APITarget.isLocal("https://training-api.fly.dev/api"))
        XCTAssertFalse(APITarget.isLocal("not a url"))
    }

    func testDeepLinksRouteToTabsAndSections() throws {
        func parse(_ s: String) -> DeepLink? { DeepLink.parse(URL(string: s)!) }
        XCTAssertEqual(parse("trainingcompanion://today"), .tab(.dashboard))
        XCTAssertEqual(parse("trainingcompanion://session?key=3-Monday-0"), .session("3-Monday-0"),
                       "the widget's link opens that session")
        XCTAssertEqual(parse("trainingcompanion://program"), .tab(.program))
        XCTAssertEqual(parse("trainingcompanion://profile"), .tab(.profile))
        XCTAssertEqual(parse("trainingcompanion://profile?section=equipment"), .profile(.equipment))
        XCTAssertEqual(parse("trainingcompanion://profile?section=nope"), .tab(.profile))
        XCTAssertEqual(parse("trainingcompanion://analytics"), .tab(.analytics))
        XCTAssertEqual(parse("trainingcompanion://analytics?section=program"), .analytics(.program))
        XCTAssertEqual(parse("trainingcompanion://analytics?section=Recovery"), .analytics(.recovery))
        XCTAssertEqual(parse("trainingcompanion://analytics?section=nope"), .tab(.analytics), "an unknown section still opens the tab")
        XCTAssertNil(parse("https://example.com/analytics"), "only our scheme")
        XCTAssertNil(parse("trainingcompanion://settings"), "no such destination")
    }

    func testLaunchEnvironmentRoute() {
        XCTAssertEqual(DeepLink.fromLaunchEnvironment(["TC_ROUTE": "trainingcompanion://analytics?section=program"]),
                       .analytics(.program))
        XCTAssertNil(DeepLink.fromLaunchEnvironment([:]))
        XCTAssertNil(DeepLink.fromLaunchEnvironment(["TC_ROUTE": "not a url at all"]))
    }

    @MainActor
    func testRouterOpensADeepLink() async {
        let router = AppRouter()
        router.open(.analytics(.program))
        XCTAssertEqual(router.tab, .analytics)
        XCTAssertEqual(router.analyticsSection, .program)
        router.open(.tab(.profile))
        XCTAssertEqual(router.tab, .profile)
    }
}
