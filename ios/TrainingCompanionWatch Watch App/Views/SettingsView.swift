import SwiftUI
import WatchConnectivity

struct SettingsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @AppStorage("hrAlertsEnabled") private var hrAlertsEnabled = true

    enum SyncState { case idle, syncing, done, unreachable }
    @State private var syncState: SyncState = .idle

    var body: some View {
        List {
            Section("HR Coaching") {
                Toggle("Zone Alerts", isOn: $hrAlertsEnabled)
            }
            Section("Sync") {
                Button {
                    requestSync()
                } label: {
                    switch syncState {
                    case .idle:        Label("Force Sync", systemImage: "arrow.clockwise")
                    case .syncing:     Label("Syncing…", systemImage: "arrow.clockwise")
                    case .done:        Label("Updated ✓", systemImage: "checkmark")
                    case .unreachable: Label("Phone not reachable", systemImage: "exclamationmark.triangle")
                    }
                }
                .foregroundStyle(syncState == .done ? .green : syncState == .unreachable ? .orange : .blue)
                .disabled(syncState == .syncing)
            }
            Section("Device") {
                LabeledContent("Max HR", value: "\(connectivity.maxHR) bpm")
            }
        }
        .navigationTitle("Settings")
    }

    private func requestSync() {
        guard WCSession.default.isReachable else {
            syncState = .unreachable
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncState = .idle }
            return
        }
        syncState = .syncing
        WCSession.default.sendMessage(["type": "request_sync"], replyHandler: { _ in
            DispatchQueue.main.async {
                syncState = .done
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncState = .idle }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                syncState = .unreachable
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncState = .idle }
            }
        })
    }
}
