import SwiftUI
import WatchConnectivity

struct SyncStatusView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var sync: SyncManager
    @ObservedObject private var logger = AppLogger.shared

    @State private var showDebugLog = false

    private var watchPaired: Bool { WCSession.default.isPaired }
    private var watchReachable: Bool { WCSession.default.isReachable }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
    private let monFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                connectionSection
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
        }
    }

    // MARK: - Connection Card

    private var connectionSection: some View {
        Section {
            HStack {
                Label("iPhone ↔ API", systemImage: "network")
                Spacer()
                if sync.isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else if sync.lastError != nil {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                } else {
                    Text(sync.lastSyncDate != nil ? "Connected" : "Not synced")
                        .foregroundStyle(sync.lastSyncDate != nil ? .green : .secondary)
                        .font(.footnote)
                }
            }

            HStack {
                Label("Watch", systemImage: "applewatch")
                Spacer()
                if watchPaired {
                    Label(watchReachable ? "Reachable" : "Paired", systemImage: watchReachable ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundStyle(watchReachable ? .green : .secondary)
                        .font(.footnote)
                } else {
                    Text("Not paired")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            Button {
                Task { await sync.syncAll() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sync.isSyncing)
        } header: {
            Text("Connection")
        } footer: {
            if let err = sync.lastError {
                Text(err).foregroundStyle(.orange)
            } else if let last = sync.lastSyncDate {
                Text("Last full sync: \(timeFmt.string(from: last))")
            }
        }
    }

    // MARK: - Sync Categories

    private var syncCategoriesSection: some View {
        Section("Sync Details") {
            syncRow(
                icon: "calendar.badge.clock",
                label: "Program Sync",
                date: UserDefaults.standard.object(forKey: "lastProgramSyncDate") as? Date,
                detail: "Today's sessions sent to Watch",
                logKeyword: "program"
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

    private func syncRow(icon: String, label: String, date: Date?, detail: String, logKeyword: String) -> some View {
        let filteredEntries = logger.entries.filter { $0.message.lowercased().contains(logKeyword.lowercased()) }
        return DisclosureGroup {
            if filteredEntries.isEmpty {
                Text("No log entries yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEntries.suffix(10)) { entry in
                    logEntryRow(entry)
                }
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body)
                    if let d = date {
                        Text(timeFmt.string(from: d))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("No uploads yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEntries.suffix(10)) { entry in
                    logEntryRow(entry)
                }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Uploads")
                    if let d = lastUpload {
                        Text("\(count) total · last \(timeFmt.string(from: d))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No uploads yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("No Watch session activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEntries.suffix(10)) { entry in
                    logEntryRow(entry)
                }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Sessions")
                    if let d = lastProgram {
                        Text("Sessions sent \(timeFmt.string(from: d))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not yet sent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    Text("No entries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logger.entries) { entry in
                        logEntryRow(entry)
                    }
                    Button("Clear", role: .destructive) {
                        logger.entries.removeAll()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    // MARK: - Log Entry Row

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
