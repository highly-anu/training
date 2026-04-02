import SwiftUI

struct SetLoggerSheetView: View {
    let exercise: WatchExercise
    let setIndex: Int
    let onConfirm: () -> Void

    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var repsActual: Int
    @State private var rpe: Int

    init(exercise: WatchExercise, setIndex: Int, onConfirm: @escaping () -> Void) {
        self.exercise = exercise
        self.setIndex = setIndex
        self.onConfirm = onConfirm
        _repsActual = State(initialValue: Int(exercise.reps ?? "0") ?? 0)
        _rpe = State(initialValue: exercise.targetRpe ?? 7)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Set \(setIndex + 1)")
                .font(.headline)

            // Reps — Digital Crown input
            VStack(spacing: 2) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(repsActual)")
                    .font(.title2.monospacedDigit().bold())
                    .focusable()
                    .digitalCrownRotation($repsActual, from: 0, through: 99, by: 1, sensitivity: .medium)
            }

            Divider()

            // RPE
            VStack(spacing: 2) {
                Text("RPE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { i in
                        Button {
                            rpe = i * 2   // 1-5 taps → RPE 2,4,6,8,10
                        } label: {
                            Circle()
                                .fill(rpe >= i * 2 ? rpeColor(i) : Color.secondary.opacity(0.3))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Set quality feedback
            if let feedback = qualityFeedback {
                Text(feedback)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button("Done") {
                sessionState.pendingSetLog = WatchSetLog(
                    setIndex: setIndex,
                    repsActual: repsActual,
                    weightKg: exercise.weightKg,
                    rpe: rpe,
                    completed: true
                )
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var qualityFeedback: String? {
        guard let prescribed = exercise.targetRpe else { return nil }
        if rpe >= prescribed + 2 { return "Felt hard — consider lighter load next session." }
        if rpe <= prescribed - 2 { return "Felt easy — ready to progress." }
        return nil
    }

    private func rpeColor(_ level: Int) -> Color {
        switch level {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        default: return .red
        }
    }
}
