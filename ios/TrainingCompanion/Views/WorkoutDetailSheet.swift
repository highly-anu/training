import SwiftUI

/// Full-detail sheet for a stored workout.
/// Shows GPS map, timeseries charts, stats, and a "Link to Session" flow
/// that reuses the same matching UI as FITImportSheet.
struct WorkoutDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let workout: ImportedWorkout
    var onDeleted: (() -> Void)? = nil

    private enum SheetState {
        case viewing
        case matching([(session: ProgramSession, key: String)])
        case manualPick
        case confirmed(String)   // session key
        case error(String)
    }

    @State private var state: SheetState = .viewing
    @State private var selectedSessionKey: String? = nil
    @State private var manualSearchText = ""
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    // Full workout loaded on appear (list only has metadata — no GPS/HR samples)
    @State private var fullWorkout: ImportedWorkout? = nil
    @State private var isLoadingDetail = false

    private var detail: ImportedWorkout { fullWorkout ?? workout }

    // Linked session key (from existing session logs)
    private var linkedSessionKey: String? {
        appState.sessionLogs.first(where: { $0.value.matchedWorkoutId == workout.id })?.key
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .viewing:           viewingBody
                case .matching(let s):   matchingBody(sessions: s)
                case .manualPick:        manualPickBody
                case .confirmed(let k):  confirmedBody(sessionKey: k)
                case .error(let msg):    errorBody(msg)
                }
            }
            .navigationTitle(titleFor(state))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .confirmed = state { EmptyView() }
                    else if case .viewing = state { EmptyView() }
                    else {
                        Button("Back") {
                            AppHaptics.selection()
                            state = .viewing
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if case .confirmed = state {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Delete Workout",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await performDelete() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the workout data and unlink it from any session.")
            }
        }
    }

    // MARK: - Viewing

    private var viewingBody: some View {
        List {
            workoutHeaderSection
            heroStatsSection
            if isLoadingDetail {
                Section {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading activity data…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                if let gps = detail.gpsTrack, !gps.isEmpty { routeSection(gps: gps) }
                if hasAnyTimeseries { timeseriesSection }
            }
            metricsSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .task {
            guard fullWorkout == nil, let api = appState.api else { return }
            isLoadingDetail = true
            fullWorkout = try? await api.fetchWorkout(id: workout.id)
            isLoadingDetail = false
        }
    }

    private var workoutHeaderSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: activityIcon(workout.activityType))
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.activityType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    Text(formattedDate(workout.date))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(workout.source.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if linkedSessionKey != nil {
                    Label("Linked", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var heroStatsSection: some View {
        let dur  = workout.durationMinutes
        let dist = workout.distance
        let cal  = workout.calories
        let pace = avgPaceString(dist: dist, durMin: dur)
        let avgHR = workout.heartRate?.avg

        return Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let d = dur  { statChip(value: "\(Int(d))", unit: "min", icon: "clock") }
                if let d = dist { statChip(value: String(format: "%.2f", d.value), unit: d.unit, icon: "arrow.forward") }
                if let p = pace { statChip(value: p, unit: "/km", icon: "figure.run") }
                if let c = cal  { statChip(value: "\(Int(c))", unit: "kcal", icon: "flame") }
                if let h = avgHR, dur == nil && dist == nil {
                    statChip(value: "\(h)", unit: "bpm", icon: "heart.fill")
                }
            }
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private func routeSection(gps: [GPSPoint]) -> some View {
        Section("Route") {
            WorkoutRouteMapView(points: gps)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    // MARK: - Timeseries

    @State private var chartTab: Int = 0

    private var hasHR: Bool        { !(detail.heartRate?.samples ?? []).isEmpty }
    private var hasElevation: Bool { detail.gpsTrack?.contains { $0.altitude != nil } ?? false }
    private var hasPace: Bool {
        guard let gps = detail.gpsTrack else { return false }
        return gps.filter { ($0.speed ?? 0) > 0.3 }.count >= 10
    }
    private var hasAnyTimeseries: Bool { hasHR || hasElevation || hasPace }

    private var availableTabs: [(label: String, icon: String, tag: Int)] {
        var tabs: [(String, String, Int)] = []
        if hasHR        { tabs.append(("HR",        "heart.fill",      0)) }
        if hasElevation { tabs.append(("Elevation", "mountain.2.fill", 1)) }
        if hasPace      { tabs.append(("Pace",      "figure.run",      2)) }
        return tabs
    }

    private var timeseriesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
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
                Group {
                    switch chartTab {
                    case 0:
                        if let samples = detail.heartRate?.samples, !samples.isEmpty {
                            HRTimelineView(samples: samples,
                                           avgHR: detail.heartRate?.avg,
                                           maxHR: detail.heartRate?.max)
                        }
                    case 1:
                        if let gps = detail.gpsTrack {
                            ElevationProfileView(points: gps, gainM: detail.elevation?.gain)
                        }
                    case 2:
                        if let gps = detail.gpsTrack {
                            PaceTimelineView(points: gps, distanceKm: detail.distance?.value)
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

    // MARK: - Metrics

    private var metricsSection: some View {
        let dist  = workout.distance
        let elev  = workout.elevation
        let avgHR = workout.heartRate?.avg
        let maxHR = workout.heartRate?.max
        let pace  = avgPaceString(dist: dist, durMin: workout.durationMinutes)
        let bestP = bestPaceString(gps: detail.gpsTrack ?? [])

        let hasHRStats     = avgHR != nil || maxHR != nil
        let hasActivityStats = dist != nil || elev != nil || workout.calories != nil

        return Group {
            if hasHRStats {
                Section("Heart Rate") {
                    HStack(spacing: 0) {
                        if let avg = avgHR {
                            VStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.caption).foregroundStyle(.red)
                                Text("\(avg)")
                                    .font(.title3).fontWeight(.semibold)
                                Text("avg bpm")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if avgHR != nil && maxHR != nil {
                            Divider().frame(height: 44)
                        }
                        if let peak = maxHR {
                            VStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                Text("\(peak)")
                                    .font(.title3).fontWeight(.semibold)
                                Text("peak bpm")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            if hasActivityStats {
                Section("Activity") {
                    if let d = dist {
                        LabeledContent("Distance", value: String(format: "%.2f %@", d.value, d.unit))
                    }
                    if let p = pace  { LabeledContent("Avg Pace", value: "\(p) /km") }
                    if let b = bestP { LabeledContent("Best Pace", value: "\(b) /km") }
                    if let g = elev?.gain, g > 0 { LabeledContent("Elevation Gain", value: "\(Int(g)) m") }
                    if let l = elev?.loss, l > 0 { LabeledContent("Elevation Loss", value: "\(Int(l)) m") }
                    if let c = workout.calories   { LabeledContent("Calories", value: "\(Int(c)) kcal") }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                AppHaptics.selection()
                let sessions = appState.sessionsForDate(workout.date)
                state = .matching(sessions)
            } label: {
                Label(linkedSessionKey != nil ? "Change Session Link" : "Link to Session",
                      systemImage: "link")
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                if isDeleting {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Deleting…")
                    }
                } else {
                    Label("Delete Workout", systemImage: "trash")
                }
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - Matching

    private func matchingBody(sessions: [(session: ProgramSession, key: String)]) -> some View {
        List {
            Section { workoutSummaryCard }

            if sessions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No sessions planned for \(formattedDate(workout.date))",
                              systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("You can match it to any session manually.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        AppHaptics.selection()
                        state = .manualPick
                    } label: {
                        Label("Pick a session manually", systemImage: "list.bullet")
                    }
                }
            } else {
                Section("Sessions on \(formattedDate(workout.date))") {
                    ForEach(sessions, id: \.key) { item in
                        sessionMatchRow(item, selected: selectedSessionKey == item.key)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AppHaptics.selection()
                                selectedSessionKey = selectedSessionKey == item.key ? nil : item.key
                            }
                    }
                }
                Section {
                    Button {
                        guard let key = selectedSessionKey ?? sessions.first?.key else { return }
                        Task { await doMatch(sessionKey: key) }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Link & Mark Complete").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(sessions.count > 1 && selectedSessionKey == nil)

                    Button {
                        AppHaptics.selection()
                        state = .manualPick
                    } label: {
                        Label("Pick a different session", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            if sessions.count == 1 { selectedSessionKey = sessions[0].key }
        }
    }

    // MARK: - Manual Pick

    private var manualPickBody: some View {
        let all = appState.allSessionPairs()
        let filtered = manualSearchText.isEmpty ? all : all.filter {
            $0.dateLabel.localizedCaseInsensitiveContains(manualSearchText)
            || ($0.session.archetype?.name ?? "").localizedCaseInsensitiveContains(manualSearchText)
            || ModalityStyle.label(for: $0.session.modality).localizedCaseInsensitiveContains(manualSearchText)
        }

        return List {
            Section { workoutSummaryCard }
            Section("Pick a session") {
                if filtered.isEmpty {
                    Text("No sessions found").foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.key) { item in
                        manualSessionRow(item, selected: selectedSessionKey == item.key)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AppHaptics.selection()
                                selectedSessionKey = item.key
                            }
                    }
                }
            }
            if let key = selectedSessionKey {
                Section {
                    Button {
                        Task { await doMatch(sessionKey: key) }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Link & Mark Complete").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $manualSearchText, prompt: "Search by date, name, or type")
    }

    // MARK: - Confirmed

    private func confirmedBody(sessionKey: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("Session Linked").font(.title2).fontWeight(.semibold)
            VStack(spacing: 8) {
                if let avg = workout.heartRate?.avg {
                    Label("Avg HR: \(avg) bpm", systemImage: "heart.fill").foregroundStyle(.red)
                }
                if let dist = workout.distance {
                    Label(String(format: "%.2f %@", dist.value, dist.unit), systemImage: "arrow.forward")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent).padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error

    private func errorBody(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Something went wrong").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Back") { state = .viewing }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared row subviews

    private var workoutSummaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: activityIcon(workout.activityType))
                .foregroundStyle(.blue).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Text(formattedDate(workout.date)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let dur = workout.durationMinutes {
                Text("\(Int(dur)) min").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionMatchRow(_ item: (session: ProgramSession, key: String), selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? .green : .secondary)
                .font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.session.archetype?.name ?? ModalityStyle.label(for: item.session.modality))
                    .font(.body)
                Text(ModalityStyle.label(for: item.session.modality))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: ModalityStyle.icon(for: item.session.modality))
                .foregroundStyle(ModalityStyle.color(for: item.session.modality))
        }
        .padding(.vertical, 4)
    }

    private func manualSessionRow(_ item: (session: ProgramSession, key: String, dateLabel: String), selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? .green : .secondary)
                .font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.session.archetype?.name ?? ModalityStyle.label(for: item.session.modality))
                    .font(.body)
                Text("\(item.dateLabel) · \(ModalityStyle.label(for: item.session.modality))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: ModalityStyle.icon(for: item.session.modality))
                .foregroundStyle(ModalityStyle.color(for: item.session.modality))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func doMatch(sessionKey: String) async {
        do {
            try await appState.matchAndComplete(workout: workout, sessionKey: sessionKey)
            AppHaptics.success()
            state = .confirmed(sessionKey)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func performDelete() async {
        isDeleting = true
        do {
            try await appState.deleteWorkout(id: workout.id)
            AppHaptics.success()
            onDeleted?()
            dismiss()
        } catch {
            isDeleting = false
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func titleFor(_ s: SheetState) -> String {
        switch s {
        case .viewing:    return workout.activityType.replacingOccurrences(of: "_", with: " ").capitalized
        case .matching:   return "Link to Session"
        case .manualPick: return "Pick Session"
        case .confirmed:  return "Linked"
        case .error:      return "Error"
        }
    }

    private func formattedDate(_ dateStr: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateStr) else { return dateStr }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }

    private func activityIcon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("run")   { return "figure.run" }
        if t.contains("cycl") || t.contains("bike") { return "figure.outdoor.cycle" }
        if t.contains("swim")  { return "figure.pool.swim" }
        if t.contains("hik")   { return "figure.hiking" }
        if t.contains("walk")  { return "figure.walk" }
        if t.contains("row")   { return "figure.rowing" }
        if t.contains("watch") { return "applewatch.watchface" }
        return "figure.mixed.cardio"
    }

    private func statChip(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3).fontWeight(.semibold)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func avgPaceString(dist: WorkoutDistance?, durMin: Double?) -> String? {
        guard let km = dist?.value, km > 0, let min = durMin, min > 0 else { return nil }
        return formatPace((min * 60.0) / km)
    }

    private func bestPaceString(gps: [GPSPoint]) -> String? {
        let speeds = gps.compactMap { $0.speed }.filter { $0 > 0.5 }
        guard speeds.count >= 10 else { return nil }
        let window = min(30, speeds.count / 3)
        guard window > 0 else { return nil }
        var best = 0.0
        for i in 0...(speeds.count - window) {
            let avg = speeds[i..<(i + window)].reduce(0, +) / Double(window)
            if avg > best { best = avg }
        }
        return best > 0.5 ? formatPace(1000.0 / best) : nil
    }

    private func formatPace(_ secPerKm: Double) -> String {
        String(format: "%d:%02d", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }
}
