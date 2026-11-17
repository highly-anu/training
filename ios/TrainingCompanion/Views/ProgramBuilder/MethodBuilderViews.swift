import SwiftUI

// A method of the athlete's own, described in words and built by the server
// (docs/roadmap.md 21.6, design-system §6.60): the describe form and the
// build's screen, pushed inside the program builder from its first step. The
// words are `MethodBuildWords`; the web's twin is `components/methods/`.

/// Where the builder's first step has gone: to describe a method (or a change
/// to one), or to a build.
enum MethodRoute: Hashable, Identifiable {
    case describe(revises: String?)
    case build(String)

    var id: String {
        switch self {
        case .describe(let revises): return "describe:\(revises ?? "")"
        case .build(let id): return "build:\(id)"
        }
    }

    #if DEBUG
    /// Debug builds open the builder on one of these with
    /// `SIMCTL_CHILD_TC_METHOD_BUILDER=describe | revise:<method id> | build:<build id>`.
    static var debugLaunch: MethodRoute? {
        guard let value = ProcessInfo.processInfo.environment["TC_METHOD_BUILDER"], !value.isEmpty else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "revise" where parts.count > 1: return .describe(revises: parts[1])
        case "build" where parts.count > 1: return .build(parts[1])
        default: return .describe(revises: nil)
        }
    }
    #endif
}

// MARK: - Describe

/// Describe a method in words, or say what to change in one of the athlete's,
/// and start its build. Days, session length, level and equipment are the
/// builder's own (filled from the profile) and can be changed here.
struct MethodDescribeView: View {
    let revises: String?
    @ObservedObject var builder: BuilderState
    @Binding var route: MethodRoute?
    @EnvironmentObject var appState: AppState

    @State private var note = ""
    @State private var tried = false
    @State private var isStarting = false
    @State private var refusal: String? = nil
    @State private var loadFailed = false

    private static let example = "For example: three strength days a week around squat, press and deadlift, "
        + "adding weight slowly, with two easy runs. Twelve weeks, an easier week every fourth."

    private var method: MethodSummary? { appState.methods?.methods.first { $0.id == revises } }
    private var unavailable: String? { MethodBuildWords.unavailableReason(appState.methods) }

    private var text: Binding<String> {
        revises == nil ? $builder.methodDraft.description : $note
    }

    private var problem: String? {
        if revises != nil {
            return MethodBuildWords.textProblem(note, length: MethodBuildWords.noteLength, what: "the change")
        }
        return MethodBuildWords.textProblem(builder.methodDraft.description, length: MethodBuildWords.descriptionLength,
                                            what: "a description")
            ?? (builder.methodDraft.pastedText.count > MethodBuildWords.pastedMax
                ? "The pasted text takes at most \(MethodBuildWords.pastedMax.formatted()) characters." : nil)
    }

    private var equipmentLine: String {
        let labels = Dictionary((EquipmentItem.all + appState.servedEquipment).map { ($0.id, $0.label) },
                                uniquingKeysWith: { first, _ in first })
        let owned = builder.constraints.equipment.map { labels[$0] ?? $0.replacingOccurrences(of: "_", with: " ") }
        return owned.isEmpty
            ? "No equipment chosen, so it is written for bodyweight. Change it on the builder's Constraints step or in Profile ▸ Equipment."
            : "Your equipment: \(owned.joined(separator: ", ")). Change it on the builder's Constraints step or in Profile ▸ Equipment."
    }

    var body: some View {
        Group {
            if appState.methods == nil {
                if loadFailed {
                    AppFailedState(title: "Couldn't load your methods",
                                   message: "Check the connection and try again.") { await load() }
                } else {
                    AppLoadingState(shape: .list, label: "Loading your methods")
                }
            } else if revises != nil && method == nil {
                AppEmptyState(icon: "questionmark.folder", title: "That method is no longer among yours",
                              message: "Pick one of your methods on the builder's first step.",
                              actionLabel: "Back") { route = nil }
            } else {
                form
            }
        }
        .navigationTitle(revises == nil ? "Your own method" : "Revise method")
        .navigationBarTitleDisplayMode(.inline)
        .task { if appState.methods == nil { await load() } }
    }

