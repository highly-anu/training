import SwiftUI

/// What was done in a session, every exercise on one screen, saved once
/// (design-system §6.16).
///
/// Pushed from the session (§6.48). A sets × reps or hold slot has a row per
/// set — reps (or seconds), kg, RPE, done; any other slot its currency
/// fields — each prefilled from what was logged before, else from the
/// prescription. An exercise is saved when it is ticked: one already logged,
/// the one the form was opened at, and any the athlete changes. Save writes
/// to the phone (`AppState.saveSessionLog`) and closes; the server hears of
/// it in the background, and `SessionLogNoticeBanner` says when it has not.
struct SessionLogForm: View {
    let sessionKey: String
    let session: ProgramSession
    /// The exercise the athlete asked to log: ticked, and scrolled to.
    var openAt: String? = nil

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [ExerciseLogDraft] = []
    @State private var initial: [ExerciseLogDraft] = []
    @State private var marksComplete = false
    @State private var loaded = false
    @State private var confirmsDiscard = false

    private var isDone: Bool { appState.isSessionComplete(sessionKey) }
    private var completes: Bool { marksComplete && !isDone }
    private var performances: [String: ExercisePerformanceLog] { SessionLogDraft.performances(drafts) }
    private var isDirty: Bool { drafts != initial }
    private var canSave: Bool {
        !SessionLogDraft.isInvalid(drafts) && (!performances.isEmpty || completes)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    Text("Tick what you did. An exercise you change is ticked for you; nothing is sent until you save.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(drafts.indices, id: \.self) { index in
                    exerciseSection(index).id(drafts[index].id)
                }
                completionSection
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                drafts = SessionLogDraft.exercises(of: session, log: appState.sessionLogs[sessionKey], openAt: openAt)
                initial = drafts
                // The whole session's log is usually its end; one exercise's is not.
                marksComplete = openAt == nil && !isDone
                if let target = drafts.first(where: { $0.exerciseId == openAt }) {
                    proxy.scrollTo(target.id, anchor: .top)
                }
                // Debug builds: TC_LOG_SAVE logs the session as prescribed (SessionLogDebug).
                if let delay = SessionLogDebug.takeSave(sessionKey) {
                    Task {
                        try? await Task.sleep(for: delay)
                        for index in drafts.indices { drafts[index].included = true }
                        save()
                    }
                }
            }
        }
        .navigationTitle("Log session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isDirty { confirmsDiscard = true } else { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { endEditing() }
            }
        }
        .confirmationDialog("Discard what you entered?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .appActionBar {
            Button { save() } label: {
                Label(completes ? "Save and complete" : "Save", systemImage: "checkmark")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .appButton(completes ? .complete : .primary)
            .disabled(!canSave)
        }
    }

    // MARK: - One exercise

    private func exerciseSection(_ index: Int) -> some View {
        let draft = drafts[index]
        return Section {
            HStack(alignment: .top, spacing: AppMetrics.gapSmall) {
                Button {
                    AppHaptics.light()
                    drafts[index].included.toggle()
                } label: {
                    Image(systemName: draft.included ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .appSymbolReplace(value: draft.included)
                        .foregroundStyle(draft.included ? AnyShapeStyle(AppColor.complete) : AnyShapeStyle(.tertiary))
                        .appTapTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Save \(draft.name)")
                .accessibilityValue(draft.included ? "Yes" : "No")
                VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                    Text(draft.name).font(.headline)
                    Text(draft.prescription)
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, AppMetrics.gapTight)
            }
            if draft.logsSets { setRows(index) } else { outcomeRows(index) }
            if draft.asksClean { cleanRows(index) }
        } footer: {
            if draft.clockInvalid {
                Text("Enter the time as m:ss, like 7:32.").foregroundStyle(AppColor.destructive)
            } else if draft.isTest {
                Text("A test: what you log comes back as a result to save on the standard.")
            } else if draft.asksClean {
                Text("Clean: every rep owned.")
            }
        }
    }

    /// A value of the exercise; changing it ticks the exercise.
    private func value<T>(_ index: Int, _ path: WritableKeyPath<ExerciseLogDraft.Values, T>) -> Binding<T> {
        Binding(get: { drafts[index].values[keyPath: path] },
                set: {
                    drafts[index].values[keyPath: path] = $0
                    drafts[index].included = true
                })
    }

    /// One set's value, found by the set's id: a row sliding away after its
    /// set was removed still reads something.
    private func setValue<T>(_ index: Int, _ id: UUID, _ path: WritableKeyPath<ExerciseLogDraft.SetRow, T>,
                             else fallback: T) -> Binding<T> {
        Binding(get: { drafts[index].values.sets.first { $0.id == id }?[keyPath: path] ?? fallback },
                set: { new in
                    guard let at = drafts[index].values.sets.firstIndex(where: { $0.id == id }) else { return }
                    drafts[index].values.sets[at][keyPath: path] = new
                    drafts[index].included = true
                })
    }

    // MARK: - Sets

    @ViewBuilder
    private func setRows(_ index: Int) -> some View {
        let draft = drafts[index]
        ForEach(Array(draft.values.sets.enumerated()), id: \.element.id) { number, set in
            AppAdaptiveStack(spacing: AppMetrics.gapMedium) {
                Text("\(number + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .leading)
                    .accessibilityLabel("Set \(number + 1)")
                if draft.isHold {
                    numberField("s", setValue(index, set.id, \.seconds, else: 0), unit: "s",
                                label: "Set \(number + 1) seconds")
                } else {
                    numberField("0", setValue(index, set.id, \.reps, else: 0), unit: "reps",
                                label: "Set \(number + 1) reps")
                }
                HStack(spacing: AppMetrics.gapTight) {
                    TextField("kg", value: setValue(index, set.id, \.kg, else: nil), format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("Set \(number + 1) kilograms")
                    Text("kg").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                rpeMenu(setValue(index, set.id, \.rpe, else: 0))
                Button {
                    AppHaptics.light()
                    setValue(index, set.id, \.completed, else: true).wrappedValue.toggle()
                } label: {
                    Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .appSymbolReplace(value: set.completed)
                        .foregroundStyle(set.completed ? AnyShapeStyle(AppColor.complete) : AnyShapeStyle(.tertiary))
                        .appTapTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Set \(number + 1) done")
                .accessibilityValue(set.completed ? "Yes" : "No")
            }
            .monospacedDigit()
        }
        AppAdaptiveStack(spacing: AppMetrics.gapLarge) {
            Button {
                AppHaptics.light()
                withAnimation(AppAnimation.layoutChange) {
                    drafts[index].addSet()
                    drafts[index].included = true
                }
            } label: {
                Label("Add set", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
            if draft.values.sets.count > 1 {
                Button {
                    AppHaptics.light()
                    withAnimation(AppAnimation.layoutChange) {
                        drafts[index].values.sets.removeLast()
                        drafts[index].included = true
                    }
                } label: {
                    Label("Remove last", systemImage: "minus.circle")
                }
                .buttonStyle(.borderless)
                .tint(AppColor.destructive)
            }
        }
        .font(.subheadline)
    }

    private func numberField(_ placeholder: String, _ value: Binding<Int>, unit: String, label: String) -> some View {
        HStack(spacing: AppMetrics.gapTight) {
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .accessibilityLabel(label)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rpeMenu(_ rpe: Binding<Int>) -> some View {
        Menu {
            Picker("RPE", selection: rpe) {
                Text("Not rated").tag(0)
                ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
            }
        } label: {
            Text(rpe.wrappedValue == 0 ? "RPE —" : "RPE \(rpe.wrappedValue)")
                .font(.caption)
                .appTapTarget()
        }
        .accessibilityLabel("RPE")
        .accessibilityValue(rpe.wrappedValue == 0 ? "Not rated" : "\(rpe.wrappedValue)")
    }

    // MARK: - Outcome

    @ViewBuilder
    private func outcomeRows(_ index: Int) -> some View {
        let draft = drafts[index]
        ForEach(draft.fields, id: \.self) { field in
            HStack {
                Text(field.label)
                Spacer()
                Group {
                    switch field {
                    case .minutes:
                        TextField("0", value: value(index, \.minutes), format: .number).keyboardType(.decimalPad)
                    case .time:
                        TextField(draft.timePlaceholder, text: value(index, \.clock))
                            .keyboardType(.numbersAndPunctuation)
                    case .km:
                        TextField("0", value: value(index, \.km), format: .number).keyboardType(.decimalPad)
                    case .rounds:
                        TextField("0", value: value(index, \.rounds), format: .number).keyboardType(.numberPad)
                    case .reps:
                        TextField("0", value: value(index, \.reps), format: .number).keyboardType(.numberPad)
                    case .seconds:
                        TextField("0", value: value(index, \.holdSeconds), format: .number).keyboardType(.numberPad)
                    }
                }
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .accessibilityLabel("\(draft.name) \(field.label)")
            }
            .monospacedDigit()
        }
    }

    // MARK: - Clean, and a contract block's effort

    @ViewBuilder
    private func cleanRows(_ index: Int) -> some View {
        let draft = drafts[index]
        Toggle("Clean", isOn: value(index, \.clean))
        if draft.isModule {
            Stepper(draft.values.moduleRpe == 0 ? "RPE: not rated" : "RPE: \(draft.values.moduleRpe)",
                    value: value(index, \.moduleRpe), in: 0...10)
            // Set rows carry their own kg; a block without them says its bell here.
            if !draft.logsSets {
                HStack {
                    Text("Bell (kg)")
                    TextField("Weight", value: value(index, \.moduleWeight), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Completion

    private var completionSection: some View {
        Section {
            if isDone {
                Label("Session completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.complete)
            } else {
                Toggle("Mark session complete", isOn: $marksComplete)
            }
        } footer: {
            Text("Saved on this phone at once and sent in the background.")
        }
    }

    // MARK: - Save

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// One local write, then the screen closes; nothing here waits for the server.
    private func save() {
        // A number field hands its value over when it stops editing.
        endEditing()
        DispatchQueue.main.async {
            guard canSave else { return }
            appState.saveSessionLog(sessionKey: sessionKey, exercises: performances,
                                    completedAt: completes ? ISO8601DateFormatter().string(from: Date()) : nil)
            AppHaptics.success()
            dismiss()
        }
    }
}

/// Session logs that did not reach the server (§6.16): one row, above the
/// content, never in its way. They keep sending by themselves; "Try again"
/// sends now, and only a log the server refused offers Discard.
struct SessionLogNoticeBanner: View {
    /// One session's log; nil for any.
    var sessionKey: String? = nil

    @EnvironmentObject var appState: AppState
    @State private var isTrying = false
    @State private var confirmsDiscard = false

    var body: some View {
        if let notice = appState.sessionLogNotice(sessionKey: sessionKey) {
            VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                    Image(systemName: notice.canDiscard ? "exclamationmark.triangle.fill" : "wifi.slash")
                        .foregroundStyle(AppColor.warning)
                    Text(notice.message).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: AppMetrics.gapLarge) {
                    Button(isTrying ? "Sending…" : "Try again") {
                        isTrying = true
                        Task {
                            await appState.retrySessionLogs()
                            isTrying = false
                        }
                    }
                    .disabled(isTrying)
                    if notice.canDiscard {
                        Button("Discard", role: .destructive) { confirmsDiscard = true }
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
            }
            .appCard(compact: true, tint: AppColor.warning)
            .confirmationDialog("Discard this log? What you entered is removed from this phone.",
                                isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    Task { await appState.discardSessionLogs(keys: notice.keys) }
                }
                Button("Keep", role: .cancel) {}
            }
        }
    }
}
