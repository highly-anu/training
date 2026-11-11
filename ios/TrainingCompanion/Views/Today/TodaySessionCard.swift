import SwiftUI

/// One planned session, located in the program.
struct TodaySession: Identifiable {
    let session: ProgramSession
    let key: String
    let weekIndex: Int
    let dayName: String
    let sessionIndex: Int
    var id: String { key }
}

/// A session on Today's day page (design-system §6.53): modality, name, time
/// and what it holds, its "…" (§6.43), and — on the session to do next —
/// Start workout, so the player is one tap from the tab. The card itself
/// opens the session.
struct TodaySessionCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var kept = KeptWorkout.shared

    let item: TodaySession
    var showsTip = false
    /// Given for the session to do next: the card leads the page and starts it.
    var onStart: (() -> Void)? = nil

    private var session: ProgramSession { item.session }
    private var color: Color { ModalityStyle.color(for: session.modality) }

    var body: some View {
        let done = appState.isSessionComplete(item.key)
        let linked = appState.linkedWorkout(forSessionKey: item.key) != nil

        VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(ModalityStyle.label(for: session.modality),
                              systemImage: ModalityStyle.icon(for: session.modality))
                            .font(.caption)
                            .foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(AppColor.Opacity.fill))
                            .clipShape(Capsule())
                        if session.isAdded {
                            // An extra the athlete added: it counts once done.
                            Text("Added").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        Spacer()
                        if linked {
                            Image(systemName: "link")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Linked to a recorded workout")
                        }
                        if done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.complete)
                                .accessibilityLabel("Done")
                        }
                    }
                    HStack(spacing: 6) {
                        // The workout icon leads the name; the capsule above keeps
                        // the modality (§6.40).
                        if let icon = session.icon, AppSymbol.custom.contains(icon) {
                            Image(symbol: icon)
                                .foregroundStyle(color)
                                .accessibilityHidden(true)
                        }
                        Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                            .font(onStart == nil ? .body : .title3).fontWeight(onStart == nil ? .medium : .semibold)
                            .foregroundStyle(done ? .secondary : .primary)
                    }
                    HStack(spacing: 12) {
                        if let mins = session.archetype?.durationEstimateMinutes {
                            Label("\(mins) min", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let test = session.testInfo {
                            // A test day says so: what it measures, not how many rows.
                            TestBadge()
                            Text("\(test.standards.count) standard\(test.standards.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            let count = session.exercises.filter { !$0.injurySkip }.count
                            Label("\(count) exercises", systemImage: "list.bullet")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // The session's actions, visible (§6.43); the card itself opens it.
                SessionActionsMenu(weekIndex: item.weekIndex, dayName: item.dayName,
                                   sessionIndex: item.sessionIndex, showsTip: showsTip)
            }
            if let onStart, !done {
                let resumes = kept.record?.target.sessionKey == item.key
                Button {
                    AppHaptics.medium()
                    onStart()
                } label: {
                    Label(resumes ? "Resume workout" : "Start workout", systemImage: "play.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .appButton(.primary)
                .tint(color)
            }
        }
        .appCard(border: done ? AppColor.complete : nil)
    }
}

/// A day with nothing planned: rest, and — today or later — room for an
/// extra session (§6.43).
struct TodayRestCard: View {
    /// "Next session: Thursday", on today's page.
    var next: String? = nil
    var day: (weekIndex: Int, dayName: String)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "battery.100.bolt")
                .font(.title2)
                .foregroundStyle(AppColor.complete)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                Text("Rest")
                    .font(.body).fontWeight(.medium)
                if let next {
                    Text("Next session: \(next)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let day {
                SessionAddButton(weekIndex: day.weekIndex, dayName: day.dayName)
            }
        }
        .appCard()
    }
}
