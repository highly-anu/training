import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var showThisWeek = false

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

                    // This Week section
                    if !connectivity.weeklyOverview.isEmpty {
                        thisWeekSection
                    }
                }
                .navigationTitle("Today")
            }
        }
    }

    // MARK: - Readiness Row

    private func readinessRow(_ info: ReadinessInfo) -> some View {
        let color: Color
        switch info.signal {
        case "green":  color = .green
        case "yellow": color = .yellow
        default:       color = .red
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("Readiness")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let hrv = info.hrv {
                Text("HRV \(hrv)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - This Week Section

    private var thisWeekSection: some View {
        let todayName: String = {
            let names = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
            return names[Calendar.current.component(.weekday, from: Date()) - 1]
        }()

        return Section {
            if showThisWeek {
                ForEach(connectivity.weeklyOverview, id: \.dayName) { day in
                    let isToday = day.dayName == todayName
                    HStack(spacing: 8) {
                        Text(String(day.dayName.prefix(3)))
                            .font(.caption2)
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(isToday ? .blue : .secondary)
                            .frame(width: 28, alignment: .leading)
                        if day.sessionCount == 0 {
                            Image(systemName: "battery.100.bolt")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(Array(day.modalityIds.prefix(2).enumerated()), id: \.offset) { _, mod in
                                    Circle()
                                        .fill(ModalityStyle.color(for: mod))
                                        .frame(width: 6, height: 6)
                                }
                                if let firstMod = day.modalityIds.first {
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
                    Text("This Week")
                        .font(.caption)
                    Spacer()
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
