import SwiftUI

struct SetsRepsView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var showSetLogger = false
    @State private var showCue = false

    private var currentSet: Int {
        if case .active(_, let s) = sessionState.phase { return s }
        return 0
    }
    private var totalSets: Int { exercise.sets ?? 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {

                // Exercise name
                Text(exercise.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                // Load
                Text(exercise.loadDescription)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                // Progression note
                if let note = exercise.loadNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                // Set dots
                HStack(spacing: 6) {
                    ForEach(0..<totalSets, id: \.self) { i in
                        Circle()
                            .fill(i < currentSet ? Color.green : (i == currentSet ? Color.primary : Color.secondary.opacity(0.4)))
                            .frame(width: 10, height: 10)
                    }
                }

                Text("Set \(currentSet + 1) of \(totalSets)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Coaching cue (expandable)
                if let cue = exercise.coachingCue, !cue.isEmpty {
                    Button {
                        showCue.toggle()
                    } label: {
                        Label(showCue ? "Hide cue" : "Show cue", systemImage: "quote.bubble")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    if showCue {
                        Text(cue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // HR badge
                HRBadge()

                Spacer(minLength: 8)

                // Complete Set button
                Button {
                    showSetLogger = true
                } label: {
                    Label("Complete Set", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .sheet(isPresented: $showSetLogger) {
            SetLoggerSheetView(exercise: exercise, setIndex: currentSet) {
                showSetLogger = false
                sessionState.completeSet(exerciseIndex: exerciseIndex, setIndex: currentSet)
            }
        }
    }
}
