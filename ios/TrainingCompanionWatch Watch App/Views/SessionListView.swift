import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

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
            if connectivity.todaySessions.isEmpty {
                restDayView
                    .navigationTitle("Today")
            } else {
                List {
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
                }
                .navigationTitle("Today")
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

    private var restDayView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Rest Day")
                .font(.headline)
            Text("Recovery is training.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
