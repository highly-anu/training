import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var sessionState: WorkoutSessionState
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        NavigationStack {
            Group {
                if !connectivity.hasProgram {
                    NoProgramView()
                } else if connectivity.todaySessions.isEmpty {
                    restDayView
                } else {
                    sessionList
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private var sessionList: some View {
        List(connectivity.todaySessions, id: \.sessionId) { session in
            NavigationLink(destination: SessionOverviewView(session: session)) {
                SessionCard(session: session)
            }
        }
        .listStyle(.carousel)
    }

    private var restDayView: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Rest Day")
                .font(.headline)
            Text("Recovery is training.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct SessionCard: View {
    let session: WatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.archetypeName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if session.isDeload {
                    Text("Deload")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                Label("\(session.estimatedMinutes) min", systemImage: "clock")
                Label("\(session.exercises.filter { !$0.isMeta }.count) exercises", systemImage: "figure.strengthtraining.traditional")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
