import SwiftUI

struct ActiveWorkoutView: View {
    let session: WatchSession

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    @Environment(\.dismiss) private var dismiss
    @State private var isStarted = false
    @State private var workoutStartDate = Date()

    var body: some View {
        Group {
            if !isStarted {
                preWorkoutView
            } else if case .sessionComplete = sessionState.phase {
                SessionCompleteView(
                    session: session,
                    startedAt: workoutStartDate,
                    onSave: {
                        connectivity.markSessionComplete(session.sessionId)
                        sessionState.reset()
                        dismiss()
                    },
                    onDiscard: {
                        sessionState.reset()
                        dismiss()
                    }
                )
            } else if sessionState.isResting {
                RestTimerView(session: session)
            } else {
                workoutTabView
            }
        }
        .navigationTitle(session.archetypeName)
        .navigationBarBackButtonHidden(isStarted)
    }

    // MARK: - Pre-workout

    private var preWorkoutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if session.isDeload {
                    Label("Deload — quality over load", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                ForEach(session.exercises, id: \.exerciseId) { ex in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: ModalityStyle.slotTypeIcon(for: ex.resolvedSlotType))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(ex.name).font(.caption).lineLimit(1)
                        }
                        Text(ex.loadDescription).font(.caption2).foregroundStyle(.secondary)
                        if let note = ex.loadNote {
                            Text(note).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button("Begin Workout") {
                    workoutStartDate = Date()
                    isStarted = true
                    Task { await workoutManager.startWorkout(session: session,
                                                            maxHR: connectivity.maxHR) }
                }
                .buttonStyle(.borderedProminent)
                .tint(ModalityStyle.color(for: session.modalityId))
                .padding(.top, 8)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Active workout (TabView)

    private var workoutTabView: some View {
        TabView {
            currentExercisePage
            timerTabView
            SessionProgressView(session: session, onStop: {
                sessionState.reset()
                Task { await workoutManager.endWorkout() }
                dismiss()
            })
            LiveMetricsView()
        }
        .tabViewStyle(.page)
    }

    // MARK: - Timer tab

    @ViewBuilder
    private var timerTabView: some View {
        if case let .timedWork(ei, elapsed) = sessionState.phase,
           ei < session.exercises.count {
            let exercise = session.exercises[ei]
            let target = (exercise.durationMinutes ?? 20) * 60
            let overTime = elapsed >= target
            let fraction = target > 0 ? min(1.0, Double(elapsed) / Double(target)) : 0

            VStack(spacing: 12) {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(overTime ? Color.orange : ModalityStyle.color(for: session.modalityId),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(timerString(elapsed))
                            .font(.title2.monospacedDigit().bold())
                        if let zone = exercise.zoneTarget {
                            Text(zone)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
                Button("Done") {
                    sessionState.completeTimedWork(exerciseIndex: ei,
                                                   exerciseId: exercise.exerciseId)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding()
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No active timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func timerString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var currentExercisePage: some View {
        let exerciseIndex = currentExerciseIndex
        if exerciseIndex < session.exercises.count {
            CurrentExerciseView(
                exercise: session.exercises[exerciseIndex],
                exerciseIndex: exerciseIndex,
                session: session
            )
        } else {
            finishButton
        }
    }

    private var finishButton: some View {
        Button("Finish Session") {
            sessionState.completeSession()
            Task { await workoutManager.endWorkout() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private var currentExerciseIndex: Int {
        switch sessionState.phase {
        case let .active(ei, _):           return ei
        case let .timedWork(ei, _):        return ei
        case let .emomInterval(ei, _, _, _): return ei
        case let .amrapRunning(ei, _):     return ei
        default:                           return 0
        }
    }
}
