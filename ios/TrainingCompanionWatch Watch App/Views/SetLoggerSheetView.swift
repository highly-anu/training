import SwiftUI

struct SetLoggerSheetView: View {
    let exercise: WatchExercise
    let setIndex: Int
    let exerciseIndex: Int
    let onDone: (WatchSetLog) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var repsDouble: Double
    @State private var weightKg: Double
    @State private var rpeDouble: Double = 7
    @State private var page = 0

    private var repsActual: Int { Int(repsDouble) }
    private var rpe: Int { Int(rpeDouble) }

    init(exercise: WatchExercise, setIndex: Int, exerciseIndex: Int,
         onDone: @escaping (WatchSetLog) -> Void) {
        self.exercise = exercise
        self.setIndex = setIndex
        self.exerciseIndex = exerciseIndex
        self.onDone = onDone
        _repsDouble = State(initialValue: Double(exercise.reps.flatMap(Int.init) ?? 5))
        _weightKg   = State(initialValue: exercise.weightKg ?? 0)
    }

    var body: some View {
        TabView(selection: $page) {
            repsPage.tag(0)
            rpePage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var repsPage: some View {
        VStack(spacing: 6) {
            Text("Set \(setIndex + 1) — Reps")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(repsActual)")
                .font(.title.bold().monospacedDigit())
                .focusable()
                .digitalCrownRotation($repsDouble,
                                      from: 1, through: 30, by: 1,
                                      sensitivity: .medium,
                                      isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            if weightKg > 0 {
                Text("\(String(format: "%.1f", weightKg)) kg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .focusable()
                    .digitalCrownRotation($weightKg,
                                          from: 0, through: 500, by: 2.5,
                                          sensitivity: .low)
            }
            Button("RPE →") { withAnimation { page = 1 } }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.caption)
        }
    }

    private var rpePage: some View {
        VStack(spacing: 6) {
            Text("RPE")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(rpe)/10")
                .font(.title.bold())
                .focusable()
                .digitalCrownRotation($rpeDouble,
                                      from: 1, through: 10, by: 1,
                                      sensitivity: .medium,
                                      isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            rpeLabelText(rpe: rpe)
            Button("Done") {
                let log = WatchSetLog(
                    setIndex: setIndex,
                    repsActual: repsActual,
                    weightKg: weightKg > 0 ? weightKg : nil,
                    rpe: rpe,
                    completed: true,
                    durationSeconds: nil
                )
                onDone(log)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private func rpeLabelText(rpe: Int) -> some View {
        let label: String
        if rpe <= 5      { label = "Easy" }
        else if rpe == 6 { label = "Moderate" }
        else if rpe == 7 { label = "Hard" }
        else if rpe == 8 { label = "Very Hard" }
        else if rpe == 9 { label = "Near Max" }
        else             { label = "Max Effort" }
        return Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
