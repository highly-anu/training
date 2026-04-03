import SwiftUI

struct DistanceView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var manualKm: Double = 0
    @State private var useManual = false

    private var targetKm: Double { exercise.distanceKm ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(exercise.loadDescription)
                    .font(.title3.bold())

                if let zone = exercise.zoneTarget {
                    Text(zone)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let cue = exercise.coachingCue, !cue.isEmpty {
                    Text(cue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HRBadge()

                // GPS unavailable — manual entry
                VStack(spacing: 4) {
                    Text("Distance covered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f km", manualKm))
                        .font(.title3.monospacedDigit())
                    HStack(spacing: 12) {
                        Button { manualKm = max(0, manualKm - 0.5) } label: {
                            Image(systemName: "minus.circle")
                        }
                        Button { manualKm += 0.5 } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                }

                Button {
                    sessionState.completeExercise(exerciseIndex)
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
    }
}
