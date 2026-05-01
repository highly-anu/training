import SwiftUI

private let orderedDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

struct DashboardView: View {
    let api: APIClient
    @EnvironmentObject var programStore: ProgramStore
    @State private var weekIndex = 0

    var body: some View {
        Group {
            if programStore.isLoading {
                ProgressView("Loading program…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let program = programStore.serverProgram?.currentProgram {
                weekScheduleView(program: program)
            } else {
                emptyState
            }
        }
        .navigationTitle("Workouts")
        .task {
            if programStore.serverProgram == nil {
                await programStore.load(api: api)
                weekIndex = currentWeekIndex
            }
        }
        .refreshable {
            await programStore.load(api: api)
            weekIndex = currentWeekIndex
        }
    }

    @ViewBuilder
    private func weekScheduleView(program: GeneratedProgram) -> some View {
        let weeks = program.weeks
        let safeWeekIndex = min(weekIndex, weeks.count - 1)
        let week = weeks[safeWeekIndex]
        let scheduledDays = orderedDays.filter { week.schedule[$0] != nil }
        VStack(spacing: 0) {
            if weeks.count > 1 {
                Picker("Week", selection: $weekIndex) {
                    ForEach(weeks.indices, id: \.self) { i in
                        Text("Week \(weeks[i].weekNumber)\(weeks[i].isDeload ? " · Deload" : "")")
                            .tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            List {
                ForEach(scheduledDays, id: \.self) { day in
                    let sessions = week.schedule[day] ?? []
                    Section(header: Text(day)) {
                        ForEach(sessions.indices, id: \.self) { idx in
                            NavigationLink {
                                WorkoutDetailView(
                                    api: api,
                                    weekIndex: safeWeekIndex,
                                    dayName: day,
                                    sessionIndex: idx,
                                    session: sessions[idx]
                                )
                            } label: {
                                SessionRowView(session: sessions[idx])
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No program loaded")
                .font(.headline)
            Text("Generate a program in the web app first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await programStore.load(api: api)
                    weekIndex = currentWeekIndex
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentWeekIndex: Int {
        guard let startStr = programStore.serverProgram?.programStartDate else { return 0 }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        guard let start = iso.date(from: startStr) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        let idx = max(0, days / 7)
        let count = programStore.serverProgram?.currentProgram?.weeks.count ?? 1
        return min(idx, count - 1)
    }
}

// MARK: - Session row

struct SessionRowView: View {
    let session: ProgramSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.archetype?.name ?? session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.body.weight(.medium))
            HStack(spacing: 8) {
                Text(session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let mins = session.archetype?.durationEstimateMinutes {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(mins) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.isDeload {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("Deload")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
