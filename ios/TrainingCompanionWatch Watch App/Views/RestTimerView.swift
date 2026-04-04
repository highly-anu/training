import SwiftUI

struct RestTimerView: View {
    let session: WatchSession

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        guard case let .resting(ei, cs, remaining) = sessionState.phase else {
            return AnyView(EmptyView())
        }
        let ex = ei < session.exercises.count ? session.exercises[ei] : nil
        let isSmartHold = shouldHoldForHR(exercise: ex,
                                          maxHR: connectivity.maxHR,
                                          remaining: remaining)

        return AnyView(
            VStack(spacing: 8) {
                Text("REST")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progressFraction(remaining: remaining,
                                                            exercise: ex))
                        .stroke(isSmartHold ? Color.orange : Color.green,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeString(remaining))
                        .font(.title3.monospacedDigit())
                        .bold()
                }
                .frame(width: 80, height: 80)

                if isSmartHold {
                    Label("Still recovering", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(sessionState.currentHR) bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if ex != nil {
                    Text(ex!.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }

                HStack(spacing: 12) {
                    Button("Skip") {
                        sessionState.skipRest(exerciseIndex: ei, completedSet: cs)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    Button("+30s") {
                        sessionState.extendRest(exerciseIndex: ei, completedSet: cs,
                                                current: remaining)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if case .resting = sessionState.phase { sessionState.tickRest() }
                }
            }
        )
    }

    private func shouldHoldForHR(exercise: WatchExercise?, maxHR: Int, remaining: Int) -> Bool {
        guard remaining == 0,
              let upper = exercise?.prescribedZoneUpper,
              sessionState.currentHR > 0, maxHR > 0 else { return false }
        let upperBPM = HRZoneCalculator.bpmBounds(zone: upper, maxHR: maxHR).upper
        return sessionState.currentHR > upperBPM + 5
    }

    private func progressFraction(remaining: Int, exercise: WatchExercise?) -> Double {
        let total = Double(exercise?.restSeconds ?? 60)
        guard total > 0 else { return 1 }
        return min(1.0, Double(remaining) / total)
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}
