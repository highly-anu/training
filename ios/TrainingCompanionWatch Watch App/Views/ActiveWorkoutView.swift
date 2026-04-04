import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    let session: WatchSession

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    @Environment(\.dismiss) private var dismiss
    @State private var isStarted = false
    @State private var workoutStartDate = Date()
    @State private var showStopConfirm = false
    @State private var lastHapticExerciseIndex = -1

    var body: some View {
        Group {
            if !isStarted {
                preWorkoutView
            } else if case .sessionComplete = sessionState.phase {
                SessionCompleteView(
                    session: session,
                    startedAt: workoutStartDate,
                    onSave: {
                        // buildSummary captures GPS, HR samples, and exercise timeline
                        let summary = workoutManager.buildSummary(startedAt: workoutStartDate)
                            ?? WatchWorkoutSummary(
                                sessionId: session.sessionId,
                                date: {
                                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                                    return f.string(from: Date())
                                }(),
                                startedAt: ISO8601DateFormatter().string(from: workoutStartDate),
                                endedAt: ISO8601DateFormatter().string(from: Date()),
                                durationMinutes: max(1, Int(Date().timeIntervalSince(workoutStartDate) / 60)),
                                avgHR: sessionState.avgHR > 0 ? sessionState.avgHR : nil,
                                peakHR: sessionState.peakHR > 0 ? sessionState.peakHR : nil,
                                setLogs: sessionState.setLogs,
                                exercisesCompleted: sessionState.completedExerciseIds.count,
                                source: "apple_watch_live",
                                hrSamples: nil, gpsTrack: nil, distanceMeters: nil,
                                elevationGainMeters: nil, cadenceAvg: nil,
                                paceSecsPerKm: nil, exerciseTimeline: nil
                            )
                        connectivity.sendWorkoutSummary(summary)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                timerStatusIndicator
            }
        }
        .task(id: isStarted) {
            guard isStarted else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard case let .timedWork(ei, elapsed) = sessionState.phase else { continue }
                guard !sessionState.isTimerPaused else { continue }
                sessionState.tickTimedWork()
                guard ei < session.exercises.count,
                      let durationMin = session.exercises[ei].durationMinutes else { continue }
                let target = durationMin * 60
                if elapsed + 1 == target && lastHapticExerciseIndex != ei {
                    lastHapticExerciseIndex = ei
                    WKInterfaceDevice.current().play(.notification)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    WKInterfaceDevice.current().play(.notification)

                    // Auto-advance to next exercise, or complete session if last
                    let nextIndex = ei + 1
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if nextIndex < session.exercises.count {
                        if session.exercises[nextIndex].durationMinutes != nil {
                            // Next is also timed — start its timer immediately
                            sessionState.autoAdvanceToNextTimedWork(
                                currentExerciseId: session.exercises[ei].exerciseId,
                                nextIndex: nextIndex
                            )
                        } else {
                            // Next is not timed — advance to active phase
                            sessionState.completeTimedWork(
                                exerciseIndex: ei,
                                exerciseId: session.exercises[ei].exerciseId
                            )
                        }
                    } else {
                        // Last exercise — complete it and end the session automatically
                        sessionState.completeTimedWork(
                            exerciseIndex: ei,
                            exerciseId: session.exercises[ei].exerciseId
                        )
                        sessionState.completeSession()
                        await workoutManager.endWorkout()
                    }
                }
            }
        }
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
                        if let cue = ex.coachingCue, !cue.isEmpty {
                            Text(cue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
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
            SessionProgressView(session: session)
            commandsTabView
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
            let target = (exercise.durationMinutes ?? 0) * 60
            let overTime = elapsed >= target
            let fraction = target > 0 ? min(1.0, Double(elapsed) / Double(target)) : 0
            let nextIndex = ei + 1
            let isLast = nextIndex >= session.exercises.count

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
                Button(isLast ? "Done" : "Next") {
                    if isLast {
                        sessionState.completeTimedWork(exerciseIndex: ei,
                                                       exerciseId: exercise.exerciseId)
                    } else if session.exercises[nextIndex].durationMinutes != nil {
                        sessionState.autoAdvanceToNextTimedWork(
                            currentExerciseId: exercise.exerciseId,
                            nextIndex: nextIndex
                        )
                    } else {
                        sessionState.completeTimedWork(exerciseIndex: ei,
                                                       exerciseId: exercise.exerciseId)
                    }
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

    // MARK: - Timer status indicator (navigation bar, visible from all tabs)

    @ViewBuilder
    private var timerStatusIndicator: some View {
        if case let .timedWork(_, elapsed) = sessionState.phase {
            HStack(spacing: 3) {
                Image(systemName: sessionState.isTimerPaused ? "pause.fill" : "timer")
                    .font(.system(size: 9))
                Text(timerString(elapsed))
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(sessionState.isTimerPaused ? Color.orange : Color.green)
        }
    }

    // MARK: - Commands tab

    @ViewBuilder
    private var commandsTabView: some View {
        VStack(spacing: 14) {
            if case .timedWork = sessionState.phase {
                Button {
                    if sessionState.isTimerPaused { sessionState.resumeTimer() }
                    else { sessionState.pauseTimer() }
                } label: {
                    Label(sessionState.isTimerPaused ? "Resume" : "Pause",
                          systemImage: sessionState.isTimerPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(sessionState.isTimerPaused ? .green : .orange)
            }

            Button(role: .destructive) {
                showStopConfirm = true
            } label: {
                Label("End Session", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.8))
        }
        .padding()
        .navigationTitle("Commands")
        .confirmationDialog("End session?", isPresented: $showStopConfirm) {
            Button("End", role: .destructive) {
                sessionState.reset()
                Task { await workoutManager.endWorkout() }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Exercise page

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
