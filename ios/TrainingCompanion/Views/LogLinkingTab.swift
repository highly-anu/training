import SwiftUI

/// Log ▸ Linking: one section per day, the workouts recorded that day beside
/// the sessions planned for it — the current program's and every earlier
/// program's — with the links already made and same-day suggestions
/// (`GET /health/linking`, design-system §6.19).
///
/// Suggestions stay inside a day; linking across days is the athlete's call:
/// tap Link… on a workout, then any session on any day. The web drags a
/// workout onto a session; a long list on a phone is no place to drag.
struct LogLinkingTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var reviewWorkout: ImportedWorkout?

    @State private var showAll = false
    /// The workout being linked by hand, while the athlete picks its session.
    @State private var picking: LinkWorkout?

    var body: some View {
        let all = appState.linking?.days ?? []
        let days = Linking.visible(all, showAll: showAll)
        Group {
            if appState.linking == nil, let error = appState.linkingError {
                empty(icon: "exclamationmark.triangle", title: "Could not load",
                      message: error, actionLabel: "Try again") {
                    appState.linkingError = nil
                    Task { await appState.loadLinking() }
                }
            } else if appState.linking == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if all.isEmpty {
                empty(icon: "link", title: "Nothing to link yet",
                      message: "Once you have a program and recorded workouts, each day shows them side by side here.")
            } else {
                List {
                    Section {
                        scopeLine(open: all.filter(\.needsAttention).count)
                        if let picking { pickingBanner(picking) }
                    }
                    if days.isEmpty {
                        Section {
                            Text("Every day is linked.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(days) { day in
                        Section { rows(for: day) } header: { header(for: day) }
                    }
                }
            }
        }
        .task { if appState.linking == nil { await appState.loadLinking() } }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadWorkouts()
                await appState.loadLinking()
            }
        }
    }

    // MARK: - Pieces

    private func scopeLine(open: Int) -> some View {
        HStack {
            Text(open == 0 ? "Nothing waiting" : "\(open) \(open == 1 ? "day" : "days") to link")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(showAll ? "Days to link" : "All days") {
                AppHaptics.selection()
                withAnimation(AppAnimation.springStandard) { showAll.toggle() }
            }
            .font(.subheadline)
        }
    }

    private func pickingBanner(_ workout: LinkWorkout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Linking \(workout.title)").font(.subheadline.weight(.semibold))
                Text("Tap a session on any day.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { picking = nil }.font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func header(for day: LinkingDay) -> some View {
        HStack(spacing: 6) {
            Text(Self.dayTitle(day.date))
            if let label = day.programLabel {
                Text("· \(label)").lineLimit(1)
            }
            if day.historical {
                Text("earlier program")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }
        }
    }

    @ViewBuilder
    private func rows(for day: LinkingDay) -> some View {
        ForEach(day.links) { pair in
            pairRow(pair.workout, pair.session, linked: true)
                .swipeActions {
                    Button("Unlink", role: .destructive) { act { await appState.unlink(workoutId: pair.workout.id) } }
                }
                .contextMenu {
                    Button("Unlink", systemImage: "link.badge.plus") { act { await appState.unlink(workoutId: pair.workout.id) } }
                    openButton(pair.workout)
                }
        }
        ForEach(day.suggestions) { s in
            VStack(alignment: .leading, spacing: 10) {
                pairRow(s.workout, s.session, linked: false)
                HStack {
                    Button("Link") { act { await appState.link(workoutId: s.workout.id, to: s.session) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Link \(s.workout.title) to \(s.session.name)")
                    Button("Not this") {
                        act { await appState.dismissLink(workoutId: s.workout.id, sessionKey: s.session.key) }
                    }
                    .buttonStyle(.bordered)
                    if picking != nil { pickTarget(s.session) }
                }
                .font(.subheadline)
            }
            .contextMenu { openButton(s.workout) }
        }
        ForEach(day.workouts) { w in
            HStack {
                workoutLine(w)
                Spacer()
                Button(picking?.id == w.id ? "Picking…" : "Link…") {
                    AppHaptics.selection()
                    picking = picking?.id == w.id ? nil : w
                }
                .buttonStyle(.bordered).font(.subheadline)
                .accessibilityLabel("Select \(w.title) to link")
            }
            .contextMenu { openButton(w) }
        }
        ForEach(day.sessions) { s in
            HStack {
                sessionLine(s)
                Spacer()
                if picking != nil { pickTarget(s) }
            }
        }
        ForEach(day.elsewhere) { e in
            VStack(alignment: .leading, spacing: 2) {
                workoutLine(e.workout)
                Text("Linked to a session not shown here").font(.caption).foregroundStyle(.secondary)
            }
            .contextMenu { openButton(e.workout) }
        }
        ForEach(day.declined) { w in
            HStack {
                workoutLine(w)
                Spacer()
                Text("No session").font(.caption).foregroundStyle(.secondary)
            }
            .swipeActions {
                Button("Link…") { picking = w }.tint(.accentColor)
            }
            .contextMenu { openButton(w) }
        }
    }

    private func pickTarget(_ session: LinkSession) -> some View {
        Button("Link here") {
            guard let w = picking else { return }
            picking = nil
            act { await appState.link(workoutId: w.id, to: session) }
        }
        .buttonStyle(.borderedProminent).font(.subheadline)
        .accessibilityLabel("Link to \(session.name)")
    }

    private func pairRow(_ w: LinkWorkout, _ s: LinkSession, linked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            workoutLine(w, linkedTo: linked ? s : nil)
            HStack(spacing: 8) {
                Image(systemName: linked ? "checkmark.circle.fill" : "arrow.turn.down.right")
                    .foregroundStyle(linked ? Color.green : Color.secondary)
                    .frame(width: 22)
                sessionLine(s)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(linked ? "\(w.title) linked to \(s.name)" : "\(w.title) may be \(s.name)")
    }

    /// A workout linked to a session shows that session's icon and colour, so
    /// the pair reads as one; any other leads with what the device recorded.
    private func workoutLine(_ w: LinkWorkout, linkedTo s: LinkSession? = nil) -> some View {
        let sessionIcon = s?.icon.flatMap { AppSymbol.custom.contains($0) ? $0 : nil }
        return HStack(spacing: 8) {
            Image(symbol: sessionIcon ?? ActivityIcon.forWorkout(activityType: w.activityType ?? "",
                                                                 modalityId: w.inferredModalityId))
                .foregroundStyle(ModalityStyle.color(for: (sessionIcon != nil ? s?.modality : w.inferredModalityId) ?? ""))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(w.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(Self.workoutDetail(w)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sessionLine(_ s: LinkSession) -> some View {
        HStack(spacing: 8) {
            Image(symbol: SessionIcon.symbol(icon: s.icon, modality: s.modality ?? ""))
                .foregroundStyle(ModalityStyle.color(for: s.modality ?? ""))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.subheadline).lineLimit(1)
                Text(Self.sessionDetail(s)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func openButton(_ w: LinkWorkout) -> some View {
        if let full = appState.importedWorkouts.first(where: { $0.id == w.id }) {
            Button("Open Workout", systemImage: "arrow.up.right") { reviewWorkout = full }
        }
    }

    private func empty(icon: String, title: String, message: String,
                       actionLabel: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The change shows at once (AppState applies it before the request);
    /// the list stays live while the server's reload catches up.
    private func act(_ work: @escaping () async -> Void) {
        AppHaptics.light()
        Task { await work() }
    }

    // MARK: - Text

    private static let parse: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A workout's start as the server stores it: ISO 8601, with or without
    /// fractional seconds, or Postgres's "2026-10-13 20:00:00+02:00".
    static func instant(_ raw: String) -> Date? {
        let iso = raw.count > 10 && raw[raw.index(raw.startIndex, offsetBy: 10)] == " "
            ? raw.prefix(10) + "T" + raw.dropFirst(11) : Substring(raw)
        let f = ISO8601DateFormatter()
        if let d = f.date(from: String(iso)) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: String(iso))
    }

    static func dayTitle(_ date: String) -> String {
        guard let d = parse.date(from: date) else { return date }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func workoutDetail(_ w: LinkWorkout) -> String {
        var parts: [String] = []
        if let start = w.startTime, let d = Self.instant(start) {
            parts.append(d.formatted(date: .omitted, time: .shortened))
        }
        if let m = w.durationMinutes, m > 0 { parts.append("\(Int(m.rounded())) min") }
        return parts.joined(separator: " · ")
    }

    static func sessionDetail(_ s: LinkSession) -> String {
        var parts = [ModalityStyle.label(for: s.modality ?? "")]
        if let m = s.durationMinutes, m > 0 { parts.append("\(Int(m.rounded())) min planned") }
        if s.completedAt != nil { parts.append("done") }
        return parts.joined(separator: " · ")
    }
}
