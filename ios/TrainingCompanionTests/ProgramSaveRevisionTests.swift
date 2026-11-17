import XCTest
@testable import TrainingCompanion

/// Every save is checked against the revision the copy was read at, and the
/// PUT answers the new one. The phone kept the revision it loaded, so the
/// second edit since the program was read — moving tomorrow's session to
/// today after any other edit — was refused as stale, and the reload put the
/// session back. A stub server here refuses a stale save as the real one does.
/// `async` for AppState's isolated deinit (CurrentWeekIndexTests explains).
final class ProgramSaveRevisionTests: XCTestCase {

    private var storedOverride: String?

    override func setUp() {
        super.setUp()
        // A local target: no sign-in, and the stub answers it.
        storedOverride = UserDefaults.standard.string(forKey: APITarget.overrideDefaultsKey)
        APITarget.setOverride("http://localhost:9/api")
        StubProgramServer.reset(revision: "r0")
        URLProtocol.registerClass(StubProgramServer.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubProgramServer.self)
        APITarget.setOverride(storedOverride)
        super.tearDown()
    }

    private func session(_ modality: String) -> ProgramSession {
        ProgramSession(modality: modality, archetype: nil, isDeload: false, exercises: [])
    }

    @MainActor
    private func makeState() -> AppState {
        let state = AppState()
        state.api = APIClient(auth: AuthManager())
        let week = ProgramWeek(weekNumber: 1, weekInPhase: 1, isDeload: false, phase: "base",
                               schedule: ["Monday": [session("max_strength")],
                                          "Wednesday": [session("aerobic_base")],
                                          "Friday": [session("mobility")]])
        state.serverProgram = ServerProgram(currentProgram: GeneratedProgram(weeks: [week]),
                                            programStartDate: "2026-11-02", eventDate: nil,
                                            sourceGoalIds: [], revision: "r0")
        return state
    }

    @MainActor
    func testTwoEditsInARowBothSave() async {
        let state = makeState()
        state.moveSession(weekIndex: 0, fromDay: "Friday", toDay: "Saturday", sessionIndex: 0)
        await state.programSaveTask?.value
        XCTAssertEqual(state.serverProgram?.revision, "r1", "the PUT's revision is kept")

        state.moveSession(weekIndex: 0, fromDay: "Wednesday", toDay: "Tuesday", sessionIndex: 0)
        await state.programSaveTask?.value
        XCTAssertNil(state.programSaveConflict)
        XCTAssertEqual(StubProgramServer.saves, 2)
        XCTAssertEqual(state.serverProgram?.revision, "r2")
        let schedule = state.serverProgram?.currentProgram?.weeks[0].schedule
        XCTAssertEqual(schedule?["Tuesday"]?.map(\.modality), ["aerobic_base"], "the move stays")
        XCTAssertEqual(schedule?["Wednesday"]?.count ?? 0, 0)
    }

    @MainActor
    func testEditsInQuickSuccessionSaveOneAfterTheOther() async {
        let state = makeState()
        state.moveSession(weekIndex: 0, fromDay: "Friday", toDay: "Saturday", sessionIndex: 0)
        state.moveSession(weekIndex: 0, fromDay: "Wednesday", toDay: "Tuesday", sessionIndex: 0)
        await state.programSaveTask?.value
        XCTAssertNil(state.programSaveConflict, "the second save waits for the first's revision")
        XCTAssertEqual(StubProgramServer.rejected, 0)
        XCTAssertEqual(state.serverProgram?.currentProgram?.weeks[0].schedule["Tuesday"]?.count, 1)
    }
}

/// PUT /user/program as the server answers it: 409 for a stale base revision,
/// else saved with a new revision.
final class StubProgramServer: URLProtocol {
    nonisolated(unsafe) static var revision = "r0"
    nonisolated(unsafe) static var saves = 0
    nonisolated(unsafe) static var rejected = 0

    static func reset(revision: String) {
        self.revision = revision; saves = 0; rejected = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "localhost" && request.url?.port == 9
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let base = json?["baseRevision"] as? String
        var status = 200
        var answer: [String: Any]
        if request.httpMethod == "PUT", request.url?.path == "/api/user/program" {
            if base != Self.revision {
                Self.rejected += 1
                status = 409
                answer = ["saved": false, "detail": "stale_revision", "currentRevision": Self.revision]
            } else {
                Self.saves += 1
                Self.revision = "r\(Self.saves)"
                answer = ["saved": true, "revision": Self.revision, "programVersionId": "v\(Self.saves)"]
            }
        } else {
            status = 404
            answer = [:]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
