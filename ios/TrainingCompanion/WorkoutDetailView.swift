import SwiftUI

struct WorkoutDetailView: View {
    let api: APIClient
    let weekIndex: Int
    let dayName: String
    let sessionIndex: Int
    let session: ProgramSession

    @EnvironmentObject var programStore: ProgramStore
    @State private var showMoveSheet = false
    @State private var showReplaceSheet = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.archetype?.name
                         ?? session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.title2.bold())
                    HStack(spacing: 6) {
                        Label(session.modality.replacingOccurrences(of: "_", with: " ").capitalized,
                              systemImage: modalityIcon(session.modality))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let mins = session.archetype?.durationEstimateMinutes {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("\(mins) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if session.isDeload {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("Deload")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let notes = session.archetype?.notes {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Exercises") {
                if session.exercises.isEmpty {
                    Text("No exercises")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.exercises.indices, id: \.self) { i in
                        let assignment = session.exercises[i]
                        if !assignment.injurySkip, let ex = assignment.exercise {
                            ExerciseRowView(exercise: ex, assignment: assignment)
                        }
                    }
                }
            }
        }
        .navigationTitle(dayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    showMoveSheet = true
                } label: {
                    Label("Move Day", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showReplaceSheet = true
                } label: {
                    Label("Replace", systemImage: "arrow.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showMoveSheet) {
            if let week = programStore.serverProgram?.currentProgram?.weeks[safe: weekIndex] {
                MoveWorkoutSheet(
                    api: api,
                    weekIndex: weekIndex,
                    fromDay: dayName,
                    sessionIndex: sessionIndex,
                    weekSchedule: week.schedule
                )
                .environmentObject(programStore)
            }
        }
        .sheet(isPresented: $showReplaceSheet) {
            ReplaceWorkoutSheet(
                api: api,
                weekIndex: weekIndex,
                dayName: dayName,
                sessionIndex: sessionIndex,
                session: session
            )
            .environmentObject(programStore)
        }
    }

    private func modalityIcon(_ modality: String) -> String {
        switch modality {
        case "strength", "strength_endurance": return "dumbbell"
        case "conditioning", "aerobic_base": return "heart.circle"
        case "kettlebell": return "figure.strengthtraining.functional"
        case "mobility", "movement_skill": return "figure.flexibility"
        default: return "figure.run"
        }
    }
}

// MARK: - Exercise row

struct ExerciseRowView: View {
    let exercise: ProgramExercise
    let assignment: ProgramExerciseAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.body)
            Text(loadSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var loadSummary: String {
        let load = assignment.load
        if let sets = load.sets, let reps = load.reps?.displayString {
            var s = "\(sets)×\(reps)"
            if let kg = load.weightKg { s += " @ \(Int(kg)) kg" }
            else if let rpe = load.targetRpe { s += " @ RPE \(rpe)" }
            return s
        }
        if let dur = load.durationMinutes { return "\(dur) min" }
        if let rounds = load.targetRounds { return "\(rounds) rounds" }
        if assignment.loadNote != nil { return assignment.loadNote! }
        return assignment.slotType?.replacingOccurrences(of: "_", with: " ").capitalized ?? ""
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