    private var form: some View {
        Form {
            Section {
                AppLongTextField(prompt: revises == nil ? Self.example
                                 : "For example: make the Saturday session a long easy run instead of intervals.",
                                 text: text, lines: revises == nil ? 5...12 : 3...8,
                                 label: revises == nil ? "Describe how you want to train" : "What should change")
            } header: {
                Text(revises == nil ? "Describe how you want to train" : "What should change in \(method?.name ?? "it")?")
            } footer: {
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    Text(revises == nil
                         ? "In your own words: what a week looks like, what you want to get better at, how it should progress. Name a published method if it is one — it is written as your version of it."
                         : "Say it as you would to a coach. The method keeps its name unless you ask otherwise, and the change becomes a new revision.")
                    if tried, let problem {
                        Text(problem).foregroundStyle(AppColor.destructive)
                    }
                }
            }

            Section {
                Picker("Days a week", selection: $builder.constraints.daysPerWeek) {
                    ForEach(MethodBuildWords.days, id: \.self) { Text("\($0) days").tag($0) }
                }
                Picker("Session length", selection: $builder.constraints.sessionTimeMinutes) {
                    ForEach(minuteChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Level", selection: $builder.constraints.trainingLevel) {
                    ForEach(ClientVocab.trainingLevels, id: \.self) { Text($0.capitalized).tag($0) }
                }
            } header: {
                Text("Written for")
            } footer: {
                Text(equipmentLine)
            }

            if revises == nil {
                Section {
                    AppLongTextField(prompt: "A plan from a coach, a week you wrote down, notes from a book.",
                                     text: $builder.methodDraft.pastedText, lines: 2...10,
                                     label: "A plan or notes to work from")
                } header: {
                    Text("A plan or notes to work from (optional)")
                }
            }

            Section {
                Toggle("Look it up on the web", isOn: $builder.methodDraft.webSearch)
            } footer: {
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    Text("For a published method: reads how its week is really built before writing yours.")
                    if let limits = appState.methods?.limits {
                        Text("A build takes a few minutes. \(limits.remaining) of \(limits.daily) left today.")
                    }
                }
            }

            if let message = unavailable ?? refusal {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(AppColor.destructive)
                }
            }
        }
        .appActionBar {
            Button {
                Task { await start() }
            } label: {
                Group {
                    if isStarting {
                        ProgressView()
                    } else {
                        Label(revises == nil ? "Build the method" : "Build the revision", systemImage: "sparkles")
                    }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .appButton(.primary)
            .disabled(isStarting || unavailable != nil)
        }
    }

    /// The athlete's own length when it is not one of the usual ones.
    private var minuteChoices: [Int] {
        let own = builder.constraints.sessionTimeMinutes
        return MethodBuildWords.minutes.contains(own) ? MethodBuildWords.minutes
            : (MethodBuildWords.minutes + [own]).sorted()
    }

    private func load() async {
        loadFailed = false
        loadFailed = !(await appState.loadMethods())
    }

    private func start() async {
        tried = true
        refusal = nil
        guard problem == nil, unavailable == nil, let api = appState.api else { return }
        isStarting = true
        defer { isStarting = false }
        let request = MethodBuildRequest(
            text: revises == nil ? builder.methodDraft.description : note,
            pastedText: builder.methodDraft.pastedText, webSearch: builder.methodDraft.webSearch,
            answers: .init(days: builder.constraints.daysPerWeek, minutes: builder.constraints.sessionTimeMinutes,
                           level: builder.constraints.trainingLevel, equipment: builder.constraints.equipment),
            revises: revises)
        do {
            switch try await api.startMethodBuild(request) {
            case .build(let build):
                AppHaptics.light()
                await appState.loadMethods()
                route = .build(build.id)
            case .refused(let message):
                refusal = message
            }
        } catch {
            refusal = "The build could not be started. Check the connection and try again."
        }
    }
}

// MARK: - A build

/// One build, from waiting to its end: the steps while it runs (asked again
/// every two seconds while this screen is in front), then the method, or why
/// there is none. The athlete is free to leave; the build carries on and is
/// offered again on the builder's first step.
struct MethodBuildView: View {
    let buildId: String
    @ObservedObject var builder: BuilderState
    @Binding var route: MethodRoute?
    @EnvironmentObject var appState: AppState

    @State private var build: MethodBuild? = nil
    @State private var missing = false
    @State private var loadFailed = false
    @State private var isCancelling = false
    @State private var announced = false

