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
    /// Written by the watch app (nil from the phone and from older data): the
    /// ids of today's sessions done on any device, this program week's sessions
    /// done and in all (the server's `progress.week`), and readiness 0–100.
    var completedIds: [String]? = nil
    var weekDone: Int? = nil
    var weekSessions: Int? = nil
    var readinessScore: Int? = nil
    var readinessSignal: String? = nil

    /// Every one of today's sessions is done.
    var allDone: Bool {
        !sessions.isEmpty && sessions.allSatisfy { (completedIds ?? []).contains($0.id) }
    }
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

// MARK: - Home-screen: week overview and status row

/// The program week, Monday to Sunday — the web's Week overview strip, for
/// the full-width Week widget. Written by the phone (AppState.writeHomeWidgets)
/// whenever the program, a completion, readiness or the analytics change.
struct WidgetWeekData: Codable {
    struct Session: Codable, Hashable {
        let modalityId: String
        let name: String
        let minutes: Int
        let done: Bool
    }
    struct Day: Codable, Hashable {
        let dayName: String          // "Monday"
        let date: String             // yyyy-MM-dd
        let sessions: [Session]
    }
    let updatedAt: Date
    let weekNumber: Int
    let totalWeeks: Int
    let phase: String?
    let isDeload: Bool
    let days: [Day]
}

/// The status row — Today · Readiness · Adherence · Progress — the web's four
/// cards in one full-width widget. Every number is the server's (readiness,
/// the scorecard, the methodology's headline sentence); the phone only copies.
struct WidgetStatusData: Codable {
    struct Today: Codable {
        let date: String
        let sessionCount: Int
        let doneCount: Int
        let firstName: String?
        let firstModality: String?
        let minutes: Int?
    }
    struct Readiness: Codable {
        let score: Int
        let status: String           // green | yellow | red
    }
    struct Adherence: Codable {
        let pct: Int
        let verdict: String          // on_plan | off_plan | not_started
        let weekDone: Int?
        let weekDue: Int?
    }
    struct Progress: Codable {
        let label: String
        let text: String?            // nil until a measure has data
        let status: String
    }
    let updatedAt: Date
    let today: Today?
    let readiness: Readiness?
    let adherence: Adherence?
    let progress: Progress?
}
