import SwiftUI

/// What waits for the athlete's answer on Today: workouts that look like
/// planned sessions, and results logged sessions suggest. The first three of
/// each live here; the rest are in Log ▸ Linking and Profile ▸ Standards.
struct TodayInbox: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter

    /// A suggestion's "Review" lands on the workout, whose Link to Session
    /// flow is the one matching UI the app has.
    let onReview: (ImportedWorkout) -> Void

    var body: some View {
        suggestions
        resultsToConfirm
    }

    // MARK: - Match suggestions

    /// Workouts the server matched to a planned session too weakly to confirm
    /// on its own (Garmin webhook, Apple Health relay). They were written and
    /// shown nowhere; this is where the decision gets made. A workout the
    /// athlete has since linked drops out without waiting for the next load.
    @ViewBuilder
    private var suggestions: some View {
        let pending = appState.pendingMatchSuggestions()
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(pending.count == 1
                             ? "1 workout looks like a planned session"
                             : "\(pending.count) workouts look like planned sessions")
                VStack(spacing: AppMetrics.gapSmall) {
                    ForEach(pending.prefix(3), id: \.suggestion.id) { item in
                        SuggestionRowView(
                            suggestion: item.suggestion, workout: item.workout,
                            planned: plannedSession(for: item.suggestion.sessionKey),
                            // Accept here as in Log ▸ Linking and on the web's
                            // Today card — the decision belongs where the
                            // suggestion is shown.
                            onAccept: {
                                Task { try? await appState.matchAndComplete(workout: item.workout,
                                                                            sessionKey: item.suggestion.sessionKey) }
                            },
                            onReview: { onReview(item.workout) },
                            onDismiss: { Task { await appState.dismissSuggestion(workoutId: item.workout.id) } })
                    }
                    if pending.count > 3 {
                        more("All \(pending.count) in Log", hint: "Opens Log, Linking") { router.showLog(.linking) }
                    }
                }
            }
        }
    }

    // MARK: - Results to confirm

    /// Results logged sessions suggest — a test slot's outcome, or a single
    /// that beat the current result — waiting for Save or "Not a test" (the
    /// web's `ResultsToConfirmCard`).
    @ViewBuilder
    private var resultsToConfirm: some View {
        let pending = appState.standardSuggestions
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(pending.count == 1 ? "1 result to confirm" : "\(pending.count) results to confirm")
                VStack(spacing: AppMetrics.gapSmall) {
                    ForEach(pending.prefix(3)) { s in
                        StandardSuggestionRow(suggestion: s)
                            .appCard(compact: true)
                    }
                    if pending.count > 3 {
                        more("All \(pending.count) in Profile", hint: "Opens Profile, Standards") {
                            router.showProfile(.standards)
                        }
                    }
                }
            }
        }
    }

    private func more(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.caption)
            .appTapSlop()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHint(hint)
    }

    /// "3-Monday-0" → the planned session, from the loaded program.
    private func plannedSession(for sessionKey: String) -> ProgramSession? {
        let parts = sessionKey.split(separator: "-")
        guard parts.count == 3, let weekNum = Int(parts[0]), let idx = Int(parts[2]) else { return nil }
        let dayName = String(parts[1])
        guard let week = appState.allWeeks.first(where: { $0.weekNumber == weekNum }),
              let sessions = week.schedule[dayName], idx < sessions.count else { return nil }
        return sessions[idx]
    }
}
