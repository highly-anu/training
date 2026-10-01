import SwiftUI

/// Log what was done for one exercise of a session (design-system §6.16).
///
/// A sets × reps or hold slot gets one row per set — reps (or seconds), kg,
/// RPE, done — prefilled from the prescription or from what was logged
/// before; any other slot gets its currency fields. Saving writes through
/// `AppState.logExercise`, which merges per exercise on the server.
struct ExerciseLogSheet: View {
    let sessionKey: String
    let assignment: ProgramExerciseAssignment

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private struct SetDraft: Identifiable {
        let id = UUID()
        var reps: Int
        var seconds: Int
        var kg: Double?
        var rpe: Int          // 0 = not rated
        var completed: Bool
    }

    @State private var sets: [SetDraft] = []
    @State private var minutes: Double? = nil
    @State private var km: Double? = nil
    @State private var rounds: Int? = nil
    @State private var reps: Int? = nil
    @State private var isSaving = false
    @State private var loaded = false

    private var slotType: String { LoadFormat.resolvedSlotType(assignment) }
    private var logsSets: Bool { SessionLogging.logsSets(slotType) }
    private var isHold: Bool { slotType == "static_hold" }
    private var fields: [OutcomeField] { SessionLogging.outcomeFields(for: slotType) }
    private var exerciseId: String? { assignment.exercise?.id }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.exercise?.name ?? "Exercise").font(.headline)
                        Text(LoadFormat.describe(assignment))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if logsSets { setsSection } else { outcomeSection }
            }
            .navigationTitle(logsSets ? "Log sets" : "Log result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || exerciseId == nil)
                }
            }
            .onAppear { if !loaded { prefill(); loaded = true } }
        }
    }

    // MARK: - Sets

    private var setsSection: some View {
        Section {
            ForEach($sets) { $set in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Set \((sets.firstIndex { $0.id == set.id } ?? 0) + 1)")
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Toggle("Done", isOn: $set.completed).labelsHidden()
                    }
                    HStack(spacing: 12) {
                        if isHold {
                            Stepper("\(set.seconds) s", value: $set.seconds, in: 1...600, step: 5)
                        } else {
                            Stepper("\(set.reps) reps", value: $set.reps, in: 0...100)
                        }
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            TextField("kg", value: $set.kg, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("kg").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper(set.rpe == 0 ? "RPE —" : "RPE \(set.rpe)", value: $set.rpe, in: 0...10)
                            .font(.caption)
                    }
                    .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
            .onDelete { sets.remove(atOffsets: $0) }
            Button {
                let last = sets.last
                sets.append(SetDraft(reps: last?.reps ?? 5, seconds: last?.seconds ?? 30,
                                     kg: last?.kg, rpe: 0, completed: true))
            } label: {
                Label("Add set", systemImage: "plus.circle")
            }
        } header: {
            Text(isHold ? "Holds" : "Sets")
        } footer: {
            Text("Prefilled from the prescription. Switch off a set you skipped; swipe to remove one.")
        }
    }

    // MARK: - Outcome

    private var outcomeSection: some View {
        Section {
            ForEach(fields, id: \.self) { field in
                HStack {
                    Text(field.label)
                    Spacer()
                    switch field {
                    case .minutes:
                        TextField("0", value: $minutes, format: .number).multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad).frame(width: 90)
                    case .km:
                        TextField("0", value: $km, format: .number).multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad).frame(width: 90)
                    case .rounds:
                        TextField("0", value: $rounds, format: .number).multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad).frame(width: 90)
                    case .reps:
                        TextField("0", value: $reps, format: .number).multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad).frame(width: 90)
                    }
                }
                .monospacedDigit()
            }
        } header: {
            Text("What you did")
        } footer: {
            Text("This is the currency the program's analytics read for this slot.")
        }
    }

    // MARK: - Data

    private func prefill() {
        let load = assignment.load
        let existing = exerciseId.flatMap { appState.sessionLogs[sessionKey]?.exercises[$0] }
        if logsSets {
            if let existing, !existing.sets.isEmpty {
                sets = existing.sets.sorted { $0.setIndex < $1.setIndex }.map {
                    SetDraft(reps: $0.repsActual ?? 0, seconds: $0.durationSeconds ?? load.holdSeconds ?? 30,
                             kg: $0.weightKg, rpe: $0.rpe ?? 0, completed: $0.completed)
                }
            } else {
                let count = max(1, load.sets ?? 3)
                let reps = load.reps?.intValue ?? 5
                sets = (0..<count).map { _ in
                    SetDraft(reps: reps, seconds: load.holdSeconds ?? 30, kg: load.weightKg, rpe: 0, completed: true)
                }
            }
        } else {
            minutes = existing?.durationSec.map { Double($0) / 60 }
                ?? (load.durationMinutes ?? load.timeMinutes).map(Double.init)
            km = existing?.distanceKm ?? load.distanceKm
            rounds = existing?.rounds ?? load.targetRounds
            reps = existing?.sets.first?.repsActual
        }
    }

    private func save() async {
        guard let exerciseId else { return }
        isSaving = true
        defer { isSaving = false }
        var perf = ExercisePerformanceLog()
        if logsSets {
            perf.sets = sets.enumerated().map { i, d in
                WatchSetLog(setIndex: i, repsActual: isHold ? nil : d.reps, weightKg: d.kg,
                            rpe: d.rpe > 0 ? d.rpe : nil, completed: d.completed,
                            durationSeconds: isHold ? d.seconds : nil, startOffset: nil, endOffset: nil)
            }
        } else {
            if fields.contains(.minutes), let m = minutes, m > 0 { perf.durationSec = Int((m * 60).rounded()) }
            if fields.contains(.km), let k = km, k > 0 { perf.distanceKm = k }
            if fields.contains(.rounds), let r = rounds, r > 0 { perf.rounds = r }
            if fields.contains(.reps), let r = reps, r > 0 {
                perf.sets = [WatchSetLog(setIndex: 0, repsActual: r, weightKg: nil, rpe: nil, completed: true,
                                         durationSeconds: nil, startOffset: nil, endOffset: nil)]
            }
        }
        await appState.logExercise(sessionKey: sessionKey, exerciseId: exerciseId, performance: perf)
        AppHaptics.success()
        dismiss()
    }
}
