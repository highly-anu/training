import SwiftUI

/// Program ▸ Overview: what the plan is, as the web's Program ▸ Overview
/// shows it — the methodology it comes from, where the athlete is in it, its
/// phases in the methodology's own words, and the modality weights the
/// schedule was allocated from. A summary of two cards: each phase opens its
/// own screen (`PhaseDetailView`), and the phases side by side open Compare
/// phases (`PhaseMatrixView`) — design-system §6.26. The weeks themselves are
/// on Calendar (information-architecture.md §2).
struct ProgramOverviewTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @State private var route: OverviewRoute?
    /// The leading column of a Phases row: the phase's dot, Compare's symbol.
    @ScaledMetric(relativeTo: .subheadline) private var markWidth: CGFloat = 16

    /// A screen the Phases card pushes: the n-th phase segment, or Compare phases.
    enum OverviewRoute: Hashable {
        case phase(Int)
        case compare
    }

    /// The server's per-phase summary (`phase_summary`); empty for an older server.
    private var summaries: [PhaseSummary] {
        PhaseSummary.list(from: appState.serverProgram?.currentProgram?.extra)
    }

    var body: some View {
        Group {
            if appState.allWeeks.isEmpty {
                ContentUnavailableView(
                    "No program",
                    systemImage: "calendar",
                    description: Text("Generate a program on Calendar to see its phases and priorities.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard
                        if let program = appState.serverProgram?.currentProgram, program.compositionLanes.count > 1 {
                            CompositionTracks(program: program)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        phasesCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .navigationDestination(item: $route) { destination($0) }
        .task { await appState.loadPhilosophiesIfNeeded() }
        .task { applyPendingPhase() }
        .onChange(of: router.pendingProgramPhase) { applyPendingPhase() }
        .onChange(of: appState.allWeeks.count) { applyPendingPhase() }
    }

    // MARK: - Header

    /// The shared program header (§6.28), as on Analytics ▸ Program, with
    /// what the plan is rather than how it is going: where the athlete is in
    /// it, the settings it was built for, and the priority mix.
    private var headerCard: some View {
        let cards = appState.programMethodologies()
        let weeks = appState.allWeeks
        // No phase row before the start or after the end, as on Analytics ▸
        // Program (the server's current week is None there too); `?? 0` read
        // a finished block as "Week 1/16". The track is the current week's,
        // else the first week's.
        let current = appState.currentWeekIndex.flatMap { weeks.indices.contains($0) ? $0 : nil }
        let week = current.map { weeks[$0] } ?? weeks.first
        return ProgramHeaderCard(
            name: cards.isEmpty ? "Program" : cards.map(\.name).joined(separator: " + "),
            methodologies: cards,
            phase: current.map { i in .init(label: weeks[i].phaseLabel, kind: weeks[i].phase, week: i + 1,
                                            totalWeeks: weeks.count, isDeload: weeks[i].isDeload) },
            tags: headerTags(cards: cards, week: week)
        ) {
            planFooter(weeks: weeks, current: current)
        }
    }

    /// Only the track, when the methodology offers more than one. How it
    /// trains — progression and intensity model — is the methodology sheet's
    /// (§6.18, the book), and Analytics ▸ Program's header names the framework;
    /// on Overview the three rows repeated the phase's own name.
    private func headerTags(cards: [PhilosophyCard], week: ProgramWeek?) -> [ProgramHeader.Tag] {
        // A composition: every track.
        let lanes = appState.serverProgram?.currentProgram?.compositionLanes ?? []
        if lanes.count > 1 {
            return lanes.map { .init(icon: "arrow.triangle.branch", text: $0.name) }
        }
        // The methodology whose track this week runs; a blend's heaviest otherwise.
        let lead = cards.first { card in card.tracks?.contains { $0.id == week?.trackId } ?? false } ?? cards.first
        guard let track = lead?.track(week?.trackId), (lead?.tracks?.count ?? 0) > 1 else { return [] }
        return [.init(icon: "arrow.triangle.branch", text: track.name)]
    }

    /// The weeks as one bar from the first day to the last, what the program
    /// was built for — days and session length, the event — and the priority
    /// mix, with no verdict beside them; Analytics ▸ Program holds those. The
    /// number of weeks is the phase row's "1/12" and the bar's length.
    private func planFooter(weeks: [ProgramWeek], current: Int?) -> some View {
        let constraints = appState.programConstraints
        let days = ProgramConstraintsDiff.int(constraints["days_per_week"])
        let minutes = ProgramConstraintsDiff.int(constraints["session_time_minutes"])
        let event = shortDate(appState.serverProgram?.eventDate)
        let shares = ProgramPriorities.shares(from: appState.serverProgram?.currentProgram?.extra)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                PhaseProgressBar(weeks: weeks, currentIndex: current, showsLabels: false)
                if let span = dateSpan(weekCount: weeks.count) {
                    HStack {
                        Text(span.start)
                        Spacer()
                        Text(span.end)
                    }
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(span.start) to \(span.end)")
                }
            }
            if days != nil || minutes != nil || event != nil {
                HStack(alignment: .top, spacing: 32) {
                    if let days {
                        ProgramHeaderStat(icon: "repeat", value: "\(days)", unit: "days/wk",
                                          accessibility: "\(days) days a week")
                    }
                    if let minutes {
                        ProgramHeaderStat(icon: "clock", value: "\(minutes)", unit: "min",
                                          accessibility: "\(minutes) minute sessions")
                    }
                    if let event {
                        ProgramHeaderStat(icon: "flag.checkered", value: event, unit: "event",
                                          accessibility: "Event \(event)")
                    }
                }
            }
            if !shares.isEmpty {
                Divider()
                PriorityMixBar(shares: shares)
            }
        }
        .padding(.top, 2)
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func shortDate(_ iso: String?) -> String? {
        iso.flatMap(Self.isoDay.date(from:)).map { $0.formatted(.dateTime.day().month(.abbreviated)) }
    }

    /// "5 Oct" and "24 Jan": the start date and the last day of the last week.
    private func dateSpan(weekCount: Int) -> (start: String, end: String)? {
        guard let start = appState.serverProgram?.programStartDate.flatMap(Self.isoDay.date(from:)),
              weekCount > 0,
              let end = Calendar.current.date(byAdding: .day, value: weekCount * 7 - 1, to: start) else { return nil }
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return (start.formatted(fmt), end.formatted(fmt))
    }

    // MARK: - Phases

    /// One row per phase, in order; a row with the server's summary opens the
    /// phase's screen. Compare phases closes the card when there is more than
    /// one phase to compare.
    private var phasesCard: some View {
        let weeks = appState.allWeeks
        let segments = PhaseSegment.segments(of: weeks)
        let current = appState.currentWeekIndex ?? -1
        let summaries = self.summaries
        return AnalyticsCard(header: "Phases") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                    if index > 0 { Divider() }
                    phaseRow(seg, index: index, weeks: weeks, isCurrent: seg.weekIndices.contains(current),
                             opens: PhaseSummary.forSegment(index, of: summaries, segmentCount: segments.count) != nil)
                }
                if summaries.count > 1 {
                    Divider()
                    compareRow
                }
            }
        }
    }

    private func phaseRow(_ seg: PhaseSegment, index: Int, weeks: [ProgramWeek], isCurrent: Bool,
                          opens: Bool) -> some View {
        let color = PhaseStyle.color(for: seg.kind)
        let focus = philosophyPhase(for: seg, weeks: weeks)?.focus.flatMap { $0.isEmpty ? nil : $0 }
        return Button {
            guard opens else { return }
            route = .phase(index)
        } label: {
            HStack(spacing: 12) {
                Circle().fill(color)
                    .frame(width: 8, height: 8)
                    .frame(width: markWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(seg.label)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(2)
                        if isCurrent {
                            TintCapsule(text: "Now", color: color)
                        }
                    }
                    Text([seg.shortRange(in: weeks), focus].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityRemoveTraits(opens ? [] : .isButton)
        .accessibilityHint(opens ? "Opens the phase" : "")
    }

    private var compareRow: some View {
        Button { route = .compare } label: {
            HStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(width: markWidth)
                Text("Compare phases").font(.subheadline)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Every session against every phase")
    }

    @ViewBuilder
    private func destination(_ route: OverviewRoute) -> some View {
        let weeks = appState.allWeeks
        let segments = PhaseSegment.segments(of: weeks)
        switch route {
        case .phase(let i):
            if segments.indices.contains(i),
               let summary = PhaseSummary.forSegment(i, of: summaries, segmentCount: segments.count) {
                PhaseDetailView(segment: segments[i], summary: summary,
                                phase: philosophyPhase(for: segments[i], weeks: weeks), weeks: weeks,
                                isCurrent: segments[i].weekIndices.contains(appState.currentWeekIndex ?? -1))
            }
        case .compare:
            PhaseMatrixView(summaries: summaries)
        }
    }

    /// Push the screen a deep link asked for (`program?section=overview&phase=`),
    /// once the program is loaded; one that names no phase is dropped.
    private func applyPendingPhase() {
        guard let raw = router.pendingProgramPhase, !appState.allWeeks.isEmpty else { return }
        let segmentCount = PhaseSegment.segments(of: appState.allWeeks).count
        if raw == "compare", summaries.count > 1 {
            route = .compare
        } else if let i = Int(raw), PhaseSummary.forSegment(i, of: summaries, segmentCount: segmentCount) != nil {
            route = .phase(i)
        }
        router.clearPendingProgramPhase()
    }

    /// The methodology's own phase for a segment — the program's track first,
    /// then any methodology of the blend that declares it; one that has a
    /// focus line wins over one that does not.
    private func philosophyPhase(for seg: PhaseSegment, weeks: [ProgramWeek]) -> PhilosophyPhase? {
        guard let i = seg.weekIndices.first, weeks.indices.contains(i), let phaseId = weeks[i].phaseId else {
            return nil
        }
        let week = weeks[i]
        let matches = appState.programMethodologies().flatMap { card in
            ((card.track(week.trackId)?.phases ?? []) + (card.tracks ?? []).flatMap(\.phases))
                .filter { $0.id == phaseId }
        }
        return matches.first { !($0.focus ?? "").isEmpty } ?? matches.first
    }
}

// MARK: - Priority mix

/// `goal.priorities`, the modality weights the scheduler allocated sessions
/// from — the web's Priority Mix — as shares of their sum.
enum ProgramPriorities {
    struct Share: Identifiable, Equatable {
        let id: String
        let share: Double

        var percent: Int { Int((share * 100).rounded()) }
    }

    /// Heaviest first (ties by id), zero weights left out; empty without a goal.
    static func shares(from extra: [String: JSONValue]?) -> [Share] {
        guard case .object(let goal)? = extra?["goal"],
              case .object(let raw)? = goal["priorities"] else { return [] }
        let weights: [(id: String, weight: Double)] = raw.compactMap { key, value in
            switch value {
            case .double(let d): return (key, d)
            case .int(let i): return (key, Double(i))
            default: return nil
            }
        }.filter { $0.weight > 0 }
        let total = weights.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return weights
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.id < $1.id }
            .map { Share(id: $0.id, share: $0.weight / total) }
    }
}

/// The priority mix as one bar, a segment per modality in its colour (§3.1)
/// as wide as its share, and a legend naming each with its percentage.
/// It was a card of its own, a bar per modality, until 2026-10-17.
struct PriorityMixBar: View {
    let shares: [ProgramPriorities.Share]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gaps = CGFloat(max(shares.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(shares) { share in
                        Rectangle()
                            .fill(ModalityStyle.color(for: share.id))
                            .frame(width: max((geo.size.width - gaps) * share.share, 2))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            LegendFlow(spacing: 14, lineSpacing: 4) { legend }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Priority mix: " + shares.map {
            "\(ModalityStyle.label(for: $0.id)) \($0.percent) percent"
        }.joined(separator: ", "))
    }

    private var legend: some View {
        ForEach(shares) { share in
            HStack(spacing: 5) {
                Circle().fill(ModalityStyle.color(for: share.id)).frame(width: 8, height: 8)
                Text(ModalityStyle.label(for: share.id))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(share.percent)%").monospacedDigit()
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
