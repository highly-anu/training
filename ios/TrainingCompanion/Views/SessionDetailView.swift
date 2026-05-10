import SwiftUI

struct SessionDetailView: View {
    let session: ProgramSession
    let sessionKey: String
    var weekIndex: Int? = nil
    var dayName: String? = nil
    var sessionIndex: Int? = nil

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var programStore: ProgramStore
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String = ""
    @State private var fatigueRating: Double = 5
    @State private var showFatigue = false
    @State private var isSaving = false
    @State private var showMove = false
    @State private var showReplace = false

    private var isDone: Bool { appState.isSessionComplete(sessionKey) }

    /// Live session read from the store (updated after replace/move).
    /// Falls back to the prop value when index params are unavailable.
    private var currentSession: ProgramSession {
        guard let wi = weekIndex, let dn = dayName, let si = sessionIndex,
              let live = appState.serverProgram?.currentProgram?.weeks[safe: wi]?.schedule[dn]?[safe: si]
        else { return session }
        return live
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                exercisesSection
                if canEditProgram { actionsSection }
                if isDone { notesSection }
            }
            .navigationTitle(currentSession.archetype?.name ?? ModalityStyle.label(for: currentSession.modality))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                completionButton
                    .padding()
                    .background(.background)
            }
            .sheet(isPresented: $showMove) {
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex,
                   let week = appState.serverProgram?.currentProgram?.weeks[safe: wi] {
                    MoveWorkoutSheet(weekIndex: wi, fromDay: dn,
                                    sessionIndex: si, weekSchedule: week.schedule)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showReplace) {
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex,
                   let api = appState.api {
                    ReplaceWorkoutSheet(api: api, weekIndex: wi, dayName: dn,
                                       sessionIndex: si, session: currentSession)
                        .environmentObject(appState)
                }
            }
            .task {
                if let log = appState.sessionLogs[sessionKey] {
                    notes = log.notes ?? ""
                }
            }
        }
    }

    // MARK: - Program Actions

    private var canEditProgram: Bool {
        weekIndex != nil && dayName != nil && sessionIndex != nil && appState.api != nil
    }

    private var actionsSection: some View {
        Section("Workout") {
            Button { showMove = true } label: {
                Label("Move to Another Day", systemImage: "arrow.left.arrow.right")
            }
            Button { showReplace = true } label: {
                Label("Replace Workout", systemImage: "arrow.2.circlepath")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: ModalityStyle.icon(for: currentSession.modality))
                    .foregroundStyle(ModalityStyle.color(for: currentSession.modality))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ModalityStyle.label(for: currentSession.modality))
                        .font(.caption)
                        .foregroundStyle(ModalityStyle.color(for: currentSession.modality))
                    if let arch = currentSession.archetype {
                        Text(arch.name)
                            .font(.headline)
                        HStack(spacing: 8) {
                            if let mins = arch.durationEstimateMinutes {
                                Label("\(mins) min", systemImage: "clock")
                            }
                            if currentSession.isDeload {
                                Label("Deload", systemImage: "arrow.down.circle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            if let log = appState.sessionLogs[sessionKey], let completedAt = log.completedAt {
                Label("Completed · \(shortDateTime(completedAt))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
                if let avgHR = log.avgHR {
                    Label("Avg HR: \(avgHR) bpm", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        let exercises = currentSession.exercises.filter { !$0.injurySkip && $0.exercise != nil }
        return Section("Exercises") {
            if exercises.isEmpty {
                Text("No exercises").foregroundStyle(.secondary)
            } else {
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, ea in
                    exerciseRow(ea)
                }
            }
        }
    }

    private func exerciseRow(_ ea: ProgramExerciseAssignment) -> some View {
        let ex = ea.exercise!
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ex.name)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if let slotType = ea.slotType {
                    Text(slotTypeLabel(slotType))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            Text(formatLoad(ea))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let note = ea.notes ?? ex.notes {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section("Session Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .onChange(of: notes) { _, _ in
                    debouncedSaveNotes()
                }

            Toggle("Log Fatigue", isOn: $showFatigue)

            if showFatigue {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fatigue: \(Int(fatigueRating))/10")
                        Spacer()
                    }
                    .font(.caption)
                    Slider(value: $fatigueRating, in: 1...10, step: 1)
                        .onChange(of: fatigueRating) { _, _ in debouncedSaveNotes() }
                }
            }
        }
    }

    // MARK: - Completion Button

    private var completionButton: some View {
        Button {
            Task {
                isSaving = true
                if isDone {
                    appState.undoSessionComplete(sessionKey: sessionKey)
                } else {
                    await appState.markSessionComplete(sessionKey: sessionKey)
                    AppHaptics.success()
                }
                isSaving = false
            }
        } label: {
            HStack {
                if isSaving {
                    ProgressView().scaleEffect(0.9)
                } else {
                    Image(systemName: isDone ? "xmark.circle" : "checkmark.circle.fill")
                }
                Text(isDone ? "Mark Incomplete" : "Mark Session Complete")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(isDone ? .secondary : .green)
        .disabled(isSaving)
    }

    // MARK: - Helpers

    private func shortDateTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .short; out.timeStyle = .short
        return out.string(from: date)
    }

    private func slotTypeLabel(_ slotType: String) -> String {
        switch slotType {
        case "sets_reps":     return "Sets × Reps"
        case "time_domain":   return "Duration"
        case "emom":          return "EMOM"
        case "amrap":         return "AMRAP"
        case "for_time":      return "For Time"
        case "distance":      return "Distance"
        case "static_hold":   return "Static Hold"
        case "skill_practice":return "Skill"
        default:              return slotType
        }
    }

    private func resolvedSlotType(_ ea: ProgramExerciseAssignment) -> String {
        let known = ["sets_reps", "time_domain", "skill_practice", "emom",
                     "amrap", "amrap_movement", "for_time", "distance", "static_hold"]
        if let st = ea.slotType, known.contains(st) { return st }
        let load = ea.load
        if load.distanceKm    != nil { return "distance" }
        if load.holdSeconds   != nil { return "static_hold" }
        if load.format        != nil { return "emom" }
        if load.durationMinutes != nil { return "time_domain" }
        if load.timeMinutes != nil && load.targetRounds != nil { return "amrap" }
        if load.targetRounds  != nil { return "for_time" }
        return "sets_reps"
    }

    private func formatLoad(_ ea: ProgramExerciseAssignment) -> String {
        let load = ea.load
        let slotType = resolvedSlotType(ea)
        switch slotType {
        case "sets_reps":
            let sets = load.sets.map { "\($0)" } ?? "?"
            let reps = load.reps?.displayString ?? "?"
            if let kg = load.weightKg { return "\(sets)×\(reps) @ \(kg) kg" }
            if let rpe = load.targetRpe { return "\(sets)×\(reps) @ RPE \(rpe)" }
            return "\(sets)×\(reps)"
        case "time_domain", "skill_practice":
            if let min = load.durationMinutes {
                return "\(min) min\(load.zoneTarget.map { " · \($0)" } ?? "")"
            }
            return "Duration TBD"
        case "emom":
            if let min = load.timeMinutes, let rounds = load.targetRounds {
                return "\(min) min · \(rounds) rounds"
            }
            return load.format ?? "EMOM"
        case "amrap":
            return load.timeMinutes.map { "AMRAP \($0) min" } ?? "AMRAP"
        case "for_time":
            return load.targetRounds.map { "\($0) rounds for time" } ?? "For time"
        case "distance":
            return load.distanceKm.map { "\($0) km" } ?? "Distance"
        case "static_hold":
            let sets = load.sets.map { "\($0)×" } ?? ""
            let secs = load.holdSeconds.map { "\($0)s" } ?? "?"
            return "\(sets)\(secs) hold"
        default:
            return ""
        }
    }

    private func debouncedSaveNotes() {
        // Save notes via the API on each change (idempotent PUT).
        // In a production app this would be debounced to avoid rapid-fire API calls.
        Task {
            try? await appState.api?.saveSessionNotes(
                sessionKey: sessionKey,
                notes: notes,
                fatigueRating: showFatigue ? Int(fatigueRating) : nil
            )
        }
    }
}
