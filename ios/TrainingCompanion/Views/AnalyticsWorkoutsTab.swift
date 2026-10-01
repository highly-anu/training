import SwiftUI

struct AnalyticsWorkoutsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var period: AnalyticsPeriod
    @Binding var selectedWorkout: ImportedWorkout?
    @State private var sortKey: WorkoutSortKey = .date
    @State private var activityFilter: String? = nil  // nil = all types
    @State private var trimpCache: [String: Int] = [:]

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
            AnalyticsPeriodPicker(period: $period)
                .padding(.horizontal)
                .padding(.top, 4)
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
                    .onDelete { [snapshot = filtered] indexSet in
                        for idx in indexSet {
                            let w = snapshot[idx]
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
                .task(id: appState.importedWorkouts.map(\.id).joined()) {
                    let workouts = appState.importedWorkouts
                    let hrConfig = appState.profile.hrConfig
                    let dob = appState.profile.dateOfBirth
                    let result = await Task.detached(priority: .background) {
                        Dictionary(uniqueKeysWithValues: workouts.compactMap { w -> (String, Int)? in
                            guard let t = AnalyticsEngine.computeWorkoutTRIMP(
                                workout: w, hrConfig: hrConfig, dateOfBirth: dob)
                            else { return nil }
                            return (w.id, t)
                        })
                    }.value
                    trimpCache = result
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
        let session = linkedProgramSession(for: workout)
        let modality = workout.inferredModalityId ?? session?.modality
        // Activity first, modality second: a ride infers `aerobic_base`, whose
        // icon is a runner. The colour still comes from the modality, so the
        // row keeps its place in the palette.
        let iconName  = ActivityIcon.forWorkout(activityType: workout.activityType,
                                                modalityId: modality)
        let iconColor = modality.map { ModalityStyle.color(for: $0) } ?? Color.blue
        let trimp = trimpCache[workout.id]

        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(recordedTitle(workout)).font(.body)

                // What was recorded: when, for how long, and by what.
                HStack(spacing: 8) {
                    Text(workoutDateLabel(workout.date))
                        .font(.caption).foregroundStyle(.secondary)
                    if let time = workoutTimeLabel(workout) {
                        Text(time).font(.caption).foregroundStyle(.secondary)
                    }
                    if let dur = workout.durationMinutes, dur > 0 {
                        Text("\(Int(dur)) min").font(.caption).foregroundStyle(.secondary)
                    }
                }

                let distance = workout.distance.flatMap { $0.isMeaningful ? $0 : nil }
                if distance != nil || workout.heartRate?.avg != nil {
                    HStack(spacing: 10) {
                        if let dist = distance {
                            Label(String(format: "%.1f %@", dist.value, dist.unit), systemImage: "arrow.forward")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let avg = workout.heartRate?.avg {
                            Label("\(avg) bpm", systemImage: "heart.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                HStack(spacing: 6) {
                    sourceChip(workout.source)
                    matchChip(session: session,
                              isMatched: appState.matchedSessionKey(for: workout.id) != nil)
                    if isEmptyRecord(workout) {
                        Text("No data recorded")
                            .font(.caption2).foregroundStyle(.secondary)
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

            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the workout detail")
    }

    /// Where the record came from, in the athlete's language rather than the
    /// database's.
    private func sourceChip(_ source: String) -> some View {
        Text(sourceLabel(source))
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "garmin":           return "Garmin"
        case "fit_file":         return "FIT file"
        case "apple_watch_live": return "Apple Watch"
        case "apple_health":     return "Apple Health"
        case "strava":           return "Strava"
        case "manual":           return "Manual"
        default:                 return source.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The planned session this workout was matched to.
    ///
    /// Three states, not two: a workout can be matched to a session that is no
    /// longer in the loaded program — an older block, say — and calling that
    /// "Unmatched" contradicts the detail page, which reads the match itself.
    @ViewBuilder
    private func matchChip(session: ProgramSession?, isMatched: Bool) -> some View {
        if let session {
            let color = ModalityStyle.color(for: session.modality)
            Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                .font(.caption2).fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        } else if isMatched {
            Label("Linked", systemImage: "link")
                .font(.caption2).fontWeight(.medium)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(Color.green)
                .clipShape(Capsule())
        } else {
            Text("Unmatched")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.systemGray6))
                .foregroundStyle(.tertiary)
                .clipShape(Capsule())
        }
    }

    /// True when the record carries no measurement at all — the shape left by a
    /// watch session that was started and abandoned, or by a simulator.
    private func isEmptyRecord(_ workout: ImportedWorkout) -> Bool {
        (workout.durationMinutes ?? 0) <= 0
            && workout.distance == nil
            && workout.heartRate?.avg == nil
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
        guard let sessionKey = appState.matchedSessionKey(for: workout.id) else { return nil }
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

    /// What the device recorded — never the name of the session that was
    /// planned.
    ///
    /// This used to fall back to the matched session's name, which is the main
    /// reason a list of imported workouts read as a list of programmed ones.
    /// The planned session is still shown, as a badge, where it cannot be
    /// mistaken for the activity itself.
    private func recordedTitle(_ workout: ImportedWorkout) -> String {
        workout.recordedTitle
    }

    private static let timeDisplay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// Time of day, which is what tells two sessions on the same day apart.
    private func workoutTimeLabel(_ workout: ImportedWorkout) -> String? {
        guard let start = workout.startTime,
              let date = ISO8601DateFormatter().date(from: start)
                ?? {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return f.date(from: start)
                }()
        else { return nil }
        return Self.timeDisplay.string(from: date)
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let dateDisplay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    private func workoutDateLabel(_ dateStr: String) -> String {
        guard let date = Self.dateParser.date(from: dateStr) else { return dateStr }
        return Self.dateDisplay.string(from: date)
    }
}
