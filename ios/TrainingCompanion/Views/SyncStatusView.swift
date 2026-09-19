import SwiftUI
import WatchConnectivity

struct SyncStatusView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var appState: AppState
    @ObservedObject private var logger = AppLogger.shared

    @State private var showDebugLog = false
    @State private var garminDevices: [PairedDevice] = []
    @State private var isLoadingDevices = false
    @State private var garminCode = ""
    @State private var isClaiming = false
    @State private var claimError: String?
    @State private var justPaired = false
    @State private var lastGarminPushDate: Date? = UserDefaults.standard.object(forKey: "lastGarminProgramSyncDate") as? Date

    private var watchPaired: Bool { WCSession.default.isPaired }
    private var watchReachable: Bool { WCSession.default.isReachable }
    private var normalizedCode: String { garminCode.trimmingCharacters(in: .whitespaces).uppercased() }
    private var canClaim: Bool { normalizedCode.count == 6 && !isClaiming }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
    private let monFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                devicesSection
                pairGarminSection
                syncCategoriesSection
                debugLogSection
            }
            .navigationTitle("Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) { auth.signOut() }
                        .font(.footnote)
                }
            }
            .task { await loadGarminDevices() }
        }
    }

    // MARK: - Devices + Sync Now (all in one section so button clearly covers all)

    private var devicesSection: some View {
        Section {
            // iPhone ↔ API
            HStack {
                Label("iPhone ↔ API", systemImage: "network")
                Spacer()
                if sync.isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else if sync.lastError != nil {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote)
                } else {
                    Text(sync.lastSyncDate != nil ? "Connected" : "Not synced")
                        .foregroundStyle(sync.lastSyncDate != nil ? .green : .secondary)
                        .font(.footnote)
                }
            }

            // Apple Watch
            HStack {
                Label("Apple Watch", systemImage: "applewatch")
                Spacer()
                if watchPaired {
                    Text(watchReachable ? "Reachable" : "Paired")
                        .foregroundStyle(watchReachable ? .green : .secondary).font(.footnote)
                } else {
                    Text("Not paired").foregroundStyle(.secondary).font(.footnote)
                }
            }

            // Garmin — one row per device, or placeholder
            if isLoadingDevices {
                HStack {
                    Label("Garmin", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                }
            } else if garminDevices.isEmpty {
                HStack {
                    Label("Garmin", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text("Not paired").foregroundStyle(.secondary).font(.footnote)
                }
        } else {
                ForEach(garminDevices) { d in
                    HStack {
                        Label(d.deviceName ?? "Garmin Watch",
                              systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        if let last = d.lastUsedAt {
                            Text(String(last.prefix(10)))
                                .foregroundStyle(.secondary).font(.footnote)
                        } else {
                            Text("Paired").foregroundStyle(.green).font(.footnote)
                        }
                    }
                }
            }

            // Sync Now — visually tied to all device rows above
            Button {
                Task { await runFullSync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: sync.isSyncing)
                    Text(sync.isSyncing ? "Syncing…" : "Sync Now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sync.isSyncing)

        } header: {
            Text("Devices")
        } footer: {
            if let err = sync.lastError {
                Text(err).foregroundStyle(.orange)
            } else if let last = sync.lastSyncDate {
                Text("Last full sync: \(timeFmt.string(from: last))")
            }
        }
    }

    // MARK: - Pair Garmin Watch (separate section, below Sync Now)

    private var pairGarminSection: some View {
        Section {
            TextField("6-character code", text: $garminCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .onChange(of: garminCode) { _, v in
                    let cleaned = v.uppercased().filter { !$0.isWhitespace }
                    garminCode = String(cleaned.prefix(6))
                }

            Button {
                Task { await claimGarmin() }
            } label: {
                HStack {
                    if isClaiming { ProgressView().padding(.trailing, 4) }
                    Text(isClaiming ? "Pairing…" : "Pair Garmin Watch")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canClaim)

            if let claimError {
                Text(claimError).foregroundStyle(.red).font(.footnote)
            }
            if justPaired {
                Label("Paired! Open the Training app on your watch to sync.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.footnote)
            }
        } header: {
            Text("Pair Garmin Watch")
        } footer: {
            Text("Open the Training app on your Garmin — it shows a 6-character code.")
        }
    }

    // MARK: - Sync Categories

    private var syncCategoriesSection: some View {
        Section("Sync Details") {
            syncRow(
                icon: "person.crop.circle",
                label: "Profile Sync",
                date: appState.lastProfileSyncAt,
                detail: "Equipment, schedule, injuries",
                logKeyword: "profile:"
            )

            syncRow(
                icon: "calendar.badge.clock",
                label: "Apple Watch Program",
                date: UserDefaults.standard.object(forKey: "lastProgramSyncDate") as? Date,
                detail: "Today's sessions sent to Watch",
                logKeyword: "program"
            )

            syncRow(
                icon: "dot.radiowaves.left.and.right",
                label: "Garmin Program",
                date: lastGarminPushDate,
                detail: garminDevices.isEmpty ? "No Garmin paired" : "Not yet pushed",
                logKeyword: "garmin"
            )

            syncRow(
                icon: "heart.text.square",
                label: "Bio Sync",
                date: sync.lastBioSyncDate,
                detail: sync.lastBioPushedCount > 0 ? "\(sync.lastBioPushedCount) days pushed" : "Up to date",
                logKeyword: "bio"
            )

            watchUploadRow
            watchSessionRow
        }
    }

    // MARK: - Sync logic

    private func runFullSync() async {
        await sync.syncAll()

        // The SERVER is the source of truth for the program.
        //
        // This used to push appState.serverProgram back to the server on every
        // sync, "so Garmin can fetch it". That was both unnecessary and
        // destructive: Garmin reads GET /user/today-session from the server
        // directly and never needed the phone to re-upload, while the phone's
        // in-memory copy is only refreshed by loadProgram() — which this path
        // did not call. So generating a program on the web and then pressing
        // Sync on the phone overwrote the new program with the phone's stale
        // copy, and the web, phone and watch all reverted together.
        //
        // Pull first. Only push when the server genuinely has nothing.
        await appState.loadProgram()

        if appState.serverProgram == nil {
            AppLogger.shared.log("program: server has none — nothing to pull")
        } else {
            let startDate = appState.serverProgram?.programStartDate ?? "nil"
            AppLogger.shared.log("program: pulled from server (startDate=\(startDate))")
            let now = Date()
            lastGarminPushDate = now
            UserDefaults.standard.set(now, forKey: "lastGarminProgramSyncDate")

            // Verify what Garmin would actually receive.
            if let api = appState.api {
                let status = (try? await api.fetchTodaySessionStatus()) ?? "error"
                AppLogger.shared.log("garmin: today-session status = \(status)")
                if status == "program_expired" || status == "not_started" {
                    await resetProgramStartToToday()
                }
            }
        }

        await appState.loadProfile()
        await appState.loadPerformanceLogs()
        await appState.loadRecentBioLogs()
        await appState.loadReadiness()
        await appState.loadWorkouts()
        await loadGarminDevices()
    }

    private func resetProgramStartToToday() async {
        guard let sp = appState.serverProgram else { return }
        let cal = Calendar.current
        let today = Date()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        // Monday of the current week
        let weekday = cal.component(.weekday, from: today)  // 1=Sun … 7=Sat
        let daysToMonday = (weekday == 1 ? -6 : 2 - weekday)
        guard let monday = cal.date(byAdding: .day, value: daysToMonday, to: today) else { return }

        // Preserve the cyclic week index so the same week's sessions are shown.
        // Without this, resetting to week 0 shows a different (possibly rest) week.
        var cycledWeekIndex = 0
        let numWeeks = max(1, sp.currentProgram?.weeks.count ?? 1)
        if let origStart = sp.programStartDate.flatMap({ fmt.date(from: $0) }) {
            let daysSince = cal.dateComponents([.day], from: origStart, to: today).day ?? 0
            let originalWeekIndex = daysSince / 7
            cycledWeekIndex = originalWeekIndex % numWeeks
        }
        // newStart = monday_of_this_week - cycledWeekIndex * 7
        guard let newStart = cal.date(byAdding: .day, value: -cycledWeekIndex * 7, to: monday) else { return }
        let newStartStr = fmt.string(from: newStart)

        let updated = ServerProgram(
            currentProgram: sp.currentProgram,
            programStartDate: newStartStr,
            eventDate: sp.eventDate,
            sourceGoalIds: sp.sourceGoalIds,
            revision: sp.revision
        )
        appState.serverProgram = updated
        do {
            try await appState.saveProgramToServer()
            AppLogger.shared.log("garmin: program start reset to \(newStartStr) (cycled week \(cycledWeekIndex)/\(numWeeks))")
            if let api = appState.api {
                let status = (try? await api.fetchTodaySessionStatus()) ?? "error"
                AppLogger.shared.log("garmin: today-session after reset = \(status)")
            }
        } catch {
            AppLogger.shared.log("garmin: reset start date failed — \(error.localizedDescription)")
        }
    }

    private func claimGarmin() async {
        guard let api = appState.api else { return }
        isClaiming = true; claimError = nil; justPaired = false
        do {
            try await api.claimDevice(code: normalizedCode)
            justPaired = true
            garminCode = ""
            await loadGarminDevices()
        } catch {
            claimError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isClaiming = false
    }

    private func loadGarminDevices() async {
        guard let api = appState.api else { return }
        isLoadingDevices = true
        garminDevices = (try? await api.fetchDevices()) ?? []
        isLoadingDevices = false
    }

    // MARK: - Sync row helpers

    private func syncRow(icon: String, label: String, date: Date?, detail: String, logKeyword: String) -> some View {
        let filteredEntries = logger.entries.filter { $0.message.lowercased().contains(logKeyword.lowercased()) }
        return DisclosureGroup {
            if filteredEntries.isEmpty {
                Text("No log entries yet.")
                    .font(.caption).foregroundStyle(.secondary)
        } else {
                ForEach(filteredEntries.suffix(10)) { entry in logEntryRow(entry) }
            }
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body)
                    if let d = date {
                        Text(timeFmt.string(from: d)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var watchUploadRow: some View {
        let lastUpload = UserDefaults.standard.object(forKey: "lastWatchUploadDate") as? Date
        let count = UserDefaults.standard.integer(forKey: "watchUploadCount")
        let filteredEntries = logger.entries.filter {
            $0.message.contains("watch workout") || $0.message.contains("workout_complete")
        }
        return DisclosureGroup {
            if filteredEntries.isEmpty {
                Text("No uploads yet.").font(.caption).foregroundStyle(.secondary)
        } else {
                ForEach(filteredEntries.suffix(10)) { entry in logEntryRow(entry) }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Uploads")
                    if let d = lastUpload {
                        Text("\(count) total · last \(timeFmt.string(from: d))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No uploads yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var watchSessionRow: some View {
        let lastProgram = UserDefaults.standard.object(forKey: "lastProgramSyncDate") as? Date
        let filteredEntries = logger.entries.filter {
            $0.message.contains("WCSession") || $0.message.contains("watch")
        }
        return DisclosureGroup {
            if filteredEntries.isEmpty {
                Text("No Watch session activity yet.").font(.caption).foregroundStyle(.secondary)
        } else {
                ForEach(filteredEntries.suffix(10)) { entry in logEntryRow(entry) }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch").foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Sessions")
                    if let d = lastProgram {
                        Text("Sessions sent \(timeFmt.string(from: d))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Not yet sent").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Debug Log

    private var debugLogSection: some View {
        Section {
            DisclosureGroup("Full Debug Log (\(logger.entries.count) entries)", isExpanded: $showDebugLog) {
                if logger.entries.isEmpty {
                    Text("No entries.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(logger.entries) { entry in logEntryRow(entry) }
                    Button("Clear", role: .destructive) { logger.entries.removeAll() }
                        .font(.footnote)
                }
            }
        }
    }

    private func logEntryRow(_ entry: AppLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(monFmt.string(from: entry.date))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
    }
}
