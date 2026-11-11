import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var router: AppRouter

    /// A session's detail grows out of its card (§6.48).
    @Namespace private var zoom
    @State private var selectedSession: TodaySession? = nil
    /// The session the player runs, started from its card (§6.53).
    @State private var player: PlayerStart? = nil
    /// The day the pager shows: 0 = today, ±n = days from today (§6.49).
    @State private var dayOffset: Int = 0
    @State private var showBuilder = false
    @State private var reviewWorkout: ImportedWorkout? = nil

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    private let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
    private let weekdayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]

    /// The days the pager can show: the program's span around today.
    private var dayPages: ClosedRange<Int> {
        Paging.dayRange(today: Date(), programStart: appState.programStart, weeks: appState.allWeeks.count)
    }

    private func dateFor(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func sessionsFor(_ offset: Int) -> [TodaySession] {
        let date = dateFor(offset)
        guard let wi = appState.weekIndex(for: date) else { return [] }
        let week = appState.allWeeks[wi]
        let dayName = weekdayNames[Calendar.current.component(.weekday, from: date) - 1]
        return (week.schedule[dayName] ?? []).enumerated().map { (i, s) in
            TodaySession(session: s,
                         key: appState.makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i),
                         weekIndex: wi, dayName: dayName, sessionIndex: i)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // A failed load says so (§6.3): until 1.36 it read "No Program".
                switch AppLoadPhase.resolve(hasContent: appState.serverProgram?.currentProgram != nil,
                                            isLoading: appState.isLoadingProgram && appState.serverProgram == nil,
                                            error: appState.serverProgram == nil ? appState.programError : nil) {
                case .content: dashboardContent
                case .loading: AppLoadingState(label: "Loading program")
                case .failed(let message):
                    AppFailedState(title: "Could not load your program", message: message) { await appState.loadAll() }
                case .empty: noProgramView
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .appTabStyle()
            .sheet(isPresented: $showBuilder) {
                ProgramBuilderFlow().environmentObject(appState)
            }
            // A session asked for from outside (a widget, a deep link): both
            // hooks, because the router may set it before this view exists or
            // while it is on screen, and the program may still be loading.
            .onAppear { openPendingSession() }
            #if DEBUG
            .onAppear { if BuilderDebugLaunch.current != nil { showBuilder = true } }
            #endif
            .onChange(of: router.pendingSessionKey) { openPendingSession() }
            // A session just completed turns emerald once Today is in front
            // of the athlete again (§6.56).
            .onChange(of: isCovered) { showCompletion() }
            .onChange(of: appState.justCompleted) { showCompletion() }
            // A regenerate (here or on the web) is a new program: its
            // scorecard, not the last one's, on the Development card.
            .onChange(of: appState.serverProgram?.revision) {
                openPendingSession()
                Task { await appState.loadProgramAnalytics() }
            }
            // A suggestion's "Review" lands on the workout, whose Link to
            // Session flow is the one matching UI the app has.
            .navigationDestination(item: $reviewWorkout) { workout in
                WorkoutDetailView(workout: workout)
                    .environmentObject(appState)
            }
            .sheet(item: $selectedSession) { item in
                SessionDetailView(session: item.session, sessionKey: item.key,
                                  weekIndex: item.weekIndex, dayName: item.dayName,
                                  sessionIndex: item.sessionIndex)
                    .environmentObject(appState)
                    .appZoom(from: item.key, in: zoom)
            }
            // Start workout on today's card: the player, without the detour
            // through the session's sheet.
            .fullScreenCover(item: $player) { start in
                WorkoutPlayerView(player: .resumingIfKept(start.target), fallback: start.session) {
                    player = nil
                }
                .appZoom(from: start.target.sessionKey, in: zoom)
                .environmentObject(appState)
            }
            .task {
                // Guard against duplicate loads: if a load is already in flight
                // (started by ContentView.onAppear), don't pile on a second one.
                // serverProgram == nil && !isLoadingProgram means no load has run yet.
                if appState.serverProgram == nil && !appState.isLoadingProgram {
                    await appState.loadAll()
                }
                // The header names the program's methodology; the catalog is
                // static and small.
                await appState.loadPhilosophiesIfNeeded()
                // Adherence and Progress read the program's analytics document.
                if appState.programAnalytics == nil { await appState.loadProgramAnalytics() }
            }
        }
    }

    // MARK: - Completion

    /// Something is over Today: a session's sheet, the player, another tab.
    private var isCovered: Bool {
        selectedSession != nil || player != nil || router.tab != .dashboard
    }

    /// The completion moment: the card's stripe and border turn emerald, its
    /// mark arrives and the week strip's dot fills — after the sheet that
    /// completed it has gone, which is where the success haptic was given.
    private func showCompletion() {
        guard !isCovered, appState.justCompleted != nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !isCovered else { return }
            withAnimation(AppAnimation.springStandard) { appState.justCompleted = nil }
        }
    }

    // MARK: - Dashboard Content

    /// §6.53: where the athlete is, the day and its session, what waits for an
    /// answer, then the three numbers.
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppMetrics.gapSection) {
                AppScrollFade {
                    programHeader
                    todaySection
                    TodayInbox { reviewWorkout = $0 }
                    TodaySummary()
                    Spacer(minLength: 40)
                }
            }
            .padding()
        }
        .refreshable {
            await AppRefresh.perform {
                await sync.syncAll()
                await appState.loadAll()
            }
            dayOffset = 0
        }
    }

    // MARK: - Program Header

    /// The program and where the athlete is in it. The date is the pager's
    /// title: until 1.39 it was a heading here too, over a pager titled "Today"
    /// under a navigation title "Today".
    @ViewBuilder
    private var programHeader: some View {
        if let week = appState.currentWeek {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let goalName = programGoalName {
                        Text(goalName).font(.headline)
                    }
                    HStack(spacing: 6) {
                        // Position in the program (see ProgramView) — weekNumber is
                        // the stored absolute number and can disagree with the start date.
                        Text("Week \((appState.currentWeekIndex ?? 0) + 1)")
                        Text("·")
                        Text(week.phaseLabel)
                        if week.isDeload {
                            Text("· Deload").foregroundStyle(AppColor.warning)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let countdown = eventCountdown {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.checkered")
                        Text(countdown)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.warning.gradient)
                    .clipShape(Capsule())
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Sessions Section

    /// The day's sessions, one day a page: the header's chevrons and the week
    /// strip are the controls, a swipe the shortcut (§6.49, §6.50).
    private var todaySection: some View {
        let pages = dayPages
        return VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            AppPagerHeader(pages: pages, selection: $dayOffset, unit: "day",
                           onTitle: dayOffset == 0 ? nil : { dayOffset = 0 }) {
                HStack(spacing: AppMetrics.gapSmall) {
                    Text(dayFmt.string(from: dateFor(dayOffset)))
                        .font(.headline)
                    if dayOffset != 0 {
                        Label("Today", systemImage: dayOffset > 0 ? "arrow.uturn.backward" : "arrow.uturn.forward")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.accent)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dayOffset == 0 ? "Today, \(dayFmt.string(from: dateFor(dayOffset)))"
                                    : "\(dayFmt.string(from: dateFor(dayOffset))). Back to today")
            }
            WeekStrip(days: Paging.week(around: dayOffset, today: Date()).map(stripDay), selection: $dayOffset)
            // As tall as the day on show: a rest day no longer leaves three
            // sessions' worth of space above what follows.
            AppPager(pages: pages, selection: $dayOffset, fitsPage: true) { offset in
                dayCardView(dayOff: offset)
            }
            // Pages slide edge to edge; each keeps the screen's margin.
            .padding(.horizontal, -AppMetrics.gapLarge)
        }
    }

    /// One day of the week strip: what is planned and whether it is done.
    private func stripDay(_ offset: Int) -> WeekStrip.Day {
        let date = dateFor(offset)
        let sessions = sessionsFor(offset)
        let done = sessions.filter { appState.isShownComplete($0.key) }.count
        let status: WeekStrip.Status = sessions.isEmpty ? .rest
            : (done == sessions.count ? .done : .planned)
        return WeekStrip.Day(offset: offset, date: date, status: status,
                             color: sessions.first.map { ModalityStyle.color(for: $0.session.modality) },
                             isToday: offset == 0, isEnabled: dayPages.contains(offset))
    }

    private func dayCardView(dayOff: Int) -> some View {
        let sessions = sessionsFor(dayOff)
        // Today's first session still to do leads the page and starts from it.
        let next = dayOff == 0 ? sessions.first { !appState.isShownComplete($0.key) }?.key : nil
        return VStack(spacing: AppMetrics.gapMedium) {
            if sessions.isEmpty {
                // A rest day can still take one: its Add session row, or a long press.
                if let day = dayTarget(for: dayOff) {
                    TodayRestCard(next: dayOff == 0 ? nextSessionDay : nil, day: day)
                        .sessionActions(weekIndex: day.weekIndex, dayName: day.dayName)
                } else {
                    TodayRestCard(next: dayOff == 0 ? nextSessionDay : nil)
                }
            } else {
                ForEach(sessions) { item in
                    TodaySessionCard(item: item, showsTip: dayOff == 0 && item.sessionIndex == 0,
                                     onStart: item.key == next ? start(item) : nil)
                        .matchedTransitionSource(id: item.key, in: zoom)
                        .onTapGesture {
                            AppHaptics.light()
                            selectedSession = item
                        }
                        .accessibilityAddTraits(.isButton)
                        // The card's "…" as a long press: Move, Replace, Remove (an added one), Add Session.
                        .sessionActions(weekIndex: item.weekIndex, dayName: item.dayName,
                                        sessionIndex: item.sessionIndex)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opens the player on a session, when the program can date it.
    private func start(_ item: TodaySession) -> (() -> Void)? {
        guard let date = appState.sessionDate(weekIndex: item.weekIndex, dayName: item.dayName) else { return nil }
        let title = item.session.archetype?.name ?? ModalityStyle.label(for: item.session.modality)
        return { player = PlayerStart(target: .init(sessionKey: item.key, date: date, title: title),
                                      session: item.session) }
    }

    /// The program day `dayOff` days from today, if the program covers it.
    private func dayTarget(for dayOff: Int) -> (weekIndex: Int, dayName: String)? {
        let date = dateFor(dayOff)
        guard let wi = appState.weekIndex(for: date) else { return nil }
        return (wi, weekdayNames[Calendar.current.component(.weekday, from: date) - 1])
    }

    // MARK: - Shared Helpers

    private var programGoalName: String? {
        guard let ids = appState.serverProgram?.sourceGoalIds, let first = ids.first else { return nil }
        return appState.philosophies.first(where: { $0.id == first })?.name
    }

    private var eventCountdown: String? {
        guard let eventStr = appState.serverProgram?.eventDate else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let eventDate = df.date(from: eventStr) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: eventDate)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
        if days < 0 { return nil }
        if days == 0 { return "Event day!" }
        let weeks = days / 7
        let remainingDays = days % 7
        if weeks > 0 && remainingDays > 0 {
            return "\(weeks)w \(remainingDays)d to event"
        } else if weeks > 0 {
            return weeks == 1 ? "1 week to event" : "\(weeks) weeks to event"
        }
        return days == 1 ? "1 day to event" : "\(days) days to event"
    }

    private var nextSessionDay: String? {
        guard let week = appState.currentWeek else { return nil }
        let today = appState.todayDayName
        guard let todayIdx = dayOrder.firstIndex(of: today) else { return nil }
        for i in 1...6 {
            let next = dayOrder[(todayIdx + i) % 7]
            if let sessions = week.schedule[next], !sessions.isEmpty { return next }
        }
        return nil
    }

    // MARK: - Loading / No Program

    /// §6.3: an empty state offers the way forward, so the builder opens from
    /// here as well as from the Program tab.
    private var noProgramView: some View {
        AppEmptyState(icon: "calendar.badge.plus", title: "No program",
                      message: "Pick a methodology and generate your first program.",
                      actionLabel: "Generate a program", prominent: true) { showBuilder = true }
    }
}

extension TodayView {
    /// Present the session the router holds, once the program can locate it.
    fileprivate func openPendingSession() {
        guard let key = router.pendingSessionKey,
              let found = appState.locateSession(key: key) else { return }
        selectedSession = TodaySession(session: found.session, key: found.key, weekIndex: found.weekIndex,
                                       dayName: found.dayName, sessionIndex: found.sessionIndex)
        router.clearPendingSession()
    }
}

/// A session and where the player finds it.
private struct PlayerStart: Identifiable {
    let target: WorkoutPlayerModel.Target
    let session: ProgramSession
    var id: String { target.sessionKey }
}
