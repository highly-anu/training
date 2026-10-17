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
    @State private var entering: EntryTarget? = nil

    private struct EntryTarget: Identifiable {
        let exercise: WatchExercise
        var id: String { exercise.exerciseId }
    }

    /// The session's scored test steps; empty on any other day.
    private var testSteps: [WatchExercise] { session.exercises.filter { $0.standard != nil } }

    private func value(_ ex: WatchExercise) -> Double? {
        WatchResults.value(ex, sets: sessionState.setLogs[ex.exerciseId] ?? [],
                           outcome: sessionState.outcomes[ex.exerciseId])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)

                Text("Session Complete")
                    .font(.headline)

                statsGrid

                if !testSteps.isEmpty && !saved { resultsSection }

                if saved {
                    Button("Done") { onSave() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                } else if testSteps.isEmpty {
                    Button("Save Workout") { save(decision: nil) }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                } else {
                    // A test day: the answer rides in the upload; the server
                    // makes each a result only then.
                    Button("Save Results") { save(decision: "save") }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    Button("Not a test") { save(decision: "dismiss") }
                        .buttonStyle(.bordered)

                    Button("Discard", role: .destructive) { onDiscard() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .sheet(item: $entering) { target in
            ResultEntryView(exercise: target.exercise, initial: value(target.exercise) ?? 0) { v in
                sessionState.setResult(target.exercise, value: v)
            }
        }
    }

    private func save(decision: String?) {
        saved = true
        sessionState.resultDecision = decision
        if let summary = workoutManager.buildSummary(startedAt: startedAt) {
            connectivity.sendWorkoutSummary(summary)
        }
    }

    /// Each standard the session tested, with what the watch captured; tap one
    /// to enter or correct it (the reps of a timed step are the athlete's count).
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Results").font(.caption2).foregroundStyle(.secondary)
            ForEach(testSteps, id: \.exerciseId) { ex in
                Button { entering = EntryTarget(exercise: ex) } label: {
                    HStack {
                        Text(ex.standard?.name ?? ex.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(value(ex).map { WatchResults.text(ex, value: $0) } ?? "Enter")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(value(ex) == nil ? .yellow : .primary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
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

/// One test result, entered with the crown: a count (reps, rounds), seconds
/// for a hold, or a clock as minutes and seconds.
struct ResultEntryView: View {
    let exercise: WatchExercise
    let initial: Double
    let onDone: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 0

    private var isClock: Bool { exercise.standard?.result == "duration" }
    private var step: Double { exercise.standard?.result == "distance" ? 0.01 : 1 }

    var body: some View {
        VStack(spacing: 6) {
            Text(exercise.standard?.name ?? exercise.name).font(.caption).lineLimit(1)
            Text(WatchResults.text(exercise, value: value))
                .font(.title2.monospacedDigit().bold())
                .focusable()
                .digitalCrownRotation($value, from: 0, through: isClock ? 7200 : 999,
                                      by: step, sensitivity: .medium, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            HStack {
                Button("−") { value = max(0, value - (isClock ? 1 : step)) }
                Button("+") { value += isClock ? 1 : step }
            }
            .font(.title3)
            Button("Done") { onDone(value); dismiss() }
                .buttonStyle(.borderedProminent)
                .disabled(value <= 0)
        }
        .onAppear { value = initial }
    }
}
