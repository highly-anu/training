import SwiftUI

struct ProgramView: View {
    @EnvironmentObject var appState: AppState

    @State private var weekIndex: Int = 0

    // Swipe state
    @State private var dragOffset: CGFloat = 0
    @State private var lockedAdjacentIndex: Int? = nil

    @State private var showBuilder = false
    @State private var showSettings = false
    @State private var selectedDay: DaySelection? = nil

    private let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
    private var cardWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private var peekIndex: Int { lockedAdjacentIndex ?? weekIndex + (dragOffset <= 0 ? 1 : -1) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if appState.allWeeks.isEmpty && !appState.isLoadingProgram {
                    noProgramView
                } else if appState.isLoadingProgram && appState.allWeeks.isEmpty {
                    loadingView
                } else {
                    programContent
                }
            }
            .navigationTitle("Program")
            .appTabStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appState.allWeeks.isEmpty {
                        Button { AppHaptics.light(); showBuilder = true } label: { Image(systemName: "plus") }
                    } else {
                        Button { AppHaptics.light(); showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
            }
            .sheet(isPresented: $showBuilder) {
                ProgramBuilderFlow().environmentObject(appState)
            }
            .sheet(isPresented: $showSettings) {
                ProgramSettingsSheet().environmentObject(appState)
            }
            .sheet(item: $selectedDay) { sel in
                DaySessionsSheet(week: appState.allWeeks[sel.weekIndex], dayName: sel.dayName)
                    .environmentObject(appState)
            }
            .task {
                if appState.allWeeks.isEmpty { await appState.loadProgram() }
                weekIndex = appState.currentWeekIndex ?? 0
            }
        }
    }

    // MARK: - Program Content

    private var programContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                phaseProgressBar
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                Divider().padding(.bottom, 12)

                swipeableSection
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, 4)
        }
        .refreshable {
            AppHaptics.light()
            weekIndex = appState.currentWeekIndex ?? 0
            async let delay: () = Task.sleep(nanoseconds: 600_000_000)
            await appState.loadProgram()
            _ = try? await delay
            AppHaptics.success()
        }
    }

    // MARK: - Phase Progress Bar

    private var phaseProgressBar: some View {
        let weeks = appState.allWeeks
        let total = weeks.count
        let currentIdx = appState.currentWeekIndex ?? -1
        let segments = phaseSegments(from: weeks)

        return VStack(alignment: .leading, spacing: 5) {
            // Coloured bar
            GeometryReader { geo in
                let barWidth = geo.size.width
                HStack(spacing: 0) {
                    ForEach(segments, id: \.phase) { seg in
                        let segFrac = CGFloat(seg.weekIndices.count) / CGFloat(max(total, 1))
                        let segWidth = barWidth * segFrac
                        let isCurrent = seg.weekIndices.contains(currentIdx)
                        let isPast = (seg.weekIndices.last ?? -1) < currentIdx
                        let color = phaseColor(seg.phase)

                        ZStack(alignment: .leading) {
                            if isPast {
                                Rectangle().fill(color.opacity(0.45))
                            } else if isCurrent, let firstIdx = seg.weekIndices.first {
                                let progress = CGFloat(currentIdx - firstIdx + 1)
                                    / CGFloat(seg.weekIndices.count)
                                let doneWidth = segWidth * progress
                                // Dim fill for whole segment
                                Rectangle().fill(color.opacity(0.18))
                                // Bright fill for completed portion
                                Rectangle().fill(color.opacity(0.65))
                                    .frame(width: doneWidth)
                                // Bright vertical marker at current week
                                Rectangle().fill(color)
                                    .frame(width: 3)
                                    .offset(x: max(0, doneWidth - 1.5))
                            } else {
                                Rectangle().fill(color.opacity(0.15))
                            }
                        }
                        .frame(width: segWidth, height: 10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // Subtle track behind
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemFill))
                )
            }
            .frame(height: 10)

            // Phase labels
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(segments, id: \.phase) { seg in
                        let segFrac = CGFloat(seg.weekIndices.count) / CGFloat(max(total, 1))
                        let isCurrent = seg.weekIndices.contains(currentIdx)
                        let color = phaseColor(seg.phase)
                        Text(seg.phase.capitalized)
                            .font(.caption2)
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundStyle(isCurrent ? color : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: geo.size.width * segFrac, alignment: .center)
                    }
                }
            }
            .frame(height: 14)
        }
    }

    // MARK: - Swipeable Section

    private var swipeableSection: some View {
        let gap: CGFloat = 14
        let exitDistance = cardWidth + gap
        let showPeek = dragOffset != 0
        let peekSign: CGFloat = peekIndex > weekIndex ? 1 : -1

        return ZStack(alignment: .topLeading) {
            if showPeek {
                weekCard(weekIdx: peekIndex)
                    .offset(x: dragOffset + peekSign * exitDistance)
                    .allowsHitTesting(false)
            }
            weekCard(weekIdx: weekIndex)
                .offset(x: dragOffset)
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let h = value.translation.width
                    guard abs(h) > abs(value.translation.height) else { return }
                    if lockedAdjacentIndex == nil {
                        lockedAdjacentIndex = weekIndex + (h < 0 ? 1 : -1)
                    }
                    dragOffset = h
                }
                .onEnded { value in
                    let h = value.translation.width
                    guard abs(h) > abs(value.translation.height),
                          abs(value.predictedEndTranslation.width) > AppMetrics.swipeThreshold
                          || abs(value.velocity.width) > AppMetrics.swipeVelocityThreshold else {
                        cancelSwipe(); return
                    }
                    let goNext = h < 0
                    let next = weekIndex + (goNext ? 1 : -1)
                    guard next >= 0 && next < appState.allWeeks.count else {
                        cancelSwipe(); return
                    }
                    commitSwipe(goNext: goNext, exitDistance: exitDistance)
                }
        )
    }

    private func cancelSwipe() {
        lockedAdjacentIndex = nil
        withAnimation(AppAnimation.springStandard) { dragOffset = 0 }
    }

    private func commitSwipe(goNext: Bool, exitDistance: CGFloat) {
        AppHaptics.soft()
        withAnimation(AppAnimation.springSnappy) {
            dragOffset = goNext ? -exitDistance : exitDistance
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            weekIndex += goNext ? 1 : -1
            dragOffset = 0
            lockedAdjacentIndex = nil
        }
    }

    // MARK: - Week Card

    @ViewBuilder
    private func weekCard(weekIdx: Int) -> some View {
        let weeks = appState.allWeeks
        if weekIdx >= 0 && weekIdx < weeks.count {
            let week = weeks[weekIdx]
            let isCurrent = weekIdx == (appState.currentWeekIndex ?? -1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Text("Week \(week.weekNumber)").font(.headline)
                        if isCurrent {
                            Text("Current")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.blue.gradient)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text(week.phase.capitalized)
                        if week.isDeload { Text("· Deload").foregroundStyle(.orange) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(dayOrder.indices, id: \.self) { i in
                        dayRow(day: dayOrder[i], week: week, weekIdx: weekIdx)
                        if i < dayOrder.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else {
            Text(weekIdx < 0 ? "Before program start" : "End of program")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dayRow(day: String, week: ProgramWeek, weekIdx: Int) -> some View {
        let sessions = week.schedule[day] ?? []
        let isToday = day == appState.todayDayName && weekIdx == (appState.currentWeekIndex ?? -1)

        return Button {
            guard !sessions.isEmpty else { return }
            AppHaptics.light()
            selectedDay = DaySelection(weekIndex: weekIdx, dayName: day)
        } label: {
            HStack(spacing: 12) {
                Text(day.prefix(3))
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? .blue : .primary)
                    .frame(width: 36, alignment: .leading)

                if sessions.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.100.bolt").foregroundStyle(.green)
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
                                Image(systemName: done ? "checkmark.circle.fill"
                                                       : ModalityStyle.icon(for: session.modality))
                                    .foregroundStyle(done ? .green
                                                          : ModalityStyle.color(for: session.modality))
                                    .font(.caption)
                                Text(session.archetype?.name
                                     ?? ModalityStyle.label(for: session.modality))
                                    .font(.subheadline)
                                    .foregroundStyle(done ? .secondary : .primary)
                            }
                        }
                    }
                }

                Spacer()
                if !sessions.isEmpty {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isToday ? Color.blue.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading program…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noProgramView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            Text("No Program").font(.title2).fontWeight(.medium)
            Text("Create a training program to get started.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Program") { showBuilder = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "base":   return .blue
        case "build":  return .green
        case "peak":   return .orange
        case "taper":  return .purple
        case "deload": return .gray
        default:       return .secondary
        }
    }

    private struct PhaseSegment { let phase: String; let weekIndices: [Int] }

    private func phaseSegments(from weeks: [ProgramWeek]) -> [PhaseSegment] {
        var segments: [PhaseSegment] = []
        var current: PhaseSegment? = nil
        for (i, week) in weeks.enumerated() {
            let phase = week.phase   // isDeload stays within the parent phase, matching web app
            if phase == current?.phase {
                current = PhaseSegment(phase: phase, weekIndices: (current?.weekIndices ?? []) + [i])
            } else {
                if let c = current { segments.append(c) }
                current = PhaseSegment(phase: phase, weekIndices: [i])
            }
        }
        if let c = current { segments.append(c) }
        return segments
    }
}

// MARK: - Day Sessions Sheet

private struct DaySessionsSheet: View {
    let week: ProgramWeek
    let dayName: String

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: SessionWithKey? = nil

    var body: some View {
        NavigationStack {
            List {
                let sessions = week.schedule[dayName] ?? []
                ForEach(sessions.indices, id: \.self) { i in
                    let session = sessions[i]
                    let key = appState.makeSessionKey(
                        weekNumber: week.weekNumber, dayName: dayName, index: i)
                    Button {
                        selectedSession = SessionWithKey(session: session, key: key)
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
                SessionDetailView(session: item.session, sessionKey: item.key)
                    .environmentObject(appState)
            }
        }
    }

    private func sessionRow(_ session: ProgramSession, key: String) -> some View {
        let done = appState.isSessionComplete(key)
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : ModalityStyle.icon(for: session.modality))
                .foregroundStyle(done ? .green : ModalityStyle.color(for: session.modality))
                .font(.title3)
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
