import SwiftUI

struct SessionCompleteView: View {
    let session: WatchSession
    let startedAt: Date
    let onSave: () -> Void
    let onDiscard: () -> Void

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)

                Text("Session Complete")
                    .font(.headline)

                statsGrid

                if saved {
                    Button("Done") { onSave() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                } else {
                    Button("Save Workout") {
                        saved = true
                        if let summary = workoutManager.buildSummary(startedAt: startedAt) {
                            connectivity.sendWorkoutSummary(summary)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button("Discard", role: .destructive) { onDiscard() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                statCell(value: durationString, label: "Duration")
                statCell(value: sessionState.avgHR > 0 ? "\(sessionState.avgHR)" : "—",
                         label: "Avg HR")
            }
            GridRow {
                statCell(value: sessionState.peakHR > 0 ? "\(sessionState.peakHR)" : "—",
                         label: "Peak HR")
                statCell(value: "\(sessionState.calories)",
                         label: "kcal")
            }
            GridRow {
                statCell(value: "\(sessionState.completedExerciseIds.count)",
                         label: "Exercises")
                statCell(value: "\(sessionState.setLogs.values.flatMap { $0 }.count)",
                         label: "Sets")
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var durationString: String {
        let secs = Int(Date().timeIntervalSince(startedAt))
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}
