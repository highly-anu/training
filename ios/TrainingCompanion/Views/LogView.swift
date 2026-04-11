import SwiftUI
import UniformTypeIdentifiers

struct LogView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedSegment = 0   // 0 = Workouts, 1 = Bio
    @State private var showBioEntry = false
    @State private var showImportPicker = false
    @State private var selectedWorkout: ImportedWorkout? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Workouts").tag(0)
                    Text("Bio").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: selectedSegment) { _ in AppHaptics.selection() }

                if selectedSegment == 0 { workoutsTab } else { bioTab }
            }
            .navigationTitle("Log")
            .appTabStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == 1 {
                        Button { showBioEntry = true } label: {
                            Label("Add Entry", systemImage: "plus")
                        }
                    } else {
                        Button { showImportPicker = true } label: {
                            Label("Import .fit", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailSheet(workout: workout)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showBioEntry) {
                BioCheckInView()
                    .environmentObject(appState)
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data]
            ) { result in
                if let url = try? result.get() {
                    appState.pendingFITURL = url
                }
            }
        }
    }

    // MARK: - Workouts Tab

    private var workoutsTab: some View {
        Group {
            if appState.isLoadingWorkouts && appState.importedWorkouts.isEmpty {
                VStack { Spacer(); ProgressView().scaleEffect(1.2); Spacer() }
            } else if appState.importedWorkouts.isEmpty {
                emptyState(
                    icon: "figure.run.circle",
                    title: "No Workouts",
                    subtitle: "Import a .fit file or complete a Watch session."
                )
            } else {
                List {
                    ForEach(appState.importedWorkouts) { workout in
                        workoutRow(workout)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedWorkout = workout }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let w = appState.importedWorkouts[idx]
                            Task { try? await appState.deleteWorkout(id: w.id) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    AppHaptics.light()
                    await appState.loadWorkouts()
                    AppHaptics.success()
                }
            }
        }
    }

    private func workoutRow(_ workout: ImportedWorkout) -> some View {
        let isLinked = appState.sessionLogs.values.contains { $0.matchedWorkoutId == workout.id }
        let modality = workout.inferredModalityId ?? linkedProgramSession(for: workout)?.modality
        let iconName  = modality.map { ModalityStyle.icon(for: $0) } ?? workoutRowIcon(workout.activityType)
        let iconColor = modality.map { ModalityStyle.color(for: $0) } ?? (isLinked ? .green : Color.blue)
        let title = workoutDisplayName(workout)
        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(workoutDateLabel(workout.date))
                        .font(.caption).foregroundStyle(.secondary)
                    if let dur = workout.durationMinutes {
                        Text("\(Int(dur)) min")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                let hasDist = workout.distance != nil
                let hasHR   = workout.heartRate?.avg != nil
                if hasDist && hasHR {
                    HStack(spacing: 12) {
                        logStatPill(icon: "arrow.forward",
                                    value: String(format: "%.1f", workout.distance!.value),
                                    unit: workout.distance!.unit,
                                    color: .secondary)
                        logStatPill(icon: "heart.fill",
                                    value: "\(workout.heartRate!.avg!)",
                                    unit: "bpm",
                                    color: .red)
                    }
                } else {
                    HStack(spacing: 8) {
                        if let dist = workout.distance {
                            Label(String(format: "%.1f %@", dist.value, dist.unit),
                                  systemImage: "arrow.forward")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let avg = workout.heartRate?.avg {
                            Label("\(avg) bpm", systemImage: "heart.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }

            Spacer()

            if isLinked {
                Image(systemName: "link")
                    .font(.caption).foregroundStyle(.green)
            }

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func logStatPill(icon: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(value).font(.caption).fontWeight(.medium)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func workoutDisplayName(_ workout: ImportedWorkout) -> String {
        let raw = workout.activityType
        // If activityType was set to an archetype name (not a generic watch source string), use it.
        let genericSources = ["apple_watch_live", "watch"]
        if !genericSources.contains(raw) && !raw.hasPrefix("watch_") {
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
        // Fall back to the linked program session's archetype/modality name.
        if let session = linkedProgramSession(for: workout) {
            return session.archetype?.name ?? ModalityStyle.label(for: session.modality)
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Finds the ProgramSession matched to this workout, if any.
    private func linkedProgramSession(for workout: ImportedWorkout) -> ProgramSession? {
        guard let sessionKey = appState.sessionLogs.values
            .first(where: { $0.matchedWorkoutId == workout.id })?.sessionKey else { return nil }
        let parts = sessionKey.split(separator: "-")
        guard parts.count == 3,
              let weekNum = Int(parts[0]),
              let idx = Int(parts[2]) else { return nil }
        let dayName = String(parts[1])
        guard let week = appState.serverProgram?.currentProgram?.weeks
            .first(where: { $0.weekNumber == weekNum }),
              let sessions = week.schedule[dayName],
              idx < sessions.count else { return nil }
        return sessions[idx]
    }

    private func workoutRowIcon(_ activityType: String) -> String {
        let t = activityType.lowercased()
        if t.contains("run")   { return "figure.run" }
        if t.contains("cycl")  { return "figure.outdoor.cycle" }
        if t.contains("swim")  { return "figure.pool.swim" }
        if t.contains("hik")   { return "figure.hiking" }
        if t.contains("walk")  { return "figure.walk" }
        if t.contains("row")   { return "figure.rowing" }
        if t.contains("watch") { return "applewatch.watchface" }
        return "figure.mixed.cardio"
    }

    private func workoutDateLabel(_ dateStr: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateStr) else { return dateStr }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }

    // MARK: - Bio Tab

    private var bioTab: some View {
        List {
            if appState.recentBioLogs.isEmpty {
                Section {
                    emptyState(
                        icon: "waveform.path.ecg",
                        title: "No Bio Data",
                        subtitle: "Sync from your Apple Watch or add a manual entry."
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    readinessSummaryRow
                }
                Section("Last 14 Days") {
                    ForEach(appState.recentBioLogs.prefix(14)) { log in
                        bioRow(log)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            AppHaptics.light()
            await appState.loadRecentBioLogs()
            AppHaptics.success()
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

}

// MARK: - Supporting Types

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

    @State private var matchedWorkout: ImportedWorkout? = nil
    @State private var chartTab: Int = 0   // 0=HR, 1=Elevation, 2=Pace

    private var log: SessionLogEntry? { appState.sessionLogs[sessionWithKey.key] }
    private var session: ProgramSession { sessionWithKey.session }

    // Derived convenience
    private var gps: [GPSPoint] { matchedWorkout?.gpsTrack ?? [] }
    private var hrSamples: [HRSample] { matchedWorkout?.heartRate?.samples ?? [] }
    private var hasElevation: Bool { gps.contains { $0.altitude != nil } }
    private var hasPace: Bool { gps.contains { ($0.speed ?? 0) > 0.3 } }

    // Available tabs (only those with data)
    private var availableTabs: [(label: String, icon: String, tag: Int)] {
        var tabs: [(String, String, Int)] = []
        if !hrSamples.isEmpty       { tabs.append(("HR",        "heart.fill",       0)) }
        if hasElevation             { tabs.append(("Elevation", "mountain.2.fill",  1)) }
        if hasPace                  { tabs.append(("Pace",      "figure.run",       2)) }
        return tabs
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if let log {
                    heroStatsSection(log: log)
                    if !gps.isEmpty          { routeSection }
                    if !availableTabs.isEmpty { timeseriesSection }
                    metricsSection(log: log)
                    if let fatigue = log.fatigueRating { effortSection(fatigue: fatigue) }
                    if let notes = log.notes, !notes.isEmpty { notesSection(notes: notes) }
                } else {
                    Section {
                        Label("Not yet completed", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Session Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let workoutId = log?.matchedWorkoutId {
                    matchedWorkout = try? await appState.api?.fetchWorkout(id: workoutId)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
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
    }

    private func heroStatsSection(log: SessionLogEntry) -> some View {
        let w = matchedWorkout
        let dur   = w?.durationMinutes
        let dist  = w?.distance
        let cal   = w?.calories
        let pace  = avgPaceString(dist: dist, durMin: dur)
        let avgHR = w?.heartRate?.avg ?? log.avgHR

        return Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let d = dur  { heroChip(value: "\(Int(d))", unit: "min", icon: "clock") }
                if let d = dist { heroChip(value: String(format: "%.2f", d.value), unit: d.unit, icon: "arrow.forward") }
                if let p = pace { heroChip(value: p, unit: "/km", icon: "figure.run") }
                if let c = cal  { heroChip(value: "\(Int(c))", unit: "kcal", icon: "flame") }
                if let h = avgHR, dur == nil && dist == nil { heroChip(value: "\(h)", unit: "bpm", icon: "heart.fill") }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var routeSection: some View {
        Section("Route") {
            WorkoutRouteMapView(points: gps)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private var timeseriesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                // Tab picker (only when >1 chart available)
                if availableTabs.count > 1 {
                    Picker("Chart", selection: $chartTab) {
                        ForEach(availableTabs, id: \.tag) { tab in
                            Label(tab.label, systemImage: tab.icon).tag(tab.tag)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 10)
                    .onChange(of: chartTab) { _ in AppHaptics.selection() }
                }

                // Chart content
                Group {
                    switch chartTab {
                    case 0:
                        if !hrSamples.isEmpty {
                            HRTimelineView(samples: hrSamples,
                                           avgHR: matchedWorkout?.heartRate?.avg,
                                           maxHR: matchedWorkout?.heartRate?.max)
                        }
                    case 1:
                        if hasElevation {
                            ElevationProfileView(points: gps, gainM: matchedWorkout?.elevation?.gain)
                        }
                    case 2:
                        if hasPace {
                            PaceTimelineView(points: gps, distanceKm: matchedWorkout?.distance?.value)
                        }
                    default:
                        EmptyView()
                    }
                }
                .frame(height: 160)
                .animation(.easeInOut(duration: 0.2), value: chartTab)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text(availableTabs.count == 1 ? availableTabs[0].label : "Activity Data")
        }
    }

    private func metricsSection(log: SessionLogEntry) -> some View {
        let w = matchedWorkout
        let avgHR  = w?.heartRate?.avg ?? log.avgHR
        let maxHR  = w?.heartRate?.max ?? log.peakHR
        let dist   = w?.distance
        let elev   = w?.elevation
        let cal    = w?.calories
        let pace   = avgPaceString(dist: dist, durMin: w?.durationMinutes)
        let bestP  = bestPaceString(gps: gps)
        let source = log.source

        let hasHR       = avgHR != nil || maxHR != nil
        let hasActivity = dist != nil || elev != nil || cal != nil || pace != nil

        return Group {
            if hasHR {
                Section("Heart Rate") {
                    if let avg = avgHR {
                        LabeledContent("Average") {
                            Label("\(avg) bpm", systemImage: "heart.fill").foregroundStyle(.red)
                        }
                    }
                    if let peak = maxHR {
                        LabeledContent("Peak") {
                            Label("\(peak) bpm", systemImage: "heart.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            if hasActivity {
                Section("Activity") {
                    if let d = dist {
                        LabeledContent("Distance", value: String(format: "%.2f %@", d.value, d.unit))
                    }
                    if let p = pace {
                        LabeledContent("Avg Pace", value: "\(p) /km")
                    }
                    if let b = bestP {
                        LabeledContent("Best Pace", value: "\(b) /km")
                    }
                    if let gain = elev?.gain, gain > 0 {
                        LabeledContent("Elevation Gain", value: "\(Int(gain)) m")
                    }
                    if let loss = elev?.loss, loss > 0 {
                        LabeledContent("Elevation Loss", value: "\(Int(loss)) m")
                    }
                    if let c = cal {
                        LabeledContent("Calories", value: "\(Int(c)) kcal")
                    }
                }
            }
            if let src = source, !src.isEmpty {
                Section("Source") {
                    Text(src.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func effortSection(fatigue: Int) -> some View {
        Section("Effort") {
            LabeledContent("Fatigue Rating", value: "\(fatigue) / 10")
        }
    }

    private func notesSection(notes: String) -> some View {
        Section("Notes") {
            Text(notes).font(.body)
        }
    }

    // MARK: - Helpers

    private func heroChip(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3).fontWeight(.semibold)
                Text(unit)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func avgPaceString(dist: WorkoutDistance?, durMin: Double?) -> String? {
        guard let km = dist?.value, km > 0, let min = durMin, min > 0 else { return nil }
        let secPerKm = (min * 60.0) / km
        return formatPace(secPerKm)
    }

    private func bestPaceString(gps: [GPSPoint]) -> String? {
        // Sliding 60-second window average to find fastest sustained km pace
        let speeds = gps.compactMap { $0.speed }.filter { $0 > 0.5 }
        guard speeds.count >= 10 else { return nil }
        // Best rolling 30-point average speed → best pace
        let window = min(30, speeds.count / 3)
        guard window > 0 else { return nil }
        var best = 0.0
        for i in 0...(speeds.count - window) {
            let avg = speeds[i..<(i + window)].reduce(0, +) / Double(window)
            if avg > best { best = avg }
        }
        guard best > 0.5 else { return nil }
        return formatPace(1000.0 / best)
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
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
