import SwiftUI

/// "Workout complete" (design-system §6.30): the sheet the phone shows the
/// first time it sees a newly stored workout — from the watch, Garmin,
/// Strava or Apple Health. What was done, a word of credit, what it measured,
/// and the planned session it belongs to, confirmed with one tap.
///
/// `AppState.noticeCompletedWorkout()` picks the workout (`WorkoutCompletion`)
/// and `ContentView` presents this; closing it marks every listed workout
/// seen. The numbers are the server's (`GET /health/workouts/<id>`'s
/// `analysis`); nothing is computed here.
struct WorkoutCompleteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let workout: ImportedWorkout

    @State private var analysis: WorkoutAnalysis? = nil
    /// The recorded track — the list row carries none (§6.10).
    @State private var track: [GPSPoint] = []
    /// The full record, handed to Details so it is not downloaded twice.
    @State private var full: ImportedWorkout? = nil
    @State private var appeared = false
    /// The session key a link is in flight for.
    @State private var linkingKey: String? = nil
    /// Bumped on a confirmed link, to bounce the completion mark.
    @State private var celebrations = 0
    @State private var linkError: String? = nil

    var body: some View {
        // Once per render: each call scans the program and the suggestions.
        let match = appState.completionMatch(for: workout)
        let tint = tint(for: match)
        let dots = weekDots
        let weekNumber = Self.dayParser.date(from: workout.date).flatMap { appState.week(for: $0)?.weekNumber }
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero(match: match, dots: dots, tint: tint)
                    statsGrid(tint: tint)
                    if WorkoutRoute.hasRoute(track) { routeCard }
                    if let analysis, analysis.distribution != nil || analysis.effect != nil
                        || analysis.recoveryHours != nil {
                        effortCard(analysis)
                    }
                    matchCard(match)
                    if !dots.isEmpty { weekCard(dots, number: weekNumber) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { actionBar(match) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        WorkoutDetailView(workout: workout,
                                          prefetched: full?.id == workout.id ? full : nil)
                            .environmentObject(appState)
                    } label: {
                        Label("Details", systemImage: "chart.xyaxis.line")
                    }
                    .accessibilityHint("Opens the workout's charts and map")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            // Keyed on the workout: a demo presents one sheet after another,
            // and SwiftUI kept the first one's state for the next — the
            // kettlebell session showed the run's route and load.
            .task(id: workout.id) {
                full = nil
                track = []
                analysis = nil
                guard let api = appState.api else { return }
                let loaded = try? await api.fetchWorkout(id: workout.id)
                guard loaded?.id == workout.id else { return }
                full = loaded
                track = loaded?.gpsTrack ?? []
                withAnimation(.easeOut(duration: 0.2)) { analysis = loaded?.analysis }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            appState.completedWorkoutOnScreen = true
            AppHaptics.success()
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }

    // MARK: - Hero

    /// What was recorded first; the linked session's modality only when the
    /// record names none.
    private func modalityId(for match: WorkoutCompletion.Match) -> String? {
        if let inferred = workout.inferredModalityId { return inferred }
        if case .linked(_, let s?) = match { return s.modality }
        return nil
    }

    private func tint(for match: WorkoutCompletion.Match) -> Color {
        modalityId(for: match).map { ModalityStyle.color(for: $0) } ?? .accentColor
    }

    private func hero(match: WorkoutCompletion.Match, dots: [WorkoutCompletion.WeekDot], tint: Color) -> some View {
        let linked: Bool = { if case .linked = match { return true }; return false }()
        let planned: Bool = {
            switch match {
            case .unplanned: return false
            case .linked(_, let s): return s != nil
            default: return true
            }
        }()
        let cheer = WorkoutCompletion.cheer(for: workout, linked: linked, planned: planned,
                                            weekDone: dots.filter(\.done).count, weekTotal: dots.count)
        return VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(tint.opacity(0.15))
                    .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 2))
                    .frame(width: 104, height: 104)
                    .overlay(
                        Image(symbol: ActivityIcon.forWorkout(activityType: workout.activityType,
                                                              modalityId: modalityId(for: match)))
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(tint)
                    )
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white, .green)
                    .background(Circle().fill(Color(.systemBackground)).padding(-3))
                    .symbolEffect(.bounce, value: celebrations)
                    .offset(x: 4, y: 4)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 6)
            .accessibilityHidden(true)

            Text("Workout complete")
                .font(.caption).fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.green)
            Text(workout.recordedTitle)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(metaLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(cheer)
                .font(.subheadline).fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// "Fri, Oct 17 · 07:12 · Garmin"
    private var metaLine: String {
        var parts: [String] = []
        if let day = Self.dayParser.date(from: workout.date) { parts.append(Self.dayDisplay.string(from: day)) }
        if let start = LogSessions.parseServerDate(workout.startTime) {
            parts.append(Self.timeDisplay.string(from: start))
        }
        parts.append(ImportedWorkout.sourceLabel(workout.source))
        return parts.joined(separator: " · ")
    }

    // MARK: - Numbers

    private struct Stat: Identifiable {
        let id: String
        let symbol: String
        let color: Color
        let value: String
        let unit: String
        let spoken: String
    }

    private func stats(tint: Color) -> [Stat] {
        var out: [Stat] = []
        if let minutes = workout.durationMinutes, minutes >= 1 {
            let m = Int(minutes.rounded())
            out.append(m >= 60
                ? Stat(id: "time", symbol: "clock.fill", color: .secondary,
                       value: String(format: "%d:%02d", m / 60, m % 60), unit: "h:mm",
                       spoken: "\(m / 60) hours \(m % 60) minutes")
                : Stat(id: "time", symbol: "clock.fill", color: .secondary,
                       value: "\(m)", unit: "min", spoken: "\(m) minutes"))
        }
        if let d = workout.distance, d.isMeaningful {
            out.append(Stat(id: "distance", symbol: "arrow.forward", color: tint,
                            value: String(format: d.value >= 100 ? "%.0f" : "%.1f", d.value), unit: d.unit,
                            spoken: String(format: "%.1f %@", d.value, d.unit)))
        }
        if let avg = workout.heartRate?.avg {
            out.append(Stat(id: "avg", symbol: "heart.fill", color: .red,
                            value: "\(avg)", unit: "avg bpm", spoken: "average heart rate \(avg)"))
        }
        if let trimp = analysis?.trimp {
            out.append(Stat(id: "trimp", symbol: "gauge.with.dots.needle.67percent",
                            color: TrimpStyle.color(trimp), value: "\(trimp)", unit: "load",
                            spoken: "training load \(trimp), \(TrimpStyle.label(trimp))"))
        }
        if let gain = workout.elevation?.gain, gain >= 1 {
            out.append(Stat(id: "gain", symbol: "mountain.2.fill", color: .brown,
                            value: "+\(Int(gain.rounded()))", unit: "m", spoken: "\(Int(gain)) metres climbed"))
        }
        if let kcal = workout.calories, kcal >= 1 {
            out.append(Stat(id: "kcal", symbol: "flame.fill", color: .orange,
                            value: "\(Int(kcal.rounded()))", unit: "kcal", spoken: "\(Int(kcal)) calories"))
        }
        if let max = workout.heartRate?.max {
            out.append(Stat(id: "max", symbol: "bolt.heart.fill", color: .red,
                            value: "\(max)", unit: "max bpm", spoken: "peak heart rate \(max)"))
        }
        // Two full rows at most: the first six, in this order of interest.
        return Array(out.prefix(6))
    }

    @ViewBuilder
    private func statsGrid(tint: Color) -> some View {
        let items = stats(tint: tint)
        if !items.isEmpty {
            // Four read as two by two; otherwise rows of three.
            let columns = items.count == 4 ? 2 : 3
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: stat.symbol)
                            .font(.caption)
                            .foregroundStyle(stat.color)
                        Text(stat.value)
                            .font(.title3).fontWeight(.bold)
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(stat.unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(0.1 + Double(index) * 0.04), value: appeared)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stat.spoken)
                }
            }
        }
    }

    // MARK: - Route

    /// Where it went, flat; the 3D Swiss view and the charts are one tap away
    /// under Details.
    private var routeCard: some View {
        AnalyticsCard(header: "Route") {
            WorkoutRouteMapView(points: WorkoutRoute.fixes(track))
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Map of the route")
        }
    }

    // MARK: - Effort

    private func effortCard(_ a: WorkoutAnalysis) -> some View {
        AnalyticsCard(header: "Effort") {
            if let effect = a.effect {
                TintCapsule(text: effect.rawValue, symbol: effect.icon, color: effect.color, bordered: true)
                    .accessibilityLabel("Training effect: \(effect.rawValue)")
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let z = a.distribution {
                    zoneBar(z)
                }
                if let hours = a.recoveryHours {
                    Label("\(hours) h", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("About \(hours) hours to recover")
                }
            }
        }
    }

    /// The zones as one bar, each segment as wide as its share, with the
    /// share under the zones that have one.
    private func zoneBar(_ z: HRZoneDistribution) -> some View {
        let pcts = [z.z1, z.z2, z.z3, z.z4, z.z5]
        let total = max(pcts.reduce(0, +), 1)
        let shown = (0..<5).filter { pcts[$0] > 0 }
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(shown, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(HRZoneStyle.colors[i])
                            .frame(width: max(4, (geo.size.width - CGFloat(shown.count - 1) * 2)
                                              * pcts[i] / total))
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 10) {
                ForEach(shown, id: \.self) { i in
                    HStack(spacing: 3) {
                        Circle().fill(HRZoneStyle.colors[i]).frame(width: 6, height: 6)
                        Text("Z\(i + 1) \(Int(pcts[i].rounded()))%")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.map { "Zone \($0 + 1) \(Int(pcts[$0].rounded())) percent" }
            .joined(separator: ", "))
    }

    // MARK: - Match

    @ViewBuilder
    private func matchCard(_ match: WorkoutCompletion.Match) -> some View {
        switch match {
        case .linked(let key, let session):
            AnalyticsCard(header: "Planned session") {
                TintCapsule(text: "Linked", symbol: "link", color: .green)
            } content: {
                if let session {
                    sessionRow(session, key: key) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: celebrations)
                            .accessibilityLabel("Complete")
                    }
                } else {
                    Label("An earlier program's session", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

        case .suggested(let key, let session, let others):
            AnalyticsCard(header: "Is this the session?") {
                TintCapsule(text: "Suggested", symbol: "sparkles", color: .orange)
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    if let session {
                        sessionRow(session, key: key, highlight: .orange) {
                            Button("Not this") {
                                AppHaptics.light()
                                Task { await appState.dismissSuggestion(workoutId: workout.id) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    if !others.isEmpty {
                        Text("Or").font(.caption).foregroundStyle(.secondary)
                        ForEach(others) { candidate in candidateRow(candidate) }
                    }
                    errorLine
                }
            }

        case .candidates(let candidates):
            AnalyticsCard(header: "Planned that day") {
                TintCapsule(text: "Unlinked", symbol: "link.badge.plus", color: .secondary)
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates) { candidate in candidateRow(candidate) }
                    errorLine
                }
            }

        case .unplanned:
            AnalyticsCard(header: "Planned session") {
                TintCapsule(text: "Extra", symbol: "plus.circle", color: .secondary)
            } content: {
                Label("Nothing planned that day", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func candidateRow(_ c: WorkoutCompletion.Candidate) -> some View {
        sessionRow(c.session, key: c.key) {
            Button {
                link(c.key)
            } label: {
                if linkingKey == c.key {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Link")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(ModalityStyle.color(for: c.session.modality))
            .disabled(linkingKey != nil)
            .accessibilityLabel("Link to \(sessionName(c.session))")
        }
    }

    /// A planned session as a compact row: modality colour and icon, the
    /// session's name, the modality and its minutes, then the row's action.
    private func sessionRow<Trailing: View>(_ s: ProgramSession, key: String, highlight: Color? = nil,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        let color = ModalityStyle.color(for: s.modality)
        return HStack(spacing: 12) {
            Image(systemName: ModalityStyle.icon(for: s.modality))
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionName(s))
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TintCapsule(text: ModalityStyle.label(for: s.modality), color: color, bordered: true)
                    if let minutes = s.archetype?.durationEstimateMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke((highlight ?? color).opacity(0.35), lineWidth: 1))
    }

    private func sessionName(_ s: ProgramSession) -> String {
        s.archetype?.name ?? ModalityStyle.label(for: s.modality)
    }

    @ViewBuilder
    private var errorLine: some View {
        if let linkError {
            Label(linkError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Week

    private var weekDots: [WorkoutCompletion.WeekDot] {
        guard let day = Self.dayParser.date(from: workout.date),
              let week = appState.week(for: day) else { return [] }
        // A linked session is done here even before a log exists: the
        // server's auto-match writes the match, not a session log.
        return WorkoutCompletion.weekDots(week) {
            appState.isSessionComplete($0) || appState.linkedWorkout(forSessionKey: $0) != nil
        }
    }

    private func weekCard(_ dots: [WorkoutCompletion.WeekDot], number: Int?) -> some View {
        let done = dots.filter(\.done).count
        return AnalyticsCard(header: number.map { "Week \($0)" } ?? "This week") {
            Label("\(done)/\(dots.count)", systemImage: "checkmark.circle")
                .font(.caption).fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(done == dots.count ? .green : .secondary)
                .contentTransition(.numericText())
        } content: {
            HStack(spacing: 6) {
                ForEach(dots) { dot in
                    let color = ModalityStyle.color(for: dot.modality)
                    Circle()
                        .fill(dot.done ? color : color.opacity(0.12))
                        .overlay(Circle().stroke(color.opacity(dot.done ? 0 : 0.5), lineWidth: 1.5))
                        .overlay {
                            if dot.done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 16, height: 16)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) of \(dots.count) sessions done in the week")
        }
    }

    // MARK: - Actions

    private func actionBar(_ match: WorkoutCompletion.Match) -> some View {
        VStack(spacing: 0) {
            if case .suggested(let key, _, _) = match {
                Button {
                    link(key)
                } label: {
                    HStack(spacing: 8) {
                        if linkingKey == key {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Confirm & complete")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .font(.subheadline).fontWeight(.semibold)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(linkingKey != nil)
            } else {
                Button {
                    AppHaptics.light()
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .font(.subheadline).fontWeight(.semibold)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Link the workout to a session of the current program and mark it
    /// complete — the same path as Today's Accept.
    private func link(_ key: String) {
        linkingKey = key
        linkError = nil
        Task {
            do {
                try await appState.matchAndComplete(workout: workout, sessionKey: key)
                AppHaptics.success()
                withAnimation(.easeOut(duration: 0.2)) { celebrations += 1 }
            } catch {
                AppHaptics.warning()
                linkError = "Couldn't link — try again from Log ▸ Linking."
            }
            linkingKey = nil
        }
    }

    // MARK: - Formatting

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayDisplay: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE MMM d"); return f
    }()
    private static let timeDisplay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
