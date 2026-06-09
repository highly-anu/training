import SwiftUI

struct AnalyticsWorkoutsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var period: AnalyticsPeriod
    @Binding var selectedWorkout: ImportedWorkout?
    @State private var sortKey: WorkoutSortKey = .date
    @State private var activityFilter: String? = nil  // nil = all types

    // MARK: - Filtered + Sorted Workouts

    private var filtered: [ImportedWorkout] {
        var ws = AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
        if let f = activityFilter {
            ws = ws.filter { $0.activityType.replacingOccurrences(of: "_", with: " ").capitalized == f }
        }
        switch sortKey {
        case .date:     return ws.sorted { $0.date > $1.date }
        case .duration: return ws.sorted { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
        case .distance: return ws.sorted { ($0.distance?.value ?? 0) > ($1.distance?.value ?? 0) }
        case .avgHR:    return ws.sorted { ($0.heartRate?.avg ?? 0) > ($1.heartRate?.avg ?? 0) }
        }
    }

    private var uniqueActivityTypes: [String] {
        Array(Set(AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
            .map { $0.activityType.replacingOccurrences(of: "_", with: " ").capitalized }
        )).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            filterSortBar
            Divider()
            if appState.isLoadingWorkouts && appState.importedWorkouts.isEmpty {
                Spacer()
                ProgressView().scaleEffect(1.2)
                Spacer()
            } else if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { workout in
                        workoutRow(workout)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedWorkout = workout }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let w = filtered[idx]
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

    // MARK: - Filter / Sort Bar

    private var filterSortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort pills
                ForEach(WorkoutSortKey.allCases) { key in
                    Button {
                        AppHaptics.selection()
                        sortKey = key
                    } label: {
                        Text(key.rawValue)
                            .font(.caption).fontWeight(sortKey == key ? .semibold : .regular)
                            .foregroundStyle(sortKey == key ? .white : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(sortKey == key ? Color.blue : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if uniqueActivityTypes.count > 1 {
                    Divider().frame(height: 20)
                    // Activity type filter chips
                    Button {
                        AppHaptics.selection()
                        withAnimation { activityFilter = nil }
                    } label: {
                        Text("All")
                            .font(.caption).fontWeight(activityFilter == nil ? .semibold : .regular)
                            .foregroundStyle(activityFilter == nil ? .white : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(activityFilter == nil ? Color.purple : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    ForEach(uniqueActivityTypes, id: \.self) { type in
                        Button {
                            AppHaptics.selection()
                            withAnimation { activityFilter = activityFilter == type ? nil : type }
                        } label: {
                            Text(type)
                                .font(.caption).fontWeight(activityFilter == type ? .semibold : .regular)
                                .foregroundStyle(activityFilter == type ? .white : .primary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(activityFilter == type ? Color.purple : Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Workout Row (mirrors LogView.workoutRow + TRIMP badge)

    private func workoutRow(_ workout: ImportedWorkout) -> some View {
        let isLinked = appState.sessionLogs.values.contains { $0.matchedWorkoutId == workout.id }
        let modality = workout.inferredModalityId ?? linkedProgramSession(for: workout)?.modality
        let iconName  = modality.map { ModalityStyle.icon(for: $0) } ?? activityIcon(workout.activityType)
        let iconColor = modality.map { ModalityStyle.color(for: $0) } ?? (isLinked ? .green : Color.blue)
        let trimp = AnalyticsEngine.computeWorkoutTRIMP(workout: workout,
                                                        hrConfig: appState.profile.hrConfig,
                                                        dateOfBirth: appState.profile.dateOfBirth)

        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(workoutDisplayName(workout)).font(.body)
                HStack(spacing: 8) {
                    Text(workoutDateLabel(workout.date))
                        .font(.caption).foregroundStyle(.secondary)
                    if let dur = workout.durationMinutes {
                        Text("\(Int(dur)) min").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if workout.distance != nil || workout.heartRate?.avg != nil {
                    HStack(spacing: 10) {
                        if let dist = workout.distance {
                            Label(String(format: "%.1f %@", dist.value, dist.unit), systemImage: "arrow.forward")
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

            // TRIMP badge (Strava/Whoop-style load number)
            if let t = trimp {
                VStack(spacing: 1) {
                    Text("\(t)")
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(trimpColor(t))
                    Text("load")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 40)
            }

            if isLinked {
                Image(systemName: "link").font(.caption).foregroundStyle(.green)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func trimpColor(_ trimp: Int) -> Color {
        switch trimp {
        case ..<40:  return .secondary
        case 40..<70: return .blue
        case 70..<100: return .orange
        default:       return .red
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(activityFilter != nil ? "No \(activityFilter!) workouts" : "No Workouts")
                .font(.headline)
            Text(appState.importedWorkouts.isEmpty
                 ? "Import a .fit file or complete a Watch session."
                 : "Try a longer period or remove the activity filter.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            if activityFilter != nil {
                Button("Clear Filter") {
                    AppHaptics.light()
                    withAnimation { activityFilter = nil }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers (mirrored from LogView)

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

    private func workoutDisplayName(_ workout: ImportedWorkout) -> String {
        let raw = workout.activityType
        let genericSources = ["apple_watch_live", "watch"]
        if !genericSources.contains(raw) && !raw.hasPrefix("watch_") {
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let session = linkedProgramSession(for: workout) {
            return session.archetype?.name ?? ModalityStyle.label(for: session.modality)
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func activityIcon(_ activityType: String) -> String {
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
}
