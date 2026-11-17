import SwiftUI

/// Internal so `AppRouter` and deep links can name a section.
/// The web Program's tabs, in its order (information-architecture.md §2):
/// what the plan is, the weeks you are on, and the plans you have been on.
/// One word each (§6.8). Calendar was "Current" until 2026-10-13; Overview
/// leads since 2026-10-17.
enum ProgramTab: Int, AppSubTab {
    case overview, calendar, history

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .calendar: return "Calendar"
        case .history: return "History"
        }
    }
}

struct ProgramView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    /// The week Calendar's pager shows (§6.49).
    @State private var weekIndex: Int = 0

    @State private var showBuilder = false
    @State private var showSettings = false
    /// Debug builds: a draft opened by `TC_PREVIEW` (ProgramPreviewDebugLaunch).
    @State private var debugPreview: PreviewDraft? = nil
    @State private var selectedDay: DaySelection? = nil

    @State private var section: ProgramTab = .overview

    @ViewBuilder
    private var currentProgramSection: some View {
        switch programPhase {
        case .content: programContent
        case .loading: AppLoadingState(label: "Loading program")
        case .failed(let message):
            AppFailedState(title: "Could not load your program", message: message) { await appState.loadProgram() }
        case .empty: noProgramView
        }
    }

    private let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            // §6.8: screen-level sub-navigation goes through AppSubTabs, so
            // this screen does not invent a third selector.
            AppSubTabScreen(selection: $section) { tab in
                switch tab {
                case .overview: ProgramOverviewTab()
                case .calendar: currentProgramSection
                case .history: ProgramHistoryView()
                }
            }
            .navigationTitle("Program")
            .appTabStyle()
            .task { applyRequestedSection() }
            .onChange(of: router.programSection) { applyRequestedSection() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // History is a record, not something to build or configure.
                    if section != .history {
                        if appState.allWeeks.isEmpty {
                            Button { AppHaptics.light(); showBuilder = true } label: { Image(systemName: "plus") }
                                .accessibilityLabel("New program")
                        } else {
                            Button { AppHaptics.light(); showSettings = true } label: { Image(systemName: "gearshape") }
                                .accessibilityLabel("Program settings")
                        }
                    }
                }
            }
            .sheet(isPresented: $showBuilder) {
                ProgramBuilderFlow().environmentObject(appState)
            }
            .sheet(isPresented: $showSettings) {
                if let program = appState.serverProgram {
                    ProgramSettingsSheet(program: program, weeks: appState.allWeeks, profile: appState.profile)
                        .environmentObject(appState)
                }
            }
            .sheet(item: $selectedDay) { sel in
                DaySessionsSheet(weekIndex: sel.weekIndex, dayName: sel.dayName)
                    .environmentObject(appState)
                    .appSheet(.flexible)
            }
            .task {
                if appState.allWeeks.isEmpty { await appState.loadProgram() }
                weekIndex = appState.currentWeekIndex ?? 0
                #if DEBUG
                debugPreview = await ProgramPreviewDebugLaunch.draft(appState: appState)
                #endif
            }
            .sheet(item: $debugPreview) { p in
                NavigationStack {
                    ProgramPreviewView(mode: .new, request: p.request, draft: p.draft) { _ in debugPreview = nil }
                }
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Program Content

    private var programContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let conflict = appState.programSaveConflict {
                    conflictBanner(conflict)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }

                PhaseProgressBar(weeks: appState.allWeeks, currentIndex: appState.currentWeekIndex)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                Divider().padding(.bottom, 12)

                weekPager

                Spacer(minLength: 40)
            }
            .padding(.top, 4)
        }
        .refreshable {
            weekIndex = appState.currentWeekIndex ?? 0
            await AppRefresh.perform { await appState.loadProgram() }
        }
    }

    /// A save that lost to a newer copy on the server (409). The reload has
    /// already happened; this tells the user their last move or replace is
    /// not in it, where before the edit vanished without a word.
    private func conflictBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.warning)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                AppHaptics.light()
                appState.programSaveConflict = nil
            } label: {
                Image(systemName: "xmark").font(.caption).appTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.warning.opacity(AppColor.Opacity.fill))
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: AppMetrics.radiusControl).stroke(AppColor.warning.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Week Pager

    /// One week a page: the header's chevrons are the control, a swipe the
    /// shortcut; the title goes back to the current week.
    private var weekPager: some View {
        let weeks = appState.allWeeks
        let pages = 0...max(weeks.count - 1, 0)
        let current = appState.currentWeekIndex
        return VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            AppPagerHeader(pages: pages, selection: $weekIndex, unit: "week",
                           onTitle: current == nil || current == weekIndex ? nil : { weekIndex = current ?? 0 }) {
                weekTitle(weekIndex, current: current)
            }
            .padding(.horizontal)
            AppPager(pages: pages, selection: $weekIndex) { index in
                weekCard(weekIdx: index)
            }
        }
    }

    private func weekTitle(_ index: Int, current: Int?) -> some View {
        let weeks = appState.allWeeks
        return VStack(alignment: .leading, spacing: 2) {
            AppAdaptiveStack(spacing: AppMetrics.gapSmall) {
                // Position in the program, not week.weekNumber.
                // A program whose weeks are numbered 16...31 (the tail of
                // an earlier plan) but whose programStartDate is this week
                // showed "Week 16" on day one. programStartDate anchors
                // weeks[0] as week 1, so position is the truth.
                Text("Week \(index + 1) of \(weeks.count)").font(.headline)
                if index == current {
                    Text("Current")
                        .font(.caption2).fontWeight(.semibold)
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(AppColor.accent.gradient)
                        .clipShape(Capsule())
                } else if current != nil {
                    Label("Current", systemImage: index > (current ?? 0) ? "arrow.uturn.backward" : "arrow.uturn.forward")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.accent)
                }
            }
            if let week = weeks[safe: index] {
                HStack(spacing: 6) {
                    Text(week.phaseLabel)
                    if week.isDeload { Text("· Deload").foregroundStyle(AppColor.warning) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Week Card

    @ViewBuilder
    private func weekCard(weekIdx: Int) -> some View {
        let weeks = appState.allWeeks
        if weekIdx >= 0 && weekIdx < weeks.count {
            let week = weeks[weekIdx]

            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(dayOrder.indices, id: \.self) { i in
                        dayRow(day: dayOrder[i], week: week, weekIdx: weekIdx)
                        if i < dayOrder.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusCard, style: .continuous))
            }
        } else {
            Text(weekIdx < 0 ? "Before program start" : "End of program")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusCard, style: .continuous))
        }
    }

    private func dayRow(day: String, week: ProgramWeek, weekIdx: Int) -> some View {
        let sessions = week.schedule[day] ?? []
        let isToday = day == appState.todayDayName && weekIdx == (appState.currentWeekIndex ?? -1)

        // The row opens the day; its trailing control is the day's actions,
        // visible (§6.43): "…" beside sessions, Add on a rest day ahead.
        return HStack(spacing: 0) {
          Button {
            guard !sessions.isEmpty else { return }
            AppHaptics.light()
            selectedDay = DaySelection(weekIndex: weekIdx, dayName: day)
          } label: {
            // The day beside its sessions; above them at the accessibility
            // sizes, where a name would break word by word (§6.57).
            AppAdaptiveStack(spacing: 12) {
                Text(day.prefix(3))
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? AppColor.accent : .primary)
                    .frame(minWidth: 36, alignment: .leading)

                if sessions.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.100.bolt").foregroundStyle(AppColor.complete)
                        Text("Rest").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sessions.indices, id: \.self) { i in
                            let session = sessions[i]
                            let key = appState.makeSessionKey(
                                weekNumber: week.weekNumber, dayName: day, index: i)
                            let done = appState.isSessionComplete(key)
                            HStack(spacing: 6) {
                                Image(symbol: done ? "checkmark.circle.fill"
                                                   : SessionIcon.symbol(icon: session.icon, modality: session.modality))
                                    .foregroundStyle(done ? AppColor.complete
                                                          : ModalityStyle.color(for: session.modality))
                                    .font(.caption)
                                Text(session.archetype?.name
                                     ?? ModalityStyle.label(for: session.modality))
                                    .font(.subheadline)
                                    .foregroundStyle(done ? .secondary : .primary)
                                if session.testInfo != nil { TestBadge() }
                                if session.isAdded {
                                    Text("Added").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(dayLabel(day: day, week: week, isToday: isToday))
          if sessions.isEmpty {
              SessionAddButton(weekIndex: weekIdx, dayName: day, title: "Add")
                  .padding(.trailing, 14)
          } else {
              SessionActionsMenu(weekIndex: weekIdx, dayName: day)
                  .padding(.trailing, 6)
          }
        }
        .background(isToday ? AppColor.accent.opacity(0.06) : Color.clear)
        // The same as a long press: each session's Move, Replace, Remove (an
        // added one); Add Session on today or a later day.
        .sessionActions(weekIndex: weekIdx, dayName: day)
    }

    /// A day's row for VoiceOver: the day, then each session with what the
    /// icons and badges say ("Wednesday, today: Swing Day, done").
    private func dayLabel(day: String, week: ProgramWeek, isToday: Bool) -> String {
        let sessions = week.schedule[day] ?? []
        let head = day + (isToday ? ", today" : "")
        guard !sessions.isEmpty else { return head + ": rest" }
        let parts = sessions.indices.map { i -> String in
            let session = sessions[i]
            let key = appState.makeSessionKey(weekNumber: week.weekNumber, dayName: day, index: i)
            var text = session.archetype?.name ?? ModalityStyle.label(for: session.modality)
            if session.testInfo != nil { text += ", test" }
            if session.isAdded { text += ", added" }
            if appState.isSessionComplete(key) { text += ", done" }
            return text
        }
        return head + ": " + parts.joined(separator: "; ")
    }

    // MARK: - Empty States

    private var noProgramView: some View {
        AppEmptyState(icon: "calendar.badge.plus", title: "No program",
                      message: "Create a training program to get started.",
                      actionLabel: "Create program", prominent: true) { showBuilder = true }
    }

    /// One reading of the program's load for Calendar and Overview.
    private var programPhase: AppLoadPhase {
        AppLoadPhase.resolve(hasContent: !appState.allWeeks.isEmpty,
                             isLoading: appState.isLoadingProgram,
                             error: appState.serverProgram == nil ? appState.programError : nil)
    }
}

// MARK: - Day Sessions Sheet

private struct DaySessionsSheet: View {
    let weekIndex: Int
    let dayName: String

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: SessionWithKey? = nil

    private var liveWeek: ProgramWeek? { appState.allWeeks[safe: weekIndex] }

    var body: some View {
        NavigationStack {
            List {
                let sessions = liveWeek?.schedule[dayName] ?? []
                let weekNumber = liveWeek?.weekNumber ?? 0
                ForEach(sessions.indices, id: \.self) { i in
                    let session = sessions[i]
                    let key = appState.makeSessionKey(weekNumber: weekNumber, dayName: dayName, index: i)
                    Button {
                        selectedSession = SessionWithKey(session: session, key: key, sessionIndex: i)
                    } label: {
                        sessionRow(session, key: key)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(dayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selectedSession) { item in
                SessionDetailView(session: item.session, sessionKey: item.key,
                                  weekIndex: weekIndex, dayName: dayName,
                                  sessionIndex: item.sessionIndex)
                    .environmentObject(appState)
            }
        }
    }

    private func sessionRow(_ session: ProgramSession, key: String) -> some View {
        let done = appState.isSessionComplete(key)
        return HStack(spacing: 12) {
            Image(symbol: done ? "checkmark.circle.fill" : SessionIcon.symbol(icon: session.icon, modality: session.modality))
                .foregroundStyle(done ? AppColor.complete : ModalityStyle.color(for: session.modality))
                .font(.title3)
                .accessibilityLabel("Done")
                .accessibilityHidden(!done)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                    .fontWeight(.medium)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(ModalityStyle.label(for: session.modality))
                        .font(.caption).foregroundStyle(.secondary)
                    if let mins = session.archetype?.durationEstimateMinutes {
                        Text("· \(mins) min").font(.caption).foregroundStyle(.secondary)
                    }
                    if session.testInfo != nil { TestBadge() }
                    TrackBadge(session: session)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Types

private struct DaySelection: Identifiable {
    let id = UUID()
    let weekIndex: Int
    let dayName: String
}

extension ProgramView {
    /// Move to the section the router asked for (a deep link), then clear it
    /// so a later visit keeps the user's own last choice.
    fileprivate func applyRequestedSection() {
        guard let requested = router.programSection else { return }
        if section != requested {
            withAnimation(AppAnimation.springStandard) { section = requested }
        }
        router.clearProgramSection()
    }
}

/// A run of consecutive weeks in one phase. Grouped by the methodology's own
/// phase id, so two phases of one kind stay two segments; weeks generated
/// before phases had ids group by kind. A deload week stays inside its phase,
/// as on the web (`hooks/usePhaseCalendar.ts`).
struct PhaseSegment: Identifiable, Equatable {
    /// Phase id, else the kind.
    let key: String
    let kind: String
    let label: String
    let weekIndices: [Int]
    /// Unique even when a phase recurs: the segment's first week.
    var id: Int { weekIndices.first ?? 0 }

    static func segments(of weeks: [ProgramWeek]) -> [PhaseSegment] {
        var out: [PhaseSegment] = []
        for (i, week) in weeks.enumerated() {
            let key = week.phaseId ?? week.phase
            if let last = out.last, last.key == key {
                out[out.count - 1] = PhaseSegment(key: key, kind: last.kind, label: last.label,
                                                  weekIndices: last.weekIndices + [i])
            } else {
                out.append(PhaseSegment(key: key, kind: week.phase, label: week.phaseLabel, weekIndices: [i]))
            }
        }
        return out
    }
}
