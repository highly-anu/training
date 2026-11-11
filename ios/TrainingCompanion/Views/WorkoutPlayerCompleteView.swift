import SwiftUI

/// The end of a workout on the phone (design-system §6.44), the watch's
/// SessionCompleteView at a phone's size: the package's summary — time, sets,
/// volume, each step's log — then a test's results to save or not, the reps
/// a timed step asks for at the end, notes, and Save. A training-contract
/// session's "done as written?" is asked on the session once it is saved
/// (SessionDetailView's Progress), where it has always been.
struct WorkoutPlayerCompleteView: View {
    @ObservedObject var player: WorkoutPlayerModel
    let session: WatchSession
    var onClose: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var failed = false
    @State private var confirmDiscard = false

    private var engine: WorkoutSessionState { player.engine }
    private var testSteps: [WatchExercise] { session.exercises.filter { $0.standard != nil } }
    private var countSteps: [WatchExercise] { session.exercises.filter(\.asksReps) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Workout complete").font(.title2.bold())
                        Text(session.archetypeName).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Summary") {
                    LabeledContent("Time", value: WatchSpecText.mmss(engine.elapsedSeconds))
                    LabeledContent("Sets", value: "\(WatchSummaryText.totalSets(engine.setLogs))")
                    let volume = WatchSummaryText.volumeKg(session, engine.setLogs)
                    if volume > 0 { LabeledContent("Volume", value: "\(Int(volume.rounded())) kg") }
                    LabeledContent("Steps done", value: "\(engine.completedExerciseIds.count)")
                }
                Section("Steps") {
                    ForEach(Array(WatchSummaryText.exerciseLines(session, logs: engine.setLogs,
                                                                 outcomes: engine.outcomes).enumerated()),
                            id: \.offset) { _, line in
                        LabeledContent(line.name, value: line.logged ?? "—")
                            .foregroundStyle(line.logged == nil ? .secondary : .primary)
                    }
                }
                if !testSteps.isEmpty {
                    Section {
                        ForEach(testSteps, id: \.exerciseId) { ex in
                            ResultField(title: ex.standard?.name ?? ex.name, exercise: ex,
                                        value: WatchResults.value(ex, sets: engine.setLogs[ex.exerciseId] ?? [],
                                                                  outcome: engine.outcomes[ex.exerciseId])) { v in
                                engine.setResult(ex, value: v)
                            }
                        }
                    } header: {
                        Text("Results")
                    } footer: {
                        Text("Save results makes each a result on its standard; Not a test leaves them out.")
                    }
                }
                if !countSteps.isEmpty {
                    Section("Reps counted") {
                        ForEach(countSteps, id: \.exerciseId) { ex in
                            CountField(title: ex.name,
                                       reps: engine.setLogs[ex.exerciseId]?.first?.repsActual) { n in
                                engine.setCount(ex, reps: n)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("How did it go?", text: $player.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    if testSteps.isEmpty {
                        saveButton("Save workout", decision: nil)
                    } else {
                        saveButton("Save results", decision: "save")
                        Button("Not a test") { Task { await save("dismiss") } }
                            .disabled(player.saving)
                    }
                    Button("Discard workout", role: .destructive) { confirmDiscard = true }
                } footer: {
                    if failed {
                        Text("Not saved — the server could not be reached. The workout is kept; try again.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("")
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { player.discard(); onClose() }
            } message: {
                Text("Nothing is saved.")
            }
        }
    }

    private func saveButton(_ title: String, decision: String?) -> some View {
        Button {
            Task { await save(decision) }
        } label: {
            HStack {
                Text(title).fontWeight(.semibold)
                if player.saving { Spacer(); ProgressView() }
            }
        }
        .disabled(player.saving)
    }

    private func save(_ decision: String?) async {
        failed = false
        if await player.save(decision: decision, appState: appState) {
            AppHaptics.success()
            onClose()
        } else {
            failed = true
            AppHaptics.error()
        }
    }
}

/// A test's result typed as the standard reads it: a clock ("4:58") for a
/// time, a number for the rest (WatchResults words it back).
private struct ResultField: View {
    let title: String
    let exercise: WatchExercise
    let value: Double?
    let onSet: (Double) -> Void

    @State private var text = ""

    private var isClock: Bool { exercise.standard?.result == "duration" }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(isClock ? "m:ss" : "0", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(isClock ? .numbersAndPunctuation : .decimalPad)
                .frame(maxWidth: 110)
                .onSubmit(commit)
                .onChange(of: text) { _, _ in commit() }
        }
        .onAppear { text = value.map { WatchResults.text(exercise, value: $0) } ?? "" }
    }

    private func commit() {
        if isClock, let secs = SessionLogging.parseClock(text) { onSet(Double(secs)) }
        else if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 { onSet(v) }
    }
}

/// The reps a timed step's athlete counted, asked at the end.
private struct CountField: View {
    let title: String
    let reps: Int?
    let onSet: (Int) -> Void

    @State private var n = 0

    var body: some View {
        Stepper(value: $n, in: 0...999) {
            LabeledContent(title, value: "\(n)")
        }
        .onChange(of: n) { _, value in if value > 0 { onSet(value) } }
        .onAppear { n = reps ?? 0 }
    }
}
