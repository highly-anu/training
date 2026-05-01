import Foundation

@MainActor
final class ProgramStore: ObservableObject {
    @Published var serverProgram: ServerProgram? = nil
    @Published var isLoading = false
    @Published var error: String? = nil

    func load(api: APIClient) async {
        isLoading = true
        error = nil
        do {
            serverProgram = try await api.fetchProgram()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func moveSession(weekIndex: Int, fromDay: String, toDay: String,
                     sessionIndex: Int, api: APIClient) {
        guard var sp = serverProgram,
              var program = sp.currentProgram else { return }
        var weeks = program.weeks
        guard weekIndex < weeks.count else { return }
        var week = weeks[weekIndex]
        var fromSessions = week.schedule[fromDay] ?? []
        guard sessionIndex < fromSessions.count else { return }
        let session = fromSessions.remove(at: sessionIndex)
        var toSessions = week.schedule[toDay] ?? []
        toSessions.append(session)
        var schedule = week.schedule
        schedule[fromDay] = fromSessions
        schedule[toDay] = toSessions
        week = ProgramWeek(weekNumber: week.weekNumber,
                           isDeload: week.isDeload,
                           phase: week.phase,
                           schedule: schedule)
        weeks[weekIndex] = week
        program = GeneratedProgram(weeks: weeks)
        sp = ServerProgram(currentProgram: program,
                           programStartDate: sp.programStartDate,
                           eventDate: sp.eventDate,
                           sourceGoalIds: sp.sourceGoalIds)
        serverProgram = sp
        Task { try? await saveProgram(api: api) }
    }

    func replaceSession(weekIndex: Int, day: String, sessionIndex: Int,
                        session: ProgramSession, api: APIClient) {
        guard var sp = serverProgram,
              var program = sp.currentProgram else { return }
        var weeks = program.weeks
        guard weekIndex < weeks.count else { return }
        var week = weeks[weekIndex]
        var sessions = week.schedule[day] ?? []
        guard sessionIndex < sessions.count else { return }
        sessions[sessionIndex] = session
        var schedule = week.schedule
        schedule[day] = sessions
        week = ProgramWeek(weekNumber: week.weekNumber,
                           isDeload: week.isDeload,
                           phase: week.phase,
                           schedule: schedule)
        weeks[weekIndex] = week
        program = GeneratedProgram(weeks: weeks)
        sp = ServerProgram(currentProgram: program,
                           programStartDate: sp.programStartDate,
                           eventDate: sp.eventDate,
                           sourceGoalIds: sp.sourceGoalIds)
        serverProgram = sp
        Task { try? await saveProgram(api: api) }
    }

    private func saveProgram(api: APIClient) async throws {
        guard let sp = serverProgram else { return }
        let payload = UserProgramSavePayload(
            currentProgram: sp.currentProgram,
            programStartDate: sp.programStartDate,
            eventDate: sp.eventDate,
            sourceGoalIds: sp.sourceGoalIds,
            sourceGoalWeights: [:]
        )
        try await api.saveProgram(payload)
    }
}
