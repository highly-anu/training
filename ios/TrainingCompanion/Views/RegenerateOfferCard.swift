import SwiftUI

/// Shown at the top of the profile tabs that feed constraints when the
/// profile no longer matches the active program — but only when the
/// difference changes the program (design-system §6.17).
///
/// It used to offer a regenerate for any difference: adding a kettlebell no
/// session uses asked to rebuild the plan. Now the server builds the rest of
/// the program both ways (`POST /programs/constraint-change`). A change that
/// moves nothing is recorded on the program (`PATCH /user/program/constraints`)
/// and the offer never appears; one that does says how many sessions from
/// which week, and opens them in the preview — applied from there, from the
/// current week, keeping the weeks and days already behind the athlete. The
/// card used to apply them straight away as well.
struct RegenerateOfferCard: View {
    @EnvironmentObject var appState: AppState
    @State private var state: CheckState = .idle
    @State private var isRunning = false
    @State private var error: String? = nil
    @State private var preview: PreviewDraft? = nil
    @State private var previewStart = 0
    @State private var previewChanged: Set<String> = []

    private enum CheckState {
        case idle
        case checking
        case answered(ConstraintChangeResult, GenerateProgramRequest, Int)
        /// The check failed: the offer stands as it did, without knowing what moves.
        case unknown
        /// Nothing changes, but recording the settings on the program failed:
        /// say so and offer it again, never drop the difference silently.
        case adoptFailed(GenerateConstraints)
    }

    var body: some View {
        let diffs = appState.constraintDifferences
        // A real container, not a Group: a Group hands `.task` to each child,
        // so switching from "Checking…" to the card started the check again,
        // in a loop.
        VStack(alignment: .leading, spacing: 0) {
            if !diffs.isEmpty {
                offer(diffs)
            } else {
                // What the last difference came to — kept in AppState, so it
                // outlives the difference this card was mounted for.
                switch appState.profileOfferOutcome {
                case .applied(let weeks):
                    Label("Rebuilt \(weeks) week\(weeks == 1 ? "" : "s") with these settings. The previous plan is in Program ▸ History.",
                          systemImage: "checkmark.circle.fill")
                        .labelStyle(.inline)
                        .font(.footnote).foregroundStyle(.green)
                case .adopted:
                    Label("Your program doesn't change with these settings.", systemImage: "checkmark")
                        .labelStyle(.inline)
                        .font(.footnote).foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
        }
        // Toggling several items in a row asks once, after the last.
        .task(id: diffs.map { "\($0.field):\($0.profile)" }.joined(separator: ",")
                  + (appState.serverProgram?.revision ?? "")) {
            await check(diffs)
        }
        .sheet(item: $preview) { p in
            NavigationStack {
                ProgramPreviewView(mode: .regenerate(start: previewStart, changed: previewChanged),
                                   request: p.request, draft: p.draft) { applied in
                    preview = nil
                    if applied { appState.profileOfferOutcome = .applied(weeks: remaining(from: previewStart)) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { preview = nil } }
                }
            }
            .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func offer(_ diffs: [ConstraintDifference]) -> some View {
        switch state {
        case .idle, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking whether this changes your program…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        case .answered(let result, let request, let start):
            if result.affected {
                card(diffs, result: result, request: request, start: start)
            }
        case .unknown:
            card(diffs, result: nil, request: nil, start: startIndex)
        case .adoptFailed(let constraints):
            VStack(alignment: .leading, spacing: 8) {
                Text("Your program doesn't change with these settings, but recording them on it failed.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await adopt(constraints) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    /// Record the unchanged program's new settings; on a stale revision the
    /// program reloads and its new revision runs the check again.
    private func adopt(_ constraints: GenerateConstraints) async {
        switch await appState.adoptProfileConstraints(constraints) {
        case .adopted, .stale: state = .idle
        case .failed: state = .adoptFailed(constraints)
        }
    }

    private func card(_ diffs: [ConstraintDifference], result: ConstraintChangeResult?,
                      request: GenerateProgramRequest?, start: Int) -> some View {
        let tail = result?.program
        let refused = tail?.isInfeasible ?? false
        let title: String = {
            guard let result, result.comparable else { return "Your program was built for different settings" }
            if refused { return "These settings can't build the rest of your program" }
            let n = result.sessions.changed
            return "These settings change \(n) session\(n == 1 ? "" : "s")"
                + (result.firstWeekNumber.map { " from week \($0)" } ?? "")
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(diffs) { d in
                    HStack(spacing: 4) {
                        Text("\(d.label):").fontWeight(.medium)
                        Text("\(d.program) → \(d.profile)").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            if refused, let message = tail?.validation?.errors.first?.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            // Side by side when they fit, stacked on a narrow phone, never truncated.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions(tail: tail, request: request, result: result, start: start, refused: refused) }
                VStack(alignment: .leading, spacing: 8) {
                    actions(tail: tail, request: request, result: result, start: start, refused: refused)
                }
            }
            Text(start > 0
                 ? "Keeps the \(start) week\(start == 1 ? "" : "s") already behind you and rebuilds the remaining \(remaining(from: start)). The current plan stays in Program ▸ History."
                 : "Rebuilds the program's \(remaining(from: start)) weeks; the days already behind you this week keep their sessions. The current plan stays in Program ▸ History.")
                .font(.caption2).foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(tail: GeneratedProgram?, request: GenerateProgramRequest?,
                         result: ConstraintChangeResult?, start: Int, refused: Bool) -> some View {
        Button {
            Task { await openPreview(tail: tail, request: request, result: result, start: start) }
        } label: {
            HStack {
                if isRunning { ProgressView().controlSize(.small) }
                Label(isRunning ? "Building a preview…" : refused ? "See why" : "Preview changes", systemImage: "eye")
                    .labelStyle(.inline)
                    .fontWeight(.semibold)
            }
            .fixedSize()
        }
        .buttonStyle(.borderedProminent)
        .disabled(isRunning || remaining(from: start) <= 0)
    }

    private var startIndex: Int {
        let count = appState.serverProgram?.currentProgram?.weeks.count ?? 0
        return min(appState.currentWeekIndex ?? 0, max(0, count - 1))
    }
    private func remaining(from start: Int) -> Int {
        (appState.serverProgram?.currentProgram?.weeks.count ?? 0) - start
    }

    private func check(_ diffs: [ConstraintDifference]) async {
        guard !diffs.isEmpty else { state = .idle; return }
        appState.profileOfferOutcome = nil   // a new difference starts over
        state = .checking
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let (result, request, start) = try await appState.checkConstraintChange()
            if !result.affected && result.comparable {
                // The program is what the new settings would build: it now
                // says it was built for them, and the offer never appears.
                await adopt(request.constraints)
                return
            }
            state = .answered(result, request, start)
        } catch is CancellationError {
        } catch {
            state = .unknown
        }
    }

    /// The tail the check built, in the preview; without one (the check
    /// failed), one generated for it. The preview's Apply saves.
    private func openPreview(tail: GeneratedProgram?, request: GenerateProgramRequest?,
                             result: ConstraintChangeResult?, start: Int) async {
        isRunning = true
        error = nil
        do {
            if let tail, let request {
                let p = appState.regeneratePreviewDraft(tail, from: start)
                previewStart = start
                previewChanged = p.changed.union(result?.changes.map(\.id) ?? [])
                preview = PreviewDraft(request: request, draft: p.draft)
            } else {
                let p = try await appState.previewRegenerateFromCurrentWeek()
                previewStart = p.start
                previewChanged = p.changed
                preview = PreviewDraft(request: p.request, draft: p.draft)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRunning = false
    }
}
