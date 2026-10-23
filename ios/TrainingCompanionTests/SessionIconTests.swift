import XCTest
@testable import TrainingCompanion

/// A planned session leads with its workout icon (the server's `icon`, from
/// its main exercise) and keeps its modality icon when it has none
/// (design-system §6.40). The icon is derived by the server on every read, so
/// it reaches the phone in the program's extras and the watch's day.
final class SessionIconTests: XCTestCase {
    func testIconElseModality() {
        XCTAssertEqual(SessionIcon.symbol(icon: "kettlebell", modality: "power"), AppSymbol.kettlebell)
        XCTAssertEqual(SessionIcon.symbol(icon: nil, modality: "power"), ModalityStyle.icon(for: "power"))
        // An id this build has no glyph for draws the modality, never nothing.
        XCTAssertEqual(SessionIcon.symbol(icon: "kettlebell.swing", modality: "movement_skill"),
                       ModalityStyle.icon(for: "movement_skill"))
    }

    func testProgramSessionReadsItsIcon() throws {
        let json = #"{"modality": "power", "archetype": null, "is_deload": false, "exercises": [], "icon": "kettlebell"}"#
        let session = try JSONDecoder().decode(ProgramSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.icon, "kettlebell")
        let bare = try JSONDecoder().decode(ProgramSession.self, from: Data(#"{"modality": "power"}"#.utf8))
        XCTAssertNil(bare.icon)
    }

    func testWatchSessionDecodesAndRelaysItsIcon() throws {
        let json = #"{"sessionId": "1-Monday-0", "modalityId": "power", "archetypeName": "Swing", "icon": "kettlebell"}"#
        let session = try JSONDecoder().decode(WatchSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.icon, "kettlebell")
        let again = try JSONDecoder().decode(WatchSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(again.icon, "kettlebell")
    }

    func testLinkSessionDecodesItsIcon() throws {
        let json = #"{"key": "1-Monday-0", "date": "2026-10-19", "modality": "power", "icon": "kettlebell", "name": "Swing", "historical": false}"#
        let session = try JSONDecoder().decode(LinkSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.icon, "kettlebell")
    }
}
