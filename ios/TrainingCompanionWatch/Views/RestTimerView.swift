import SwiftUI

struct RestTimerView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var restState: (exerciseIndex: Int, completedSet: Int, remaining: Int) {
        if case .resting(let ei, let cs, let rem) = sessionState.phase {
            return (ei, cs, rem)
        }
        return (0, 0, 60)
    }

    private var nextExercise: WatchExercise? {
        guard let session = sessionState.session else { return nil }
        let nextIdx = restState.exerciseIndex
        return session.exercises[safe: nextIdx]
    }

    private var totalRest: Int {
        nextExercise?.restSeconds ?? 60
    }

    private var progress: Double {
        guard totalRest > 0 else { return 1 }
        return 1.0 - Double(restState.remaining) / Double(totalRest)
    }

    private var isRecovering: Bool {
        guard let ex = nextExercise,
              let upper = ex.prescribedZoneUpper else { return false }
        let maxHR = HRZoneCalculator.storedMaxHR()
        let upperBPM = HRZoneCalculator.upperBPM(zone: upper, maxHR: maxHR)
        return sessionState.currentHR > (upperBPM + 5)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("REST")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Countdown ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(isRecovering ? Color.orange : Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 2) {
                    Text("\(restState.remaining)s")
                        .font(.title2.monospacedDigit().bold())
                    if isRecovering {
                        Text("Recovering")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 100, height: 100)

            // HR display
            if sessionState.currentHR > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(sessionState.currentHR)")
                        .monospacedDigit()
                }
                .font(.caption)
            }

            // Next exercise preview
            if let next = nextExercise {
                Text("Next: \(next.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Controls
            HStack(spacing: 16) {
                Button {
                    sessionState.extendRest(exerciseIndex: restState.exerciseIndex, completedSet: restState.completedSet, additionalSeconds: 60)
                } label: {
                    Text("+60s")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    let ex = nextExercise
                    let totalSets = ex?.sets ?? 1
                    let nextSet = restState.completedSet + 1
                    sessionState.skipRest(exerciseIndex: restState.exerciseIndex, nextSet: nextSet, totalSets: totalSets)
                } label: {
                    Text("Skip")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
