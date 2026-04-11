import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sync: SyncManager

    @State private var selectedSession: (session: ProgramSession, key: String)? = nil
    @State private var dayOffset: Int = 0          // 0 = today, ±n = days from today
    @State private var dragOffset: CGFloat = 0
    @State private var lockedAdjacentOffset: Int? = nil  // the peek card's day, locked at drag start
    @ScaledMetric(relativeTo: .body) private var sessionsListHeight: CGFloat = 256

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    private let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
    private let weekdayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]

    private var cardWidth: CGFloat { UIScreen.main.bounds.width - 32 }

    private var peekDayOffset: Int {
        lockedAdjacentOffset ?? dayOffset + (dragOffset <= 0 ? 1 : -1)
    }

    private var showPeek: Bool { dragOffset != 0 }

    private func dateFor(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func sessionsFor(_ offset: Int) -> [(session: ProgramSession, sessionKey: String)] {
        let date = dateFor(offset)
        guard let week = appState.week(for: date) else { return [] }
        let dayName = weekdayNames[Calendar.current.component(.weekday, from: date) - 1]
        return (week.schedule[dayName] ?? []).enumerated().map { (i, s) in
            (session: s, sessionKey: appState.makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoadingProgram && appState.serverProgram == nil {
                    loadingView
                } else if appState.serverProgram?.currentProgram == nil {
                    noProgramView
                } else {
                    dashboardContent
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .appTabStyle()
            .sheet(item: Binding(
                get: { selectedSession.map { SessionSheetItem(session: $0.session, key: $0.key) } },
                set: { if $0 == nil { selectedSession = nil } }
            )) { item in
                SessionDetailView(session: item.session, sessionKey: item.key)
                    .environmentObject(appState)
            }
            .task {
                if appState.serverProgram == nil {
                    await appState.loadAll()
                }
            }
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                programHeader
                todaySection
                readinessSection
                developmentSection
                Spacer(minLength: 40)
            }
            .padding()
        }
        .refreshable {
            AppHaptics.light()
            async let delay: () = Task.sleep(nanoseconds: 600_000_000)
            await sync.syncAll()
            await appState.loadAll()
            _ = try? await delay
            dayOffset = 0
            AppHaptics.success()
        }
    }

    // MARK: - Program Header

    private var programHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayFmt.string(from: Date()))
                    .font(.title2).fontWeight(.semibold)
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
                    .background(Color.orange.gradient)
                    .clipShape(Capsule())
                }
            }
            if let week = appState.currentWeek {
                HStack(spacing: 6) {
                    if let goalName = programGoalName {
                        Text(goalName).foregroundStyle(.primary)
                        Text("·")
                    }
                    Text("Week \(week.weekNumber)")
                    Text("·")
                    Text(week.phase.capitalized)
                    if week.isDeload {
                        Text("· Deload").foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sessions Section

    private var todaySection: some View {
        let gap: CGFloat = 14
        let exitDistance = cardWidth + gap

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Sessions")
            ZStack(alignment: .topLeading) {
                if showPeek {
                    let peekSign: CGFloat = peekDayOffset > dayOffset ? 1 : -1
                    dayCardView(dayOff: peekDayOffset, interactive: false)
                        .offset(x: dragOffset + peekSign * exitDistance)
                        .allowsHitTesting(false)
                }
                dayCardView(dayOff: dayOffset, interactive: true)
                    .offset(x: dragOffset)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let h = value.translation.width
                        guard abs(h) > abs(value.translation.height) else { return }
                        if lockedAdjacentOffset == nil {
                            lockedAdjacentOffset = dayOffset + (h < 0 ? 1 : -1)
                        }
                        dragOffset = h
                    }
                    .onEnded { value in
                        let h = value.translation.width
                        guard abs(h) > abs(value.translation.height),
                              abs(value.predictedEndTranslation.width) > AppMetrics.swipeThreshold
                              || abs(value.velocity.width) > AppMetrics.swipeVelocityThreshold else {
                            lockedAdjacentOffset = nil
                            withAnimation(AppAnimation.springStandard) { dragOffset = 0 }
                            return
                        }
                        let goNext = h < 0
                        AppHaptics.soft()
                        withAnimation(AppAnimation.springSnappy) {
                            dragOffset = goNext ? -exitDistance : exitDistance
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dayOffset += goNext ? 1 : -1
                            dragOffset = 0
                            lockedAdjacentOffset = nil
                        }
                    }
            )
        }
    }

    private func dayCardView(dayOff: Int, interactive: Bool) -> some View {
        let date = dateFor(dayOff)
        let sessions = sessionsFor(dayOff)
        return VStack(alignment: .leading, spacing: 10) {
            // Day label header
            HStack {
                if dayOff == 0 {
                    Label("Today", systemImage: "sun.max.fill")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.orange)
                } else {
                    Text(dayFmt.string(from: date))
                        .font(.subheadline).fontWeight(.semibold)
                }
                Spacer()
                if interactive && dayOff != 0 {
                    Button {
                        dayOffset = 0
                        dragOffset = 0
                        lockedAdjacentOffset = nil
                    } label: {
                        HStack(spacing: 3) {
                            if dayOff < 0 {
                                // Viewing a future day — today is to the left
                                Image(systemName: "chevron.left").font(.caption2)
                            }
                            Text("Today").font(.caption)
                            if dayOff > 0 {
                                // Viewing a past day — today is to the right
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Fixed-height sessions area — scrollable only when >2 sessions
            ScrollView(.vertical, showsIndicators: sessions.count > 2) {
                VStack(spacing: 12) {
                    if sessions.isEmpty {
                        restDayCardView(dayOff: dayOff)
                    } else {
                        ForEach(sessions, id: \.sessionKey) { pair in
                            sessionCard(pair.session, key: pair.sessionKey)
                                .onTapGesture {
                                    guard interactive else { return }
                                    AppHaptics.light()
                                    selectedSession = (session: pair.session, key: pair.sessionKey)
                                }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: sessionsListHeight)
            .scrollDisabled(sessions.count <= 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restDayCardView(dayOff: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "battery.100.bolt")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Rest")
                    .font(.body).fontWeight(.medium)
                if dayOff == 0, let next = nextSessionDay {
                    Text("Next session: \(next)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sessionCard(_ session: ProgramSession, key: String) -> some View {
        let done = appState.isSessionComplete(key)
        let color = ModalityStyle.color(for: session.modality)
        let arch = session.archetype

        return HStack(spacing: 14) {
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
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                    if done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                Text(arch?.name ?? ModalityStyle.label(for: session.modality))
                    .font(.body).fontWeight(.medium)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 12) {
                    if let mins = arch?.durationEstimateMinutes {
                        Label("\(mins) min", systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let count = session.exercises.filter { !$0.injurySkip }.count
                    Label("\(count) exercises", systemImage: "list.bullet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary).font(.caption)
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(done ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Readiness Section

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Readiness")
            readinessCard
        }
    }

    @ViewBuilder
    private var readinessCard: some View {
        if let info = appState.readinessInfo(from: appState.recentBioLogs),
           let latest = appState.recentBioLogs.first {
            let color = info.signalColor
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(info.score * 100))")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                            Text("/ 100")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(readinessLabel(info.signal))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let hrv = latest.hrv {
                            readinessStat(label: "HRV", value: "\(Int(hrv)) ms")
                        }
                        if let hr = latest.restingHR {
                            readinessStat(label: "RHR", value: "\(Int(hr)) bpm")
                        }
                        if let sleep = latest.sleepDurationMin, sleep > 0 {
                            let h = sleep / 60; let m = sleep % 60
                            readinessStat(label: "Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        }
                    }
                }

                // Flags
                let flags = readinessFlags(info, latest: latest)
                if !flags.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(flags, id: \.self) { flag in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(flag)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
        } else {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Text("No bio data · sync from Apple Watch or add a manual entry in Log")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func readinessStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private func readinessLabel(_ signal: String) -> String {
        switch signal {
        case "green":  return "Ready"
        case "yellow": return "Moderate"
        default:       return "Low"
        }
    }

    private func readinessFlags(_ info: ReadinessInfo, latest: DailyBioLog) -> [String] {
        var flags: [String] = []
        let logs = appState.recentBioLogs
        if logs.count >= 3 {
            let recentHR = logs.prefix(3).compactMap { $0.restingHR }
            if let baseline = logs.dropFirst(3).compactMap({ $0.restingHR }).average,
               recentHR.count == 3, (recentHR.average ?? 0) > baseline * 1.05 {
                flags.append("Elevated resting HR (3+ days)")
            }
            let recentHRV = logs.prefix(3).compactMap { $0.hrv }
            if let baseline = logs.dropFirst(3).compactMap({ $0.hrv }).average,
               recentHRV.count == 3, (recentHRV.average ?? 0) < baseline * 0.9 {
                flags.append("Suppressed HRV (3+ days)")
            }
        }
        if let sleep = latest.sleepDurationMin, sleep < 300 {
            flags.append("Less than 5h sleep last night")
        }
        if logs.count < 3 { flags.append("Limited bio data") }
        return flags
    }

    // MARK: - Development Section

    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Development")
            developmentCard
        }
    }

    private var developmentCard: some View {
        let stats = complianceStats
        let color = complianceColor(stats.overall)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(stats.overall)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        Text("% compliance")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(complianceLabel(stats.overall))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    readinessStat(label: "Done", value: "\(stats.completed)")
                    readinessStat(label: "Scheduled", value: "\(stats.scheduled)")
                    if let trend = stats.weekTrend {
                        HStack(spacing: 4) {
                            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                                .foregroundStyle(trend >= 0 ? .green : .orange)
                            Text("vs last week")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !stats.weekRows.isEmpty {
                Divider()
                VStack(spacing: 4) {
                    ForEach(stats.weekRows.suffix(4), id: \.weekNumber) { row in
                        HStack {
                            Text("Wk \(row.weekNumber)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemFill))
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(complianceColor(row.pct))
                                        .frame(width: geo.size.width * CGFloat(row.pct) / 100, height: 6)
                                }
                            }
                            .frame(height: 6)
                            Text("\(row.pct)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.4), lineWidth: 1)
        )
    }

    private struct ComplianceStats {
        let overall: Int
        let completed: Int
        let scheduled: Int
        let weekTrend: Int?
        let weekRows: [WeekRow]
        struct WeekRow { let weekNumber: Int; let pct: Int }
    }

    private var complianceStats: ComplianceStats {
        guard let currentIdx = appState.currentWeekIndex else {
            return ComplianceStats(overall: 0, completed: 0, scheduled: 0, weekTrend: nil, weekRows: [])
        }
        let weeks = appState.allWeeks
        let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
        var totalScheduled = 0
        var totalCompleted = 0
        var weekRows: [ComplianceStats.WeekRow] = []

        for wIdx in 0...currentIdx {
            let week = weeks[wIdx]
            var wScheduled = 0
            var wCompleted = 0
            for day in dayOrder {
                let sessions = week.schedule[day] ?? []
                for (i, _) in sessions.enumerated() {
                    let key = appState.makeSessionKey(weekNumber: week.weekNumber, dayName: day, index: i)
                    wScheduled += 1
                    if appState.isSessionComplete(key) { wCompleted += 1 }
                }
            }
            totalScheduled += wScheduled
            totalCompleted += wCompleted
            let pct = wScheduled > 0 ? Int(Double(wCompleted) / Double(wScheduled) * 100) : 0
            weekRows.append(ComplianceStats.WeekRow(weekNumber: week.weekNumber, pct: pct))
        }

        let overall = totalScheduled > 0 ? Int(Double(totalCompleted) / Double(totalScheduled) * 100) : 0
        var trend: Int? = nil
        if weekRows.count >= 2 {
            trend = weekRows[weekRows.count - 1].pct - weekRows[weekRows.count - 2].pct
        }
        return ComplianceStats(overall: overall, completed: totalCompleted, scheduled: totalScheduled,
                               weekTrend: trend, weekRows: weekRows)
    }

    private func complianceColor(_ pct: Int) -> Color {
        if pct >= 70 { return .green }
        if pct >= 45 { return .yellow }
        return .red
    }

    private func complianceLabel(_ pct: Int) -> String {
        if pct >= 70 { return "On Track" }
        if pct >= 45 { return "Mixed" }
        return "Off Track"
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private var programGoalName: String? {
        guard let ids = appState.serverProgram?.sourceGoalIds, let first = ids.first else { return nil }
        return appState.goals.first(where: { $0.id == first })?.name
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

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading program…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noProgramView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56)).foregroundStyle(.orange.gradient)
            Text("No Program").font(.title2).fontWeight(.medium)
            Text("Generate a program from the Program tab.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

private extension Collection where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private struct SessionSheetItem: Identifiable {
    let id = UUID()
    let session: ProgramSession
    let key: String
}
