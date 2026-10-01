import XCTest
@testable import TrainingCompanion

/// Program ▸ Current explains the methodology it was generated from.
final class ProgramMethodologyTests: XCTestCase {

    private func card(_ id: String, _ name: String) throws -> PhilosophyCard {
        try JSONDecoder().decode(PhilosophyCard.self, from: #"{"id": "\#(id)", "name": "\#(name)"}"#.data(using: .utf8)!)
    }

    @MainActor
    func testProgramMethodologiesFollowTheEnvelopeAndSkipTheBlendMarker() async throws {
        let appState = AppState()
        appState.philosophies = [try card("wildman_kettlebell", "Wildman Kettlebell"),
                                 try card("starting_strength", "Starting Strength / Mark Rippetoe")]
        appState.serverProgram = ServerProgram(currentProgram: nil, programStartDate: nil, eventDate: nil,
                                               sourceGoalIds: ["starting_strength", "wildman_kettlebell", "_blended", "unknown"])
        XCTAssertEqual(appState.programMethodologies().map(\.name),
                       ["Starting Strength / Mark Rippetoe", "Wildman Kettlebell"],
                       "the envelope's order, without the marker or an id the catalog does not know")

        appState.serverProgram = nil
        XCTAssertEqual(appState.programMethodologies().count, 0)
        appState.serverProgram = ServerProgram(currentProgram: nil, programStartDate: nil, eventDate: nil, sourceGoalIds: ["starting_strength"])
        appState.philosophies = []
        XCTAssertEqual(appState.programMethodologies().count, 0, "nothing to show until the catalog is loaded")
    }
}
