import SwiftUI

/// Today: readiness, the day's sessions, and the Garmin's menu rows — Week
/// (the days ahead, each to its sessions and steps), Progress (the week, the
/// programme, the methodology's measure) and Sync (the last sync, in words).
/// A rest day, or a day whose sessions are all done, says what tomorrow
/// holds. The words are WatchListText's, the Garmin's.
struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var deepLinkSession: WatchSession? = nil
    /// A page opened by the TC_PAGE launch switch (debug builds only).
    @State private var debugPage: String? = nil

    private var openSessions: [WatchSession] {
        connectivity.todaySessions.filter {
            !connectivity.completedSessionIds.contains($0.sessionId)
        }
    }

    private var doneSessions: [WatchSession] {
        connectivity.todaySessions.filter {
            connectivity.completedSessionIds.contains($0.sessionId)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let readiness = connectivity.readiness {
                    readinessRow(readiness)
                        .listRowBackground(Color.clear)
                }

                if connectivity.todaySessions.isEmpty {
                    restDayRow
                        .listRowBackground(Color.clear)
                }
                if !openSessions.isEmpty {
                    Section {
                        ForEach(openSessions, id: \.sessionId) { session in
                            NavigationLink(destination: ActiveWorkoutView(session: session)) {
                                sessionRow(session, done: false)
                            }
                        }
                    }
                }
                if !doneSessions.isEmpty {
                    Section("Completed") {
                        ForEach(doneSessions, id: \.sessionId) { session in
                            NavigationLink(destination: ActiveWorkoutView(session: session)) {
                                sessionRow(session, done: true)
                            }
                        }
                    }
                }
                // Nothing left to do today: what tomorrow holds.
                if openSessions.isEmpty, let line = WatchListText.tomorrowLine(connectivity.tomorrow) {
                    menuRow("Tomorrow", line, icon: "sunrise")
                }

                Section {
                    if !connectivity.weekAhead.isEmpty {
                        NavigationLink(destination: WeekAheadView()) {
                            menuRow("Week", connectivity.weekTitle, icon: "calendar")
                        }
                    }
                    if let progress = connectivity.progress {
                        NavigationLink(destination: ProgressPageView(progress: progress)) {
                            menuRow("Progress", WatchListText.progressLine(progress), icon: "checkmark.circle")
                        }
                    }
                    Button { connectivity.requestSync() } label: {
                        menuRow("Sync", connectivity.lastSync?.line ?? "today's session",
                                icon: "arrow.triangle.2.circlepath",
                                tint: connectivity.lastSync?.ok == false ? .orange : .secondary)
                    }
                }
            }
            .navigationTitle("Today")
            .navigationDestination(item: $deepLinkSession) { session in
                ActiveWorkoutView(session: session)
            }
            .navigationDestination(isPresented: Binding(get: { debugPage != nil },
                                                        set: { if !$0 { debugPage = nil } })) {
                switch debugPage {
                case "progress": if let p = connectivity.progress { ProgressPageView(progress: p) }
                case "day": if let d = connectivity.weekAhead.first(where: { !$0.sessions.isEmpty }) { DayAheadView(day: d) }
                default: WeekAheadView()
                }
            }
            .onAppear { if debugPage == nil, let p = WatchDebugLaunch.page { debugPage = p } }
        }
        .onChange(of: connectivity.pendingDeepLinkSessionId) { _, _ in resolveDeepLink() }
        .onChange(of: connectivity.todaySessions) { _, _ in resolveDeepLink() }
    }

    private func resolveDeepLink() {
        guard let sessionId = connectivity.pendingDeepLinkSessionId,
              let match = connectivity.todaySessions.first(where: { $0.sessionId == sessionId })
        else { return }
        deepLinkSession = match
        connectivity.pendingDeepLinkSessionId = nil
    }

    // MARK: - Rows

    private func readinessRow(_ info: WatchReadiness) -> some View {
        let color: Color
        switch info.status {
        case "green":  color = .green
        case "yellow": color = .yellow
        default:       color = .red
        }
        // The server's score, the one the phone's Today and the Garmin show.
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("Readiness \(Int(info.score.rounded()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// A label over its line, as the Garmin's menu items read.
    private func menuRow(_ title: String, _ line: String, icon: String,
                         tint: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                Text(line).font(.caption2).foregroundStyle(tint).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: WatchSession, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done
                  ? "checkmark.circle.fill"
                  : ModalityStyle.icon(for: session.modalityId))
                .foregroundStyle(done ? .green : ModalityStyle.color(for: session.modalityId))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.archetypeName)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(done ? .secondary : .primary)
                Text("\(session.estimatedMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restDayRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.100.bolt")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Rest day").font(.headline)
                Text("Recovery is training.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Week

/// The days ahead, from the server's week (`days`): each one's sessions,
/// and each session's steps — read only, as the Garmin's Week menu.
struct WeekAheadView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        List(connectivity.weekAhead) { day in
            if day.sessions.isEmpty {
                dayRow(day)
            } else {
                NavigationLink(destination: DayAheadView(day: day)) { dayRow(day) }
            }
        }
        .navigationTitle(connectivity.weekTitle)
    }

    private func dayRow(_ day: WatchDayAhead) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(WatchListText.dayName(day)).font(.body)
            Text(WatchListText.dayLine(day))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct DayAheadView: View {
    let day: WatchDayAhead

    var body: some View {
        List(day.sessions) { session in
            NavigationLink(destination: StepsListView(session: session)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.archetypeName).font(.body).lineLimit(2)
                    Text(WatchListText.sessionLine(session))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(WatchListText.dayName(day))
    }
}

/// A session's steps and what each asks: "5 Reps @ 100 kg", "Hold :45".
struct StepsListView: View {
    let session: WatchSession

    var body: some View {
        List(Array(session.exercises.enumerated()), id: \.offset) { _, ex in
            VStack(alignment: .leading, spacing: 1) {
                Text(ex.name).font(.footnote).lineLimit(2)
                Text(WatchSteps.preview(ex, session.screen(for: ex)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(session.archetypeName)
    }
}

// MARK: - Progress

/// The week, the programme and the methodology's measure, in the server's
/// words — the sentence the phone's and the web's Today show.
struct ProgressPageView: View {
    let progress: WatchProgress

    var body: some View {
        List(Array(WatchListText.progressRows(progress).enumerated()), id: \.offset) { _, row in
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label).font(.caption2).foregroundStyle(.secondary)
                Text(row.value).font(.footnote)
            }
        }
        .navigationTitle("Progress")
    }
}
