import SwiftUI
import WatchConnectivity

/// Connections, devices, sync status, appearance and account — configuration,
/// not a destination, so it is pushed from Profile rather than being a tab.
/// This was the fifth tab ("Sync"), a diagnostics screen that also held the
/// only sign-out and the integration toggles. The start-date "repair" it ran
/// on every sync is gone: a program mutation does not belong on a diagnostics
/// screen (see information-architecture.md §3).
struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var appState: AppState
    @ObservedObject private var logger = AppLogger.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.fallback.rawValue

    @State private var showDebugLog = false
    @State private var diagnosis: WorkoutAccessDiagnosis?
    @State private var isDiagnosing = false
    @State private var garminDevices: [PairedDevice] = []
    @State private var latestWellness: WellnessReading?
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
        List {
            connectionsSection
            devicesSection
            pairGarminSection
            notificationsSection
            appearanceSection
            syncCategoriesSection
            apiTargetSection
            debugLogSection
            accountSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGarminDevices() }
    }

    // MARK: - Notifications

    /// Local reminders, scheduled on this phone from the stored program.
    /// Enabling asks the system once; a refusal turns the switch back off and
    /// the footer says where to change it.
    private var notificationsSection: some View {
        Section {
            Toggle("Session reminders", isOn: Binding(
                get: { notifications.isEnabled },
                set: { on in Task { await setReminders(on) } }
            ))
            if notifications.isEnabled {
                DatePicker("Reminder time", selection: Binding(
                    get: { reminderDate },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        notifications.reminderMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                        appState.rescheduleNotifications()
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Notifications")
        } footer: {
            if notifications.authorizationDenied {
                Text("Notifications are off for Training Companion. Turn them on in Settings → Notifications, then enable reminders again.")
            } else {
                Text("One reminder on each day with a planned session, at the time you pick. A moved session moves its reminder; a completed one cancels it.")
            }
        }
    }

    private var reminderDate: Date {
        let minutes = notifications.reminderMinutes
        return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                     second: 0, of: Date()) ?? Date()
    }

    private func setReminders(_ on: Bool) async {
        if on {
            let granted = await notifications.requestAuthorization()
            notifications.isEnabled = granted
            if granted { appState.rescheduleNotifications() }
        } else {
            notifications.isEnabled = false
            await notifications.cancelAll()
        }
    }

    // MARK: - Appearance

    /// Dark is the default (see AppAppearance); "System" hands control back to iOS.
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.label, systemImage: option.symbol)
                        .tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if auth.isLocalTarget {
                Text("Local API — no account. Switch back to production to sign in.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Sign Out", role: .destructive) { auth.signOut() }
            }
        }
    }

    // MARK: - API target (development)

    /// Where this build sends its requests. The local server has the local
    /// dev program and needs no account, so every screen can be checked
    /// against it in the simulator; the choice persists until switched back.
    private var apiTargetSection: some View {
        Section {
            #if DEBUG
            Toggle(isOn: Binding(
                get: { APITarget.isLocal },
                set: { useLocal in
                    APITarget.setOverride(useLocal ? APITarget.localBaseURL : nil)
                    auth.applyTargetChange()
                    Task { await appState.loadAll() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use local API")
                    Text(APITarget.localBaseURL).font(.caption2).foregroundStyle(.secondary)
                }
            }
            #endif
            LabeledContent("Current") {
                Text(APITarget.baseURL)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("API target")
        } footer: {
            Text(APITarget.isLocal
                 ? "Requests go to this Mac's Flask server as local-dev-user; nothing here reaches production."
                 : "Production. A developer can point a simulator at the local server from here or with LOCAL_API=1 ./ios/run_sim.sh.")
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
                // The web Devices card's "Last wellness reading" line.
                if let latestWellness {
                    Text("Last wellness reading: \(latestWellness.summary())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - Connections (automatic workout import)

    /// Server-backed, not @AppStorage: the Garmin webhook worker reads the
    /// same settings object, so a switch kept only on this phone would do
    /// nothing about activities Garmin is already pushing.
    private var integrations: IntegrationSettings {
        appState.profile.integrations ?? .default
    }

    private func setAutoImport(_ enabled: Bool) {
        var next = integrations
        next.autoImport = enabled
        appState.profile.integrations = next
        Task { await appState.saveProfile() }
    }

    private func setSource(_ key: String, _ enabled: Bool) {
        var next = integrations
        next.sources[key] = IntegrationSource(enabled: enabled)
        appState.profile.integrations = next
        Task { await appState.saveProfile() }
    }

    // MARK: - Apple Health access check

    /// Runs the unfiltered, unanchored scan and shows the answer in place.
    ///
    /// Rendered inline rather than only logged: the debug log holds 100 entries
    /// and lives behind a disclosure group, and this is the one answer the
    /// athlete opened this screen to get.
    private func runHealthAccessCheck() async {
        isDiagnosing = true
        AppHaptics.light()
        let result = await HealthKitManager.shared.diagnoseWorkoutAccess()
        diagnosis = result
        isDiagnosing = false

        AppLogger.shared.log("health-access: \(result.summaryLine)")
        for source in result.sources.prefix(6) {
            AppLogger.shared.log("health-access: \(source.bundle)×\(source.count) [\(source.disposition)]")
        }
        AppHaptics.success()
    }

    @ViewBuilder
    private func healthAccessResult(_ result: WorkoutAccessDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.summaryLine)
                .font(.caption)
                .foregroundStyle(result.total == 0 ? Color.orange : Color.secondary)

            ForEach(result.sources, id: \.bundle) { source in
                HStack(spacing: 6) {
                    Text(source.bundle)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(source.count)")
                        .font(.caption2).fontWeight(.semibold)
                    Text(source.disposition)
                        .font(.caption2)
                        .foregroundStyle(source.disposition.hasPrefix("skip") ? Color.secondary : Color.green)
                }
            }

            if result.total == 0 && result.needsAuthorizationPrompt {
                Text("Turn on Workouts for Training Companion in "
                     + "Settings → Health → Data Access & Devices.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var connectionsSection: some View {
        Section {
            Toggle("Automatic import", isOn: Binding(
                get: { integrations.autoImport },
                set: setAutoImport
            ))

            Toggle("Apple Health workouts", isOn: Binding(
                get: { integrations.sources["appleHealth"]?.enabled ?? true },
                set: { setSource("appleHealth", $0) }
            ))
            .disabled(!integrations.autoImport)

            Toggle("Garmin Connect", isOn: Binding(
                get: { integrations.sources["garmin"]?.enabled ?? true },
                set: { setSource("garmin", $0) }
            ))
            .disabled(!integrations.autoImport)

            // Deliberately not disabled by the auto-import toggle: the reason to
            // run this is that nothing is importing.
            Button {
                Task { await runHealthAccessCheck() }
            } label: {
                Label(isDiagnosing ? "Checking…" : "Check Apple Health access",
                      systemImage: "stethoscope")
            }
            .disabled(isDiagnosing)

            if let diagnosis {
                healthAccessResult(diagnosis)
            }

            Button {
                Task { await sync.reimportRecentWorkouts() }
            } label: {
                Label("Re-import recent workouts", systemImage: "arrow.clockwise")
            }
            .disabled(sync.isSyncing || !integrations.autoImport)
        } header: {
            Text("Connections")
        } footer: {
            Text("Activities Garmin Connect writes to Apple Health are imported "
                 + "automatically and matched to your planned sessions. "
                 + "Re-import forgets where the last sync stopped and looks again — "
                 + "duplicates are merged, not repeated.")
        }
    }

    private var syncCategoriesSection: some View {
        Section("Sync Details") {
            syncRow(
                icon: "figure.run",
                label: "Workout Import",
                date: sync.lastWorkoutSyncDate,
                detail: "Garmin activities via Apple Health",
                logKeyword: "workout-import"
            )

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
            }
        }

        await appState.loadProfile()
        await appState.loadPerformanceLogs()
        await appState.loadRecentBioLogs()
        await appState.loadReadiness()
        await appState.loadWorkouts()
        await loadGarminDevices()
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
        if garminDevices.isEmpty {
            latestWellness = nil
        } else {
            latestWellness = await api.fetchLatestWellness()
        }
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
