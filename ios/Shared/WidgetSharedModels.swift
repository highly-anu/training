import Foundation

// Lightweight session snapshot for widgets. Shared between:
//   TrainingCompanion (iOS app)
//   TrainingWidgets (iOS widget extension)
//   TrainingCompanionWatch Watch App
//   TrainingWatchWidgets (watchOS widget extension)

struct WidgetSession: Codable, Identifiable {
    /// Same key as AppState.makeSessionKey — e.g. "3-Monday-0"
    let id: String
    let modalityId: String
    let archetypeName: String
    let estimatedMinutes: Int
    let isDeload: Bool
    /// First few exercise names for widget preview rows
    let exerciseNames: [String]
}

struct WidgetTodayData: Codable {
    let date: String            // "YYYY-MM-DD" — the day these sessions belong to
    let sessions: [WidgetSession]
    let updatedAt: Date
}

extension WidgetTodayData {
    static let placeholder = WidgetTodayData(
        date: {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }(),
        sessions: [
            WidgetSession(id: "1-Monday-0", modalityId: "max_strength",
                          archetypeName: "5×5 Strength", estimatedMinutes: 60,
                          isDeload: false, exerciseNames: ["Back Squat", "Press", "Deadlift"]),
            WidgetSession(id: "1-Monday-1", modalityId: "aerobic_base",
                          archetypeName: "Zone 2 Run", estimatedMinutes: 45,
                          isDeload: false, exerciseNames: ["Run"]),
        ],
        updatedAt: Date()
    )
}
