import SwiftUI

struct ProgramView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedWeekIndex: Int = 0
    @State private var showBuilder = false
    @State private var showInjurySheet = false
    @State private var selectedDay: DaySelection? = nil

    private let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showInjurySheet = true
                    } label: {
                        Label("Injuries", systemImage: "cross.case")
                    }
                    .disabled(appState.allWeeks.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBuilder = true
                    } label: {
                        Label("New Program", systemImage: appState.allWeeks.isEmpty ? "plus.circle.fill" : "plus")
                    }
                }
            }
            .sheet(isPresented: $showBuilder) {
                ProgramBuilderFlow()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showInjurySheet) {
                InjuryManagementSheet()
                    .environmentObject(appState)
            }
            .sheet(item: $selectedDay) { sel in
                DaySessionsSheet(week: appState.allWeeks[sel.weekIndex], dayName: sel.dayName)
                    .environmentObject(appState)
            }
            .task {
                if appState.allWeeks.isEmpty { await appState.loadProgram() }
                selectedWeekIndex = appState.currentWeekIndex ?? 0
            }
        }
    }

    // MARK: - Program Content

    private var programContent: some View {
        VStack(spacing: 0) {
            // Phase bar
            if !appState.allWeeks.isEmpty {
                phaseBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            // Week navigation header
            weekNavigationHeader
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider()

            // Day rows
            if selectedWeekIndex < appState.allWeeks.count {
                weekDayList(week: appState.allWeeks[selectedWeekIndex], weekIndex: selectedWeekIndex)
            }
        }
    }

    // MARK: - Phase Bar

    private var phaseBar: some View {
        let phases = phaseSegments(from: appState.allWeeks)
        let currentIdx = appState.currentWeekIndex ?? -1
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, segment in
                    let isCurrent = segment.weekIndices.contains(currentIdx)
                    let color = phaseColor(segment.phase)
                    let first = segment.weekIndices.first.map { $0 + 1 } ?? 1
                    let last  = segment.weekIndices.last.map  { $0 + 1 } ?? first
                    let weekLabel = first == last ? "Wk \(first)" : "Wk \(first)–\(last)"

                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(segment.phase.capitalized)
                                .font(.caption)
                                .fontWeight(isCurrent ? .semibold : .regular)
                            Text(weekLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if isCurrent {
                            Capsule()
                                .fill(color)
                                .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isCurrent ? color.opacity(0.12) : Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isCurrent ? color.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Week Navigation Header

    private var weekNavigationHeader: some View {
        let weeks = appState.allWeeks
        let week = weeks.isEmpty ? nil : weeks[min(selectedWeekIndex, weeks.count - 1)]

        return HStack {
            Button {
                if selectedWeekIndex > 0 { selectedWeekIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .disabled(selectedWeekIndex == 0)

            Spacer()

            VStack(spacing: 2) {
                if let week {
                    Text("Week \(week.weekNumber)")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(week.phase.capitalized)
                        if week.isDeload { Text("· Deload").foregroundStyle(.orange) }
                        if selectedWeekIndex == (appState.currentWeekIndex ?? -1) {
                            Text("· Current").foregroundStyle(.blue)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if selectedWeekIndex < appState.allWeeks.count - 1 { selectedWeekIndex += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .disabled(selectedWeekIndex >= appState.allWeeks.count - 1)
        }
    }

    // MARK: - Day List

    private func weekDayList(week: ProgramWeek, weekIndex: Int) -> some View {
        List {
            ForEach(dayOrder, id: \.self) { day in
                let sessions = week.schedule[day] ?? []
                dayRow(day: day, sessions: sessions, week: week, weekIndex: weekIndex)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func dayRow(day: String, sessions: [ProgramSession], week: ProgramWeek, weekIndex: Int) -> some View {
        let isToday = day == appState.todayDayName && weekIndex == (appState.currentWeekIndex ?? -1)

        return Button {
            if !sessions.isEmpty {
                selectedDay = DaySelection(weekIndex: weekIndex, dayName: day)
            }
        } label: {
            HStack(spacing: 12) {
                // Day name
                Text(day.prefix(3))
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? .blue : .primary)
                    .frame(width: 36, alignment: .leading)

                if sessions.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.100.bolt")
                            .foregroundStyle(.green)
                        Text("Rest")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                } else {
                    // Modality chips
                    HStack(spacing: 6) {
                        ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                            let key = appState.makeSessionKey(
                                weekNumber: week.weekNumber, dayName: day, index: 0
                            )
                            let done = appState.isSessionComplete(key)
                            HStack(spacing: 4) {
                                if done {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Image(systemName: ModalityStyle.icon(for: session.modality))
                                        .foregroundStyle(ModalityStyle.color(for: session.modality))
                                }
                                Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                                    .foregroundStyle(done ? .secondary : .primary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Spacer()

                if !sessions.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isToday ? Color.blue.opacity(0.06) : Color.clear)
    }

    // MARK: - Empty States

    private var loadingView: some View {
        VStack(spacing: 16) { ProgressView(); Text("Loading program…").foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noProgramView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            Text("No Program")
                .font(.title2).fontWeight(.medium)
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
            let phase = week.isDeload ? "deload" : week.phase
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
                ForEach(Array(sessions.enumerated()), id: \.offset) { i, session in
                    let key = appState.makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let mins = session.archetype?.durationEstimateMinutes {
                        Text("· \(mins) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Injury Management Sheet

private struct InjuryManagementSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddCustom = false
    @State private var newCustom = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Active Injuries") {
                    ForEach(appState.injuryFlagDefs) { flag in
                        Toggle(isOn: Binding(
                            get: { appState.profile.injuryFlags.contains(flag.id) },
                            set: { on in
                                if on { appState.profile.injuryFlags.append(flag.id) }
                                else { appState.profile.injuryFlags.removeAll { $0 == flag.id } }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(flag.name)
                                if let desc = flag.description {
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    ForEach(appState.profile.customInjuryFlags) { custom in
                        HStack {
                            Text(custom.description)
                            Spacer()
                            Image(systemName: "checkmark").foregroundStyle(.orange)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                appState.profile.customInjuryFlags.removeAll { $0.id == custom.id }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    Button { showAddCustom = true } label: {
                        Label("Add Custom Injury", systemImage: "plus")
                    }
                }

                Section {
                    Button("Save & Close") {
                        Task {
                            await appState.saveProfile()
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.blue)
                }
            }
            .navigationTitle("Manage Injuries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
            .alert("Add Injury", isPresented: $showAddCustom) {
                TextField("Describe the injury", text: $newCustom)
                Button("Add") {
                    let flag = CustomInjuryFlag(id: UUID().uuidString, description: newCustom)
                    appState.profile.customInjuryFlags.append(flag)
                    newCustom = ""
                }
                Button("Cancel", role: .cancel) { newCustom = "" }
            }
        }
    }
}

// MARK: - Supporting Types

private struct DaySelection: Identifiable {
    let id = UUID()
    let weekIndex: Int
    let dayName: String
}
