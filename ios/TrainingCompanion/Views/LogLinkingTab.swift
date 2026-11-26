import SwiftUI

/// Log ▸ Linking: giving each planned session its recording. One section per
/// day that has a planned session — the current program's and every earlier
/// program's — and under each session the workout linked to it, the one
/// suggested for it, or nothing yet (`GET /health/linking`, design-system
/// §6.19).
///
/// A day without a session is not listed, and a day's other workouts are not
/// rows of their own: a session's Link workout… (or, once it has one, Link a
/// different workout… in its "…") lists that day's workouts, then the unlinked
/// ones of the days around it. The web drags a workout onto a session; a long
/// list on a phone is no place to drag. Every row's actions are in its "…"
/// (§6.51); the swipe and the long press are the same ones.
struct LogLinkingTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var reviewWorkout: ImportedWorkout?

    @State private var showAll = LogLinkingTab.debugShowAll
    /// The session being given a workout by hand.
    @State private var picking: Linking.SessionRow?

    var body: some View {
        let all = Linking.visible(appState.linking?.days ?? [], showAll: true)
        let days = Linking.visible(all, showAll: showAll)
        Group {
            if appState.linking == nil, let error = appState.linkingError {
                AppFailedState(message: error) {
                    appState.linkingError = nil
                    await appState.loadLinking()
                }
            } else if appState.linking == nil {
                AppLoadingState(shape: .list, label: "Loading links")
            } else if all.isEmpty {
                AppEmptyState(icon: "link", title: "Nothing to link yet",
                              message: "Once you have a program, each day's planned sessions show here with the workouts recorded for them.")
            } else {
                List {
                    Section { scopeLine(open: all.filter(Linking.toLink).count) }
                    if days.isEmpty {
                        Section {
                            Text("Every recorded workout has its session.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(days) { day in
                        Section { rows(for: day) } header: { header(for: day) }
                    }
                }
            }
        }
        .task {
            if appState.linking == nil { await appState.loadLinking() }
            #if DEBUG
            // `SIMCTL_CHILD_TC_LINKING_PICK=1` opens the first session's workout picker.
            if ProcessInfo.processInfo.environment["TC_LINKING_PICK"] == "1" {
                picking = Linking.visible(appState.linking?.days ?? [], showAll: true)
                    .first.flatMap { Linking.rows(for: $0).first }
            }
            #endif
        }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadWorkouts()
                await appState.loadLinking()
            }
        }
        .sheet(item: $picking) { row in
            LinkWorkoutPicker(row: row,
                              candidates: appState.linking.map { Linking.candidates($0, for: row) }
                                  ?? Linking.Candidates(sameDay: [], otherDays: [])) { workout in
                act { await appState.link(workoutId: workout.id, to: row.session, replacing: row.linked?.id) }
            }
        }
    }

    /// Debug builds open on All days with `SIMCTL_CHILD_TC_LINKING_ALL=1`:
    /// the simulator cannot be tapped from a script.
    private static var debugShowAll: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TC_LINKING_ALL"] == "1"
        #else
        return false
        #endif
    }

    // MARK: - Pieces

    private func scopeLine(open: Int) -> some View {
        AppAdaptiveStack {
            Text(open == 0 ? "Nothing waiting" : "\(open) \(open == 1 ? "day" : "days") to link")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(showAll ? "Days to link" : "All days") {
                AppHaptics.selection()
                withAnimation(AppAnimation.springStandard) { showAll.toggle() }
            }
            .font(.subheadline)
        }
    }

    private func header(for day: LinkingDay) -> some View {
        AppAdaptiveStack(spacing: 6) {
            Text(Self.dayTitle(day.date))
            if let label = day.programLabel {
                Text("· \(label)").lineLimit(2)
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
        ForEach(Linking.rows(for: day)) { row in
            if let w = row.linked {
                HStack {
                    pair(row.session, w, linked: true)
                    Spacer(minLength: 0)
                    moreMenu(row, workout: w)
                }
                .swipeActions {
                    Button("Unlink", role: .destructive) { act { await appState.unlink(workoutId: w.id) } }
                }
                .contextMenu { menuItems(row, workout: w) }
            } else if let w = row.suggested {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        pair(row.session, w, linked: false)
                        Spacer(minLength: 0)
                        moreMenu(row, workout: w)
                    }
                    AppAdaptiveStack {
                        Button("Link") { act { await appState.link(workoutId: w.id, to: row.session) } }
                            .appButton(.primary)
                            .accessibilityLabel("Link \(w.title) to \(row.session.name)")
                        Button("Not this") {
                            act { await appState.dismissLink(workoutId: w.id, sessionKey: row.session.key) }
                        }
                        .appButton(.secondary)
                    }
                    .font(.subheadline)
                }
                .contextMenu { menuItems(row, workout: w) }
            } else {
                // The action under the session at the accessibility sizes (§6.57).
                AppAdaptiveStack {
                    VStack(alignment: .leading, spacing: 4) {
                        sessionLine(row.session)
                        if !day.workouts.isEmpty {
                            Text(day.workouts.count == 1 ? "1 workout recorded this day"
                                                         : "\(day.workouts.count) workouts recorded this day")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Link workout…") {
                        AppHaptics.selection()
                        picking = row
                    }
                    .appButton(.secondary).font(.subheadline)
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel("Link a workout to \(row.session.name)")
                }
            }
        }
    }

    /// The session, then the workout that is (or may be) its recording.
    private func pair(_ s: LinkSession, _ w: LinkWorkout, linked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sessionLine(s)
            HStack(spacing: 8) {
                Image(systemName: linked ? "checkmark.circle.fill" : "arrow.turn.down.right")
                    .foregroundStyle(linked ? AppColor.complete : Color.secondary)
                    .appSymbolReplace(value: linked)
                    .frame(minWidth: 22)
                Self.workoutLine(w, linkedTo: linked ? s : nil)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(linked ? "\(s.name), linked to \(w.title)" : "\(s.name) may be \(w.title)")
    }

    /// A workout linked to a session shows that session's icon and colour, so
    /// the pair reads as one; any other leads with what the device recorded.
    static func workoutLine(_ w: LinkWorkout, linkedTo s: LinkSession? = nil) -> some View {
        let sessionIcon = s?.icon.flatMap { AppSymbol.custom.contains($0) ? $0 : nil }
        return HStack(spacing: 8) {
            Image(symbol: sessionIcon ?? ActivityIcon.forWorkout(activityType: w.activityType ?? "",
                                                                 modalityId: w.inferredModalityId))
                .foregroundStyle(ModalityStyle.color(for: (sessionIcon != nil ? s?.modality : w.inferredModalityId) ?? ""))
                .frame(minWidth: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(w.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(workoutDetail(w)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sessionLine(_ s: LinkSession) -> some View {
        HStack(spacing: 8) {
            Image(symbol: SessionIcon.symbol(icon: s.icon, modality: s.modality ?? ""))
                .foregroundStyle(ModalityStyle.color(for: s.modality ?? ""))
                .frame(minWidth: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(Self.sessionDetail(s)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The row's visible "…": Open Workout when the phone has the recording,
    /// another workout for the session, and Unlink for a linked pair.
    private func moreMenu(_ row: Linking.SessionRow, workout w: LinkWorkout) -> some View {
        Menu { menuItems(row, workout: w) } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(row.session.name) actions")
    }

    @ViewBuilder
    private func menuItems(_ row: Linking.SessionRow, workout w: LinkWorkout) -> some View {
        if let full = appState.importedWorkouts.first(where: { $0.id == w.id }) {
            Button("Open Workout", systemImage: "arrow.up.right") { reviewWorkout = full }
        }
        Button("Link a Different Workout…", systemImage: "arrow.left.arrow.right") { picking = row }
        if row.linked != nil {
            Button("Unlink", systemImage: "link.badge.plus", role: .destructive) {
                act { await appState.unlink(workoutId: w.id) }
            }
        }
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

/// The workouts a session can be given by hand: its own day's first, then
/// the unlinked ones of the days around it (`Linking.candidates`).
private struct LinkWorkoutPicker: View {
    let row: Linking.SessionRow
    let candidates: Linking.Candidates
    let onPick: (LinkWorkout) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    AppEmptyState(icon: "figure.run", title: "No other workout",
                                  message: "Nothing else was recorded on \(LogLinkingTab.dayTitle(row.session.date)) or the days around it.")
                } else {
                    List {
                        if !candidates.sameDay.isEmpty {
                            Section(LogLinkingTab.dayTitle(row.session.date)) {
                                ForEach(candidates.sameDay) { line($0, dated: false) }
                            }
                        }
                        if !candidates.otherDays.isEmpty {
                            Section("Other days") {
                                ForEach(candidates.otherDays) { line($0, dated: true) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(row.session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .appSheet(.flexible)
    }

    private func line(_ c: Linking.Candidate, dated: Bool) -> some View {
        Button {
            onPick(c.workout)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    LogLinkingTab.workoutLine(c.workout)
                    let notes = [dated ? LogLinkingTab.dayTitle(c.workout.date) : nil, c.note].compactMap { $0 }
                    if !notes.isEmpty {
                        Text(notes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text("Link").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link \(c.workout.title) to \(row.session.name)")
    }
}
