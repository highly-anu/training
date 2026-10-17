import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var showThisWeek = false
    @State private var deepLinkSession: WatchSession? = nil

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
            Group {
                if connectivity.todaySessions.isEmpty {
                    restDayView
                        .navigationTitle("Today")
                } else {
                    List {
                        // Readiness indicator (if available)
                        if let readiness = connectivity.readiness {
                            readinessRow(readiness)
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

                        // The week: done of this week's sessions, and the days ahead
                        if !connectivity.weekAhead.isEmpty {
                            weekSection
                        }
                    }
                    .navigationTitle("Today")
                }
            }
            .navigationDestination(item: $deepLinkSession) { session in
                ActiveWorkoutView(session: session)
            }
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

    // MARK: - Readiness Row

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

    // MARK: - Week Section

    /// "Mon", or "Today" for the first day.
    private func dayLabel(_ day: WatchDayAhead) -> String {
        if day.offset == 0 { return "Today" }
        let parse = DateFormatter(); parse.dateFormat = "yyyy-MM-dd"; parse.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parse.date(from: day.date) else { return day.date }
        let show = DateFormatter(); show.setLocalizedDateFormatFromTemplate("EEE")
        return show.string(from: date)
    }

    /// The server's week ahead (today and the six days after it, `days`),
    /// under the count of this program week's sessions done. The phone used
    /// to build a Monday-to-Sunday list of its own from the program.
    private var weekSection: some View {
        Section {
            if showThisWeek {
                ForEach(connectivity.weekAhead) { day in
                    let modalities = day.sessions.map(\.modalityId)
                    HStack(spacing: 8) {
                        Text(dayLabel(day))
                            .font(.caption2)
                            .fontWeight(day.offset == 0 ? .bold : .regular)
                            .foregroundStyle(day.offset == 0 ? .blue : .secondary)
                            .frame(width: 40, alignment: .leading)
                        if modalities.isEmpty {
                            Image(systemName: "battery.100.bolt")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(Array(modalities.prefix(2).enumerated()), id: \.offset) { _, mod in
                                    Circle()
                                        .fill(ModalityStyle.color(for: mod))
                                        .frame(width: 6, height: 6)
                                }
                                if let firstMod = modalities.first {
                                    Image(systemName: ModalityStyle.icon(for: firstMod))
                                        .font(.caption2)
                                        .foregroundStyle(ModalityStyle.color(for: firstMod))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        } header: {
            Button(action: { showThisWeek.toggle() }) {
                HStack {
                    Text("Week")
                        .font(.caption)
                    Spacer()
                    // Done of this program week's sessions, any device — the server's count.
                    if let week = connectivity.weekDone {
                        Text("\(week.done)/\(week.sessions)")
                            .font(.caption2).monospacedDigit()
                    }
                    Image(systemName: showThisWeek ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Session Row

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

    private var restDayView: some View {
        VStack(spacing: 8) {
            Image(systemName: "battery.100.bolt")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Rest")
                .font(.headline)
            Text("Recovery is training.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
