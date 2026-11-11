import SwiftUI

// MARK: - Program Builder Flow

/// The four steps of a new program, one screen each, under a step indicator
/// in the bar and over one glass action — Next, then Preview program on the
/// last (design-system §6.55). Until 1.39 the action was a text button in the
/// corner of the bar, the last step's a row at the end of its list, and
/// nothing said how many steps there were.
struct ProgramBuilderFlow: View {
    static let stepTitles = ["Methodology", "Schedule", "Constraints", "Review"]

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var builder = BuilderState()
    @State private var step = 1

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1: BuilderStep1PhilosophyView(builder: builder)
                case 2: BuilderStep2ScheduleView(builder: builder)
                case 3: BuilderStep3ConstraintsView(builder: builder)
                case 4: BuilderStep4ReviewView(builder: builder)
                default: EmptyView()
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .task {
                guard let launch = BuilderDebugLaunch.current else { return }
                await appState.loadPhilosophiesIfNeeded()
                if let pick = appState.philosophies.first(where: { $0.id == launch.philosophyId }),
                   builder.lanes.isEmpty {
                    builder.toggle(pick)
                }
                if builder.isStep1Valid { step = launch.step }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 1 {
                        Button("Back") { step -= 1 }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    BuilderStepIndicator(step: step, titles: Self.stepTitles)
                }
            }
            .appActionBar {
                Button {
                    if step < 4 { step += 1 } else { Task { await generateProgram() } }
                } label: {
                    Group {
                        if builder.isGenerating {
                            ProgressView()
                        } else if step < 4 {
                            Text("Next")
                        } else {
                            Label("Preview program", systemImage: "eye")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .appButton(.primary)
                .disabled(!canAdvance || builder.isGenerating)
            }
            .navigationDestination(item: $builder.preview) { p in
                ProgramPreviewView(mode: .new, request: p.request, draft: p.draft,
                                   onEditSchedule: {
                                       builder.preview = nil
                                       step = 2
                                   }) { started in
                    if started { builder.didSucceed = true }
                }
            }
        }
        .task {
            await appState.loadPhilosophiesIfNeeded()
            await appState.loadInjuryFlagsIfNeeded()
            // Pre-fill constraints from profile
            builder.constraints.trainingLevel = appState.profile.trainingLevel
            builder.constraints.equipment = appState.profile.equipment
            builder.constraints.injuryFlags = appState.profile.injuryFlags
        }
        .onChange(of: builder.didSucceed) { _, succeeded in
            if succeeded { dismiss() }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return builder.isStep1Valid
        case 4: return builder.entryReady(in: appState.philosophies)
        default: return true
        }
    }

    private func generateProgram() async {
        guard builder.isComposed || builder.selectedPhilosophyId != nil else { return }
        builder.isGenerating = true
        builder.generationError = nil

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let startStr = dayFmt.string(from: builder.startDate)
        let eventStr = builder.eventDate.map { dayFmt.string(from: $0) }

        // The track and its start phase, by id. The phase picker used to send
        // `phase` only, a key the server never read, so every phone-built
        // program started wherever the server defaulted.
        var constraints = builder.constraints
        constraints.trackId = builder.selectedTrackId
        constraints.startPhase = builder.eventDate == nil ? builder.startPhaseId : nil
        constraints.phase = nil
        constraints.trainingPhase = nil

        // A draft: nothing is saved until the preview's Start. This used to
        // post `persist: true` and throw the answer away, so a refusal kept
        // the old program with nothing said.
        // Several tracks: each its own track and start phase (none with an
        // event date, which puts every track's last phase on it).
        let total = builder.lanes.reduce(0) { $0 + $1.weight }
        let lanes: [ProgramLane]? = builder.isComposed ? builder.lanes.map {
            ProgramLane(philosophyId: $0.philosophyId, trackId: $0.trackId,
                        weight: $0.weight / (total > 0 ? total : 1),
                        startPhase: builder.eventDate == nil ? $0.startPhaseId : nil)
        } : nil
        if lanes != nil { constraints.trackId = nil; constraints.startPhase = nil }
        let request = GenerateProgramRequest(
            philosophyId: lanes == nil ? builder.selectedPhilosophyId : nil,
            lanes: lanes,
            constraints: constraints,
            numWeeks: builder.numWeeks,
            startDate: startStr,
            eventDate: eventStr,
            persist: false
        )
        defer { builder.isGenerating = false }
        guard let api = appState.api else {
            builder.generationError = "Sign in to generate a program."
            return
        }
        do {
            // A refusal is previewed too: it says what alone would let it build.
            let draft = try await api.generateProgramPreview(request)
            builder.preview = PreviewDraft(request: request, draft: draft)
        } catch {
            builder.generationError = "Generation failed. Please try again."
        }
    }
}

/// Where the athlete is in the builder: "Step 2 of 4 · Schedule" over one
/// segment per step, in the navigation bar.
struct BuilderStepIndicator: View {
    let step: Int
    let titles: [String]

    var body: some View {
        VStack(spacing: AppMetrics.gapTight) {
            Text("Step \(step) of \(titles.count) · \(titles[min(max(step, 1), titles.count) - 1])")
                .font(.caption).fontWeight(.semibold)
            HStack(spacing: AppMetrics.gapTight) {
                ForEach(1...titles.count, id: \.self) { n in
                    Capsule()
                        .fill(n <= step ? AnyShapeStyle(AppColor.accent) : AnyShapeStyle(.quaternary))
                        .frame(width: 28, height: 4)
                }
            }
        }
        .animation(AppAnimation.springSnappy, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(titles.count), \(titles[min(max(step, 1), titles.count) - 1])")
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
/// Debug builds open the builder on launch with
/// `SIMCTL_CHILD_TC_BUILDER=<step>[:<philosophy id>]` — the builder is behind
/// a tap, and the Simulator's window cannot be scripted.
struct BuilderDebugLaunch {
    let step: Int
    let philosophyId: String?

    static var current: BuilderDebugLaunch? {
        guard let value = ProcessInfo.processInfo.environment["TC_BUILDER"], !value.isEmpty else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        return BuilderDebugLaunch(step: min(max(Int(parts[0]) ?? 1, 1), 4),
                                  philosophyId: parts.count > 1 ? parts[1] : nil)
    }
}
#endif
