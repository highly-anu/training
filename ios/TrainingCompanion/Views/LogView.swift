import SwiftUI
import HealthKit

struct LogView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedSegment = 0
    @State private var selectedSession: SessionWithKey? = nil
    @State private var showBioEntry = false
    @State private var showImportPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Sessions").tag(0)
                    Text("Bio").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: selectedSegment) { _ in AppHaptics.selection() }

                Divider()

                if selectedSegment == 0 {
                    sessionsTab
                } else {
                    bioTab
                }
            }
            .navigationTitle("Log")
            .appTabStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == 0 {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    } else {
                        Button {
                            showBioEntry = true
                        } label: {
                            Label("Add Entry", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(item: $selectedSession) { item in
                SessionLogDetailView(sessionWithKey: item)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showBioEntry) {
                BioCheckInView()
                    .environmentObject(appState)
            }
            .refreshable {
                AppHaptics.light()
                async let delay: () = Task.sleep(nanoseconds: 600_000_000)
                await appState.loadRecentSessionLogs()
                await appState.loadRecentBioLogs()
                _ = try? await delay
                AppHaptics.success()
            }
        }
    }

    // MARK: - Sessions Tab

    private var sessionsTab: some View {
        let pairs = recentSessionPairs
        return Group {
            if pairs.isEmpty && !appState.isLoadingProgram {
                emptyState(
                    icon: "checkmark.circle",
                    title: "No Recent Sessions",
                    subtitle: "Sessions you complete will appear here."
                )
            } else {
                List {
                    ForEach(pairs, id: \.key) { pair in
                        sessionRow(pair)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSession = SessionWithKey(
                                    session: pair.session,
                                    key: pair.key,
                                    dateLabel: sessionDayLabel(pair.key)
                                )
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ pair: SessionPair) -> some View {
        let done = appState.isSessionComplete(pair.key)
        let log = appState.sessionLogs[pair.key]

        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : ModalityStyle.icon(for: pair.session.modality))
                .foregroundStyle(done ? .green : ModalityStyle.color(for: pair.session.modality))
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(pair.session.archetype?.name ?? ModalityStyle.label(for: pair.session.modality))
                    .font(.body)
                    .foregroundStyle(done ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(sessionDayLabel(pair.key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let hr = log?.avgHR {
                        Label("\(hr) bpm", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if let fatigue = log?.fatigueRating {
                Text("\(fatigue)/10")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(fatigueColor(fatigue).opacity(0.15))
                    .foregroundStyle(fatigueColor(fatigue))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bio Tab

    private var bioTab: some View {
        Group {
            if appState.recentBioLogs.isEmpty {
                emptyState(
                    icon: "waveform.path.ecg",
                    title: "No Bio Data",
                    subtitle: "Sync from your Apple Watch or add a manual entry."
                )
            } else {
                List {
                    Section {
                        readinessSummaryRow
                    }
                    Section("Last 14 Days") {
                        ForEach(appState.recentBioLogs.prefix(14)) { log in
                            bioRow(log)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var readinessSummaryRow: some View {
        HStack(spacing: 16) {
            if let info = appState.readinessInfo(from: appState.recentBioLogs) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(info.signalColor.gradient)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: info.signalIcon)
                                .foregroundStyle(.white)
                                .font(.headline)
                        )
                    Text("Readiness")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let latest = appState.recentBioLogs.first {
                VStack(alignment: .leading, spacing: 4) {
                    if let hrv = latest.hrv {
                        bioMetric(label: "HRV", value: "\(Int(hrv)) ms")
                    }
                    if let hr = latest.restingHR {
                        bioMetric(label: "Resting HR", value: "\(Int(hr)) bpm")
                    }
                    if let sleep = latest.sleepDurationMin, sleep > 0 {
                        let h = sleep / 60; let m = sleep % 60
                        bioMetric(label: "Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func bioMetric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private func bioRow(_ log: DailyBioLog) -> some View {
        HStack {
            Text(log.date)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            Spacer()
            if let hrv = log.hrv {
                bioChip(value: "\(Int(hrv))", unit: "ms", color: .cyan)
            }
            if let hr = log.restingHR {
                bioChip(value: "\(Int(hr))", unit: "bpm", color: .red)
            }
            if let sleep = log.sleepDurationMin, sleep > 0 {
                let h = sleep / 60
                bioChip(value: "\(h)h", unit: "", color: .indigo)
            }
        }
    }

    private func bioChip(value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(value).font(.caption).fontWeight(.medium).foregroundStyle(color)
            if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(width: 52, alignment: .trailing)
    }

    // MARK: - Helpers

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func fatigueColor(_ rating: Int) -> Color {
        switch rating {
        case 1...3: return .green
        case 4...6: return .yellow
        default:    return .red
        }
    }

    private func sessionDayLabel(_ key: String) -> String {
        // Key format: "weekNumber-DayName-index" e.g. "5-Monday-0"
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let weekNumber = Int(parts[0]) else { return key }
        let dayName = String(parts[1])

        let dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        if let startStr = appState.serverProgram?.programStartDate {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            if let startDate = df.date(from: startStr),
               let targetIdx = dayNames.firstIndex(of: dayName) {
                let cal = Calendar.current
                let weekStart = cal.date(byAdding: .day, value: (weekNumber - 1) * 7,
                                         to: cal.startOfDay(for: startDate))!
                let weekStartWeekday = cal.component(.weekday, from: weekStart)
                var offset = (targetIdx + 1) - weekStartWeekday
                if offset < 0 { offset += 7 }
                if let sessionDate = cal.date(byAdding: .day, value: offset, to: weekStart) {
                    let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
                    return out.string(from: sessionDate)
                }
            }
        }
        return dayName
    }

    // Build session pairs from the full program history, sorted most recent → oldest
    private var recentSessionPairs: [SessionPair] {
        guard let weeks = appState.serverProgram?.currentProgram?.weeks,
              let currentIdx = appState.currentWeekIndex else { return [] }
        var pairs: [SessionPair] = []
        let dayOrder = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
        for wIdx in 0...currentIdx {
            let week = weeks[wIdx]
            for day in dayOrder {
                guard let sessions = week.schedule[day] else { continue }
                for (i, s) in sessions.enumerated() {
                    let key = appState.makeSessionKey(weekNumber: week.weekNumber, dayName: day, index: i)
                    pairs.append(SessionPair(session: s, key: key, weekNumber: week.weekNumber, dayName: day))
                }
            }
        }
        return pairs.sorted { a, b in
            sessionDate(weekNumber: a.weekNumber, dayName: a.dayName) >
            sessionDate(weekNumber: b.weekNumber, dayName: b.dayName)
        }
    }

    private func sessionDate(weekNumber: Int, dayName: String) -> Date {
        guard let startStr = appState.serverProgram?.programStartDate else { return .distantPast }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let startDate = df.date(from: startStr) else { return .distantPast }
        let cal = Calendar.current
        let dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        guard let targetIdx = dayNames.firstIndex(of: dayName) else { return .distantPast }
        let weekStart = cal.date(byAdding: .day, value: (weekNumber - 1) * 7,
                                 to: cal.startOfDay(for: startDate))!
        let weekStartWeekday = cal.component(.weekday, from: weekStart)
        var offset = (targetIdx + 1) - weekStartWeekday
        if offset < 0 { offset += 7 }
        return cal.date(byAdding: .day, value: offset, to: weekStart) ?? .distantPast
    }
}

// MARK: - Supporting Types

private struct SessionPair {
    let session: ProgramSession
    let key: String
    let weekNumber: Int
    let dayName: String
}

struct SessionWithKey: Identifiable {
    let id = UUID()
    let session: ProgramSession
    let key: String
    var dateLabel: String = ""
}

// MARK: - Session Log Detail

struct SessionLogDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let sessionWithKey: SessionWithKey

    private var log: SessionLogEntry? { appState.sessionLogs[sessionWithKey.key] }
    private var session: ProgramSession { sessionWithKey.session }

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        let color = ModalityStyle.color(for: session.modality)
                        Label(ModalityStyle.label(for: session.modality),
                              systemImage: ModalityStyle.icon(for: session.modality))
                            .font(.caption).foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.12)).clipShape(Capsule())
                        Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                            .font(.headline)
                        if !sessionWithKey.dateLabel.isEmpty {
                            Text(sessionWithKey.dateLabel)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let log {
                    // Completion
                    Section("Completion") {
                        if let completedAt = log.completedAt, !completedAt.isEmpty {
                            LabeledContent("Completed", value: formattedDate(completedAt))
                        }
                        if let source = log.source, !source.isEmpty {
                            LabeledContent("Source", value: source
                                .replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }

                    // Heart rate
                    if log.avgHR != nil || log.peakHR != nil {
                        Section("Heart Rate") {
                            if let avg = log.avgHR {
                                LabeledContent("Average") {
                                    Label("\(avg) bpm", systemImage: "heart.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            if let peak = log.peakHR {
                                LabeledContent("Peak") {
                                    Label("\(peak) bpm", systemImage: "heart.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    // Effort
                    if let fatigue = log.fatigueRating {
                        Section("Effort") {
                            LabeledContent("Fatigue Rating", value: "\(fatigue) / 10")
                        }
                    }

                    // Notes
                    if let notes = log.notes, !notes.isEmpty {
                        Section("Notes") {
                            Text(notes).font(.body)
                        }
                    }
                } else {
                    Section {
                        Label("Not yet completed", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Session Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d · h:mm a"
        return fmt.string(from: date)
    }
}

// MARK: - Bio Check-In Sheet

struct BioCheckInView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var restingHR: String = ""
    @State private var hrv: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Today's Metrics") {
                    HStack {
                        Text("Resting HR")
                        Spacer()
                        TextField("bpm", text: $restingHR)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("HRV")
                        Spacer()
                        TextField("ms", text: $hrv)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let latest = appState.recentBioLogs.first {
                    Section("Last Night's Sleep") {
                        if let sleep = latest.sleepDurationMin, sleep > 0 {
                            let h = sleep / 60; let m = sleep % 60
                            LabeledContent("Total Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        }
                        if let deep = latest.deepSleepMin, deep > 0 {
                            LabeledContent("Deep", value: "\(deep / 60)h \(deep % 60)m")
                        }
                        if let rem = latest.remSleepMin, rem > 0 {
                            LabeledContent("REM", value: "\(rem / 60)h \(rem % 60)m")
                        }
                        if let spo2 = latest.spo2Avg {
                            LabeledContent("SpO₂", value: String(format: "%.1f%%", spo2))
                        }
                        if let rr = latest.respiratoryRateAvg {
                            LabeledContent("Respiratory Rate", value: String(format: "%.1f /min", rr))
                        }
                        if let source = latest.source {
                            LabeledContent("Source", value: source.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                }
            }
            .navigationTitle("Bio Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(restingHR.isEmpty && hrv.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let today = dayFmt.string(from: Date())

        let payload = DailyBioPayload(
            restingHR: Double(restingHR),
            hrv: Double(hrv),
            sleepDurationMin: nil,
            deepSleepMin: nil,
            remSleepMin: nil,
            lightSleepMin: nil,
            awakeMins: nil,
            sleepStart: nil,
            sleepEnd: nil,
            spo2Avg: nil,
            respiratoryRateAvg: nil
        )

        try? await appState.api?.pushBio(date: today, payload: payload)
        await appState.loadRecentBioLogs()
        dismiss()
    }
}

// MARK: - ReadinessInfo color helpers

extension ReadinessInfo {
    var signalColor: Color {
        switch signal {
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .red
        }
    }
    var signalIcon: String {
        switch signal {
        case "green":  return "bolt.heart.fill"
        case "yellow": return "exclamationmark.heart.fill"
        default:       return "heart.slash.fill"
        }
    }
}
