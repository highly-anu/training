import XCTest
@testable import TrainingCompanion

/// A modality and an implement that one of the athlete's own methods brings
/// (its vocabulary.yaml) are served, in no build's tables (roadmap 21.5): the
/// phone reads them from /api/modalities and /api/equipment, a watch session
/// carries its modality's display.
final class ServedVocabularyTests: XCTestCase {
    private let own = "u1234abcd_odd_object_strength"
    private let display: [String: Any] = [
        "label": "Odd object", "short": "Stone", "color": "#ef4444",
        "icon": ["web": "Weight", "ios": "figure.strengthtraining.traditional", "watch": "figure.core.training"],
    ]

    override func tearDown() {
        ClientVocab.remember(served: [:], replacing: true)
        super.tearDown()
    }

    func testAServedDisplayBecomesAModality() throws {
        let modality = try XCTUnwrap(ClientVocab.served(from: display, id: own))
        XCTAssertEqual(modality.label, "Odd object")
        XCTAssertEqual(modality.short, "Stone")
        XCTAssertEqual(modality.hex, 0xef4444)
        XCTAssertEqual(modality.icon, "figure.strengthtraining.traditional")
        XCTAssertEqual(modality.watchIcon, "figure.core.training")
    }

    func testADisplayWithLessStillDraws() throws {
        let modality = try XCTUnwrap(ClientVocab.served(from: ["color": "#0ea5e9"], id: "u1_long_carry"))
        XCTAssertEqual(modality.label, "U1 Long Carry")
        XCTAssertEqual(modality.short, modality.label)
        XCTAssertEqual(modality.watchIcon, modality.icon)
        XCTAssertNil(ClientVocab.served(from: ["label": "No colour"], id: "u1_x"))
        XCTAssertNil(ClientVocab.served(from: ["color": "red"], id: "u1_x"))
    }

    func testARememberedModalityIsFoundByEveryReader() {
        XCTAssertNil(ClientVocab.modality(own))
        XCTAssertTrue(ClientVocab.remember(served: [own: display], replacing: true))
        XCTAssertEqual(ClientVocab.modality(own)?.label, "Odd object")
        XCTAssertEqual(ModalityStyle.label(for: own), "Odd object")
        XCTAssertEqual(ModalityStyle.icon(for: own), "figure.strengthtraining.traditional")
        // The same again changes nothing: no widget is redrawn for it.
        XCTAssertFalse(ClientVocab.remember(served: [own: display], replacing: true))
    }

    func testTheCommonsAreNeverReplacedOrKept() {
        XCTAssertFalse(ClientVocab.remember(served: ["max_strength": ["label": "Mine", "color": "#000000"]], replacing: true))
        XCTAssertEqual(ClientVocab.modality("max_strength")?.label, "Max Strength")
    }

    func testAWholeListReplacesAndASessionAdds() {
        ClientVocab.remember(served: [own: display], replacing: true)
        ClientVocab.remember(served: ["u1_other": ["color": "#10b981"]], replacing: false)
        XCTAssertNotNil(ClientVocab.modality(own))
        XCTAssertNotNil(ClientVocab.modality("u1_other"))
        // The phone's read of the whole list: a deleted method's modality goes.
        XCTAssertTrue(ClientVocab.remember(served: ["u1_other": ["color": "#10b981"]], replacing: true))
        XCTAssertNil(ClientVocab.modality(own))
    }

    func testTheModalitiesRouteIsReadForWhatTheCommonsLack() throws {
        let body: [[String: Any]] = [
            ["id": "max_strength", "name": "Max Strength", "display": ["label": "Max Strength", "color": "#ef4444"]],
            ["id": own, "name": "Odd-object strength", "_package": "u1234abcd_stones", "display": display],
            ["id": "u1_no_display", "name": "Nothing to draw"],
        ]
        let served = ServedVocabulary.modalityDisplays(from: try JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(Array(served.keys), [own])
        XCTAssertEqual(served[own]?["short"] as? String, "Stone")
        XCTAssertTrue(ServedVocabulary.modalityDisplays(from: Data("not json".utf8)).isEmpty)
    }

    func testTheEquipmentRouteIsReadForWhatAMethodBrings() throws {
        let body: [[String: Any]] = [
            ["id": "barbell", "label": "Barbell"],
            ["id": "u1234abcd_stone", "label": "Atlas stone", "package": "u1234abcd_stones"],
            ["id": "u1234abcd_stone", "label": "Atlas stone", "package": "u1234abcd_stones"],
            ["id": "barbell", "label": "Barbell again", "package": "someone"],
        ]
        let items = ServedVocabulary.equipment(from: try JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(items.map(\.id), ["u1234abcd_stone"])
        XCTAssertEqual(items.first?.label, "Atlas stone")
        XCTAssertEqual(items.first?.group, ServedVocabulary.equipmentGroup)
    }

    func testAWatchSessionCarriesItsModalitysDisplay() throws {
        let json = """
        {"sessionId": "1-Monday-0", "modalityId": "\(own)", "archetypeName": "Stone day", "estimatedMinutes": 45,
         "isDeload": false, "exercises": [],
         "modalityDisplay": {"label": "Odd object", "short": "Stone", "color": "#ef4444",
                             "icon": {"web": "Weight", "ios": "figure.strengthtraining.traditional", "watch": "figure.core.training"}}}
        """
        let session = try JSONDecoder().decode(WatchSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.modalityDisplay?.short, "Stone")
        let served = [session].servedModalities
        XCTAssertEqual(ClientVocab.served(from: try XCTUnwrap(served[own]), id: own)?.watchIcon, "figure.core.training")
        // …and survives the relay to the watch, which decodes what the phone encoded.
        let again = try JSONDecoder().decode(WatchSession.self, from: try JSONEncoder().encode(session))
        XCTAssertEqual(again.modalityDisplay, session.modalityDisplay)
    }

    func testASessionOfTheCommonsCarriesNone() throws {
        let json = #"{"sessionId": "1-Monday-0", "modalityId": "max_strength", "archetypeName": "A", "exercises": []}"#
        let session = try JSONDecoder().decode(WatchSession.self, from: Data(json.utf8))
        XCTAssertNil(session.modalityDisplay)
        XCTAssertTrue([session].servedModalities.isEmpty)
    }
}
