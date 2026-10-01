import SwiftUI

/// "Your program was built for different settings." Shown at the top of the
/// profile tabs that feed constraints when the profile no longer matches the
/// active program; one tap regenerates from the current week with the new
/// settings and keeps the weeks already behind the athlete (design-system
/// §6.17). The Program settings sheet offers the same action.
struct RegenerateOfferCard: View {
    @EnvironmentObject var appState: AppState
    @State private var isRunning = false
    @State private var error: String? = nil
    @State private var regenerated: Int? = nil

    var body: some View {
        let diffs = appState.constraintDifferences
        if let regenerated {
            Label("Regenerated \(regenerated) week\(regenerated == 1 ? "" : "s") with your current settings.",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        } else if !diffs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your program was built for different settings")
                    .font(.subheadline).fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(diffs) { d in
                        HStack(spacing: 4) {
                            Text("\(d.label):").fontWeight(.medium)
                            Text("\(d.program) → \(d.profile)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().controlSize(.small) }
                        Text(isRunning ? "Regenerating…" : "Regenerate from week \(startWeek)")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || remaining <= 0)
                Text("Keeps the \(startIndex) week\(startIndex == 1 ? "" : "s") already behind you and rebuilds the remaining \(remaining). The current plan stays in Program ▸ History.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var startIndex: Int {
        let count = appState.serverProgram?.currentProgram?.weeks.count ?? 0
        return min(appState.currentWeekIndex ?? 0, max(0, count - 1))
    }
    /// The position, not the stored week number: a partial regenerate numbers
    /// its tail from 1 again, so the number can repeat (see Program History).
    private var startWeek: Int { startIndex + 1 }
    private var remaining: Int {
        (appState.serverProgram?.currentProgram?.weeks.count ?? 0) - startIndex
    }

    private func run() async {
        isRunning = true
        error = nil
        do {
            regenerated = try await appState.regenerateFromCurrentWeek()
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
        isRunning = false
    }
}
