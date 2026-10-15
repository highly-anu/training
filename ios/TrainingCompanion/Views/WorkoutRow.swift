import SwiftUI

/// One recorded workout as a row (design-system §6.23): what the device
/// recorded, when, for how long, its heart rate, the source, the planned
/// session it is linked to, and the TRIMP badge. Log ▸ Workouts lists them;
/// a session detail shows the one linked to it. The web's counterpart is
/// `components/workout/WorkoutRow.tsx`.
struct WorkoutRow: View {
    @EnvironmentObject var appState: AppState
    let workout: ImportedWorkout
    /// The TRIMP badge; nil hides it.
    let trimp: Int?
    /// The linked-session chip. Off where the row already sits on that session.
    var showsSession: Bool = true
    /// Off inside a `NavigationLink`, which draws its own.
    var showsChevron: Bool = true

    var body: some View {
        let session = linkedProgramSession(for: workout)
        let modality = workout.inferredModalityId ?? session?.modality
        // Activity first, modality second: a ride infers `aerobic_base`, whose
        // icon is a runner. The colour still comes from the modality, so the
        // row keeps its place in the palette.
        let iconName  = ActivityIcon.forWorkout(activityType: workout.activityType,
                                                modalityId: modality)
        let iconColor = modality.map { ModalityStyle.color(for: $0) } ?? Color.blue

        return HStack(spacing: 12) {
            Image(symbol: iconName)
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
                    if showsSession {
                        matchChip(session: session,
                                  isMatched: appState.matchedSessionKey(for: workout.id) != nil)
                    }
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

            if showsChevron {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
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

    // MARK: - Helpers

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