    var body: some View {
        Group {
            if let build {
                if build.isOpen {
                    running(build)
                } else if build.isDone, let result = build.result {
                    done(result)
                } else {
                    ended(build)
                }
            } else if missing {
                AppEmptyState(icon: "questionmark.folder", title: "That build is no longer here",
                              message: "Your methods are on the builder's first step.",
                              actionLabel: "Back") { route = nil }
            } else if loadFailed {
                AppFailedState(title: "Couldn't load the build",
                               message: "Check the connection and try again.") { await poll() }
            } else {
                AppLoadingState(shape: .list, label: "Loading the build")
            }
        }
        .navigationTitle("Your own method")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: buildId) { await poll() }
    }

    // MARK: Running

    private func running(_ build: MethodBuild) -> some View {
        let at = MethodBuildWords.stepIndex(build)
        return List {
            Section {
                ForEach(Array(MethodBuildWords.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: AppMetrics.gapMedium) {
                        Group {
                            if index < at {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.complete)
                            } else if index == at {
                                ProgressView()
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 24)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(index == at ? MethodBuildWords.headline(build) : step.label)
                                .foregroundStyle(index > at ? .secondary : .primary)
                            if index == at, let detail = build.progress.detail, !detail.isEmpty {
                                Text(detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(stepLabel(index: index, at: at, step: step.label, build: build))
                }
            } header: {
                Text(build.revise == nil ? "Building your method" : "Building the revision")
            } footer: {
                Text("This takes a few minutes. You can leave this screen: the build carries on, and the method appears under Your methods when it is ready.")
            }
            if let words = build.description, !words.isEmpty {
                Section("You asked for") {
                    Text(words).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await cancel() }
                } label: {
                    if isCancelling { ProgressView() } else { Text("Stop the build") }
                }
                .disabled(isCancelling)
            }
        }
    }

    private func stepLabel(index: Int, at: Int, step: String, build: MethodBuild) -> String {
        if index < at { return "\(step), done" }
        if index == at { return "\(MethodBuildWords.headline(build)), in progress" }
        return "\(step), not started"
    }

    // MARK: Done

    private func done(_ result: MethodBuild.Outcome) -> some View {
        let card = appState.philosophies.first { $0.id == result.packageId }
        return List {
            Section {
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(AppColor.complete)
                    Text(result.name).font(.title3).fontWeight(.semibold)
                    if let summary = result.summary, !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, AppMetrics.gapTight)
            }
            if let card, let tracks = card.tracks, !tracks.isEmpty {
                ForEach(tracks) { track in
                    Section(track.name) {
                        TrackPhaseList(track: track, showsDescriptions: true)
                            .padding(.vertical, AppMetrics.gapTight)
                    }
                }
            }
            Section {
                Button {
                    route = .describe(revises: result.packageId)
                } label: {
                    Label("Revise it", systemImage: "pencil")
                }
            } footer: {
                Text("Say what should change and it is built again as a new revision.")
            }
        }
        .appActionBar {
            Button {
                if let card, !builder.lanes.contains(where: { $0.philosophyId == card.id }) {
                    builder.toggle(card)
                }
                route = nil
            } label: {
                Label(card == nil ? "Back to the builder" : "Build a program with it", systemImage: "arrow.right")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .appButton(.primary)
        }
    }

    // MARK: Failed or stopped

    private func ended(_ build: MethodBuild) -> some View {
        let stopped = build.status == "cancelled"
        return AppEmptyState(
            icon: stopped ? "stop.circle" : "exclamationmark.triangle",
            title: stopped ? "The build was stopped" : "The method could not be built",
            message: stopped ? "Nothing was added to your methods."
                : (build.error?.message ?? "Something went wrong while building. Try again."),
            actionLabel: build.revise == nil ? "Describe it again" : "Try the change again",
            prominent: true) { route = .describe(revises: build.revise) }
    }

    // MARK: Asking

    /// Asks how the build stands until it has ended or the screen is left
    /// (the task ends with the view; in the background its sleep is suspended
    /// with the app, so it carries on when the athlete returns).
    private func poll() async {
        loadFailed = false
        while !Task.isCancelled {
            guard let api = appState.api else { loadFailed = true; return }
            do {
                guard let latest = try await api.fetchMethodBuild(buildId) else { missing = true; return }
                build = latest
                loadFailed = false
                if !latest.isOpen {
                    if !announced {
                        announced = true
                        if latest.isDone { AppHaptics.success() }
                        await appState.methodsChanged()
                    }
                    return
                }
            } catch {
                // What is on screen stays; only a build never seen is a failed load.
                if build == nil { loadFailed = true; return }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func cancel() async {
        guard let api = appState.api else { return }
        isCancelling = true
        defer { isCancelling = false }
        if let latest = try? await api.cancelMethodBuild(buildId) {
            build = latest
            if !latest.isOpen { await appState.loadMethods() }
        }
    }
}
