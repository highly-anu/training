import SwiftUI

struct FITImportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private enum ImportState {
        case uploading
        case matching(ImportedWorkout, [(session: ProgramSession, key: String)])
        case manualPick(ImportedWorkout)
        case confirmed(ImportedWorkout)
        case error(String)
    }

    @SwiftUI.State private var importState: ImportState = .uploading
    @SwiftUI.State private var selectedSessionKey: String? = nil
    @SwiftUI.State private var manualSearchText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                switch importState {
                case .uploading:
                    uploadingView
                case .matching(let workout, let sessions):
                    matchingView(workout: workout, sessions: sessions)
                case .manualPick(let workout):
                    manualPickView(workout: workout)
                case .confirmed(let workout):
                    confirmedView(workout: workout)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Import Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .confirmed = importState { EmptyView() }
                    else { Button("Cancel") { dismiss() } }
                }
            }
        }
        .task { await upload() }
        .interactiveDismissDisabled({ if case .uploading = importState { return true }; return false }())
    }

    // MARK: - Uploading

    private var uploadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("Parsing workout…").font(.headline)
            if let url = appState.pendingFITURL {
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Matching (date-based)

    private func matchingView(workout: ImportedWorkout, sessions: [(session: ProgramSession, key: String)]) -> some View {
        List {
            Section { workoutSummaryCard(workout) }

            if sessions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No sessions planned for \(formattedDate(workout.date))", systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Workout saved. You can match it to any session manually.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        AppHaptics.selection()
                        importState = .manualPick(workout)
                    } label: {
                        Label("Match to a session manually", systemImage: "link")
                    }
                    Button("Save without matching") { dismiss() }
                        .foregroundStyle(.secondary)
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
                        Task { await matchSession(workout: workout, sessionKey: key) }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Match & Mark Complete").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(sessions.count > 1 && selectedSessionKey == nil)

                    Button {
                        AppHaptics.selection()
                        importState = .manualPick(workout)
                    } label: {
                        Label("Match to a different session", systemImage: "arrow.triangle.2.circlepath")
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

    private func manualPickView(workout: ImportedWorkout) -> some View {
        let all = appState.allSessionPairs()
        let filtered: [(session: ProgramSession, key: String, dateLabel: String)] = manualSearchText.isEmpty
            ? all
            : all.filter {
                $0.dateLabel.localizedCaseInsensitiveContains(manualSearchText)
                || ($0.session.archetype?.name ?? "").localizedCaseInsensitiveContains(manualSearchText)
                || ModalityStyle.label(for: $0.session.modality).localizedCaseInsensitiveContains(manualSearchText)
            }

        return List {
            Section { workoutSummaryCard(workout) }

            Section("Pick a session to match") {
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

            if selectedSessionKey != nil {
                Section {
                    Button {
                        guard let key = selectedSessionKey else { return }
                        Task { await matchSession(workout: workout, sessionKey: key) }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Match & Mark Complete").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $manualSearchText, prompt: "Search by date, name, or type")
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    let sessions = appState.sessionsForDate(workout.date)
                    importState = .matching(workout, sessions)
                }
            }
        }
    }

    // MARK: - Confirmed

    private func confirmedView(workout: ImportedWorkout) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Session Marked Complete")
                .font(.title2).fontWeight(.semibold)
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
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48)).foregroundStyle(.orange)
                    .padding(.top, 40)
                Text("Import Failed").font(.headline)
                Text(message)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                HStack(spacing: 16) {
                    Button("Retry") { Task { await upload() } }.buttonStyle(.bordered)
                    Button("Dismiss") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Row helpers

    private func workoutSummaryCard(_ workout: ImportedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activityIcon(workout.activityType))
                    .foregroundStyle(.blue).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.activityType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    Text(formattedDate(workout.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                if let dur = workout.durationMinutes {
                    statChip(value: "\(Int(dur))", unit: "min", icon: "clock")
                }
                if let dist = workout.distance {
                    statChip(value: String(format: "%.1f", dist.value), unit: dist.unit, icon: "arrow.forward")
                }
                if let avg = workout.heartRate?.avg {
                    statChip(value: "\(avg)", unit: "bpm", icon: "heart.fill")
                }
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

    private func upload() async {
        guard let url = appState.pendingFITURL else { return }
        importState = .uploading
        do {
            let workout = try await appState.parseFITFile(url: url)
            let sessions = appState.sessionsForDate(workout.date)
            importState = .matching(workout, sessions)
        } catch {
            importState = .error(error.localizedDescription)
        }
    }

    private func matchSession(workout: ImportedWorkout, sessionKey: String) async {
        do {
            try await appState.matchAndComplete(workout: workout, sessionKey: sessionKey)
            AppHaptics.success()
            importState = .confirmed(workout)
        } catch {
            importState = .error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ dateStr: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateStr) else { return dateStr }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }

    private func activityIcon(_ activityType: String) -> String {
        let lower = activityType.lowercased()
        if lower.contains("run") { return "figure.run" }
        if lower.contains("cycl") || lower.contains("bike") { return "figure.outdoor.cycle" }
        if lower.contains("swim") { return "figure.pool.swim" }
        if lower.contains("hik") { return "figure.hiking" }
        if lower.contains("walk") { return "figure.walk" }
        if lower.contains("row") { return "figure.rowing" }
        if lower.contains("strength") || lower.contains("weight") { return "dumbbell" }
        return "figure.mixed.cardio"
    }

    private func statChip(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).fontWeight(.medium)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
