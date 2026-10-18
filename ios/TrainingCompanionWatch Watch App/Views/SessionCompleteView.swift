import SwiftUI

struct SessionCompleteView: View {
    let session: WatchSession
    let startedAt: Date
    let onSave: () -> Void
    let onDiscard: () -> Void

    @EnvironmentObject var sessionState: WorkoutSessionState
    @EnvironmentObject var workoutManager: WorkoutManager

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

                // The package's summary pages, in its order (the Garmin's
                // SummaryView): what the session was, its heart rate, and
                // what each step logged.
                ForEach(WatchSummaryText.pages(session), id: \.self) { page in
                    switch page {
                    case "heart_rate": heartRatePage
                    case "exercises": exercisesPage
                    default: summaryPage
                    }
                }

                if !testSteps.isEmpty { resultsSection }

                if testSteps.isEmpty {
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
                }
                Button("Discard", role: .destructive) { onDiscard() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
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

    /// The answer goes into the summary `onSave` builds and sends, once.
    private func save(decision: String?) {
        sessionState.resultDecision = decision
        onSave()
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

    private func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    /// Time, sets, and the volume lifted — or the calories where nothing was.
    private var summaryPage: some View {
        let volume = WatchSummaryText.volumeKg(session, sessionState.setLogs)
        return VStack(spacing: 4) {
            pageTitle("SUMMARY")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    statCell(value: durationString, label: "Time")
                    statCell(value: "\(WatchSummaryText.totalSets(sessionState.setLogs))", label: "Sets")
                }
                GridRow {
                    if volume > 0 {
                        statCell(value: "\(Int(volume.rounded()))", label: "Volume kg")
                    } else {
                        statCell(value: "\(sessionState.calories)", label: "kcal")
                    }
                    statCell(value: "\(sessionState.completedExerciseIds.count)", label: "Exercises")
                }
            }
            .font(.caption)
        }
    }

    /// Average and maximum, and the minutes in each zone.
    private var heartRatePage: some View {
        let zones = workoutManager.zoneSeconds()
        let longest = max(zones.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 4) {
            pageTitle("HEART RATE")
            HStack {
                statCell(value: sessionState.avgHR > 0 ? "\(sessionState.avgHR)" : "--", label: "Avg.")
                Spacer()
                statCell(value: sessionState.peakHR > 0 ? "\(sessionState.peakHR)" : "--", label: "Max.")
            }
            ForEach(Array(zones.enumerated()).reversed(), id: \.offset) { i, secs in
                if secs > 0 {
                    HStack(spacing: 6) {
                        Text("Z\(i + 1)").font(.caption2).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                        Capsule().fill(HRZoneCalculator.color(for: i + 1))
                            .frame(width: max(4, 90 * CGFloat(secs) / CGFloat(longest)), height: 6)
                        Text(WatchSpecText.mmss(secs)).font(.caption2.monospacedDigit())
                    }
                }
            }
        }
    }

    /// Each step and what it logged ("3x5 @ 100"), dim where nothing was.
    private var exercisesPage: some View {
        VStack(alignment: .leading, spacing: 2) {
            pageTitle("EXERCISES")
            ForEach(Array(WatchSummaryText.exerciseLines(session, logs: sessionState.setLogs,
                                                         outcomes: sessionState.outcomes).enumerated()),
                    id: \.offset) { _, line in
                Text(line.name + (line.logged.map { "  \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(line.logged == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// The workout's own time, as the Garmin's summary shows it — the
    /// engine's elapsed seconds, which stop when the workout ends; the wall
    /// clock since the start only if the engine never ticked.
    private var durationString: String {
        let secs = sessionState.elapsedSeconds > 0
            ? sessionState.elapsedSeconds : Int(Date().timeIntervalSince(startedAt))
        return WatchSpecText.mmss(secs)
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
