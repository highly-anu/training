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
/// which week, and opens them in the preview or applies them from the current
/// week, keeping the weeks and days already behind the athlete.
struct RegenerateOfferCard: View {
    @EnvironmentObject var appState: AppState
    @State private var state: CheckState = .idle
    @State private var isRunning = false
    @State private var error: String? = nil
    @State private var regenerated: Int? = nil
    @State private var preview: PreviewDraft? = nil
    @State private var previewStart = 0
    @State private var previewChanged: Set<String> = []

    private enum CheckState {
        case idle
        case checking
        case answered(ConstraintChangeResult, GenerateProgramRequest, Int)
        /// The check failed: the offer stands as it did, without knowing what moves.
        case unknown
    }

    var body: some View {
        let diffs = appState.constraintDifferences
        // A real container, not a Group: a Group hands `.task` to each child,
        // so switching from "Checking…" to the card started the check again,
        // in a loop.
        VStack(alignment: .leading, spacing: 0) {
            if let regenerated {
                Label("Regenerated \(regenerated) week\(regenerated == 1 ? "" : "s") with your current settings.",
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            } else if diffs.isEmpty {
                if appState.adoptedProfileConstraints {
                    Label("Your program doesn't change with these settings.", systemImage: "checkmark")
                        .labelStyle(.inline)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                offer(diffs)
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
                    if applied { regenerated = (appState.serverProgram?.currentProgram?.weeks.count ?? 0) - previewStart }
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
        if let tail, let request {
            Button {
                previewStart = start
                previewChanged = Set(result?.changes.map(\.id) ?? [])
                preview = PreviewDraft(request: request, draft: tail)
            } label: {
                Label(refused ? "See why" : "Preview changes", systemImage: "eye")
                    .labelStyle(.inline)
                    .fixedSize()
            }
            .buttonStyle(refused ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
        }
        if !refused {
            Button {
                Task { await apply(tail: tail, start: start) }
            } label: {
                HStack {
                    if isRunning { ProgressView().controlSize(.small) }
                    Text(isRunning ? "Applying…" : "Apply from week \(start + 1)").fontWeight(.semibold)
                }
                .fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || remaining(from: start) <= 0)
        }
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
        appState.adoptedProfileConstraints = false
        state = .checking
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let (result, request, start) = try await appState.checkConstraintChange()
            if !result.affected && result.comparable {
                // The program is what the new settings would build: it now
                // says it was built for them, and the offer never appears.
                if await appState.adoptProfileConstraints(request.constraints) {
                    state = .idle
                    return
                }
            }
            state = .answered(result, request, start)
        } catch is CancellationError {
        } catch {
            state = .unknown
        }
    }

    /// The tail the check built, spliced and saved; without one (the check
    /// failed), a regenerate as before.
    private func apply(tail: GeneratedProgram?, start: Int) async {
        isRunning = true
        error = nil
        do {
            if let tail {
                regenerated = try appState.applyRegeneratedTail(tail, from: start)
            } else {
                regenerated = try await appState.regenerateFromCurrentWeek()
            }
            AppHaptics.success()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRunning = false
    }
}

/// `.buttonStyle` takes one concrete style; this picks between two.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
