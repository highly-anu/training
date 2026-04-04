import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @AppStorage("hrAlertsEnabled") private var hrAlertsEnabled = true
    @State private var syncRequested = false

    var body: some View {
        List {
            Section("HR Coaching") {
                Toggle("Zone Alerts", isOn: $hrAlertsEnabled)
            }
            Section("Sync") {
                Button(syncRequested ? "Requested ✓" : "Force Sync") {
                    connectivity.requestSync()
                    syncRequested = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        syncRequested = false
                    }
                }
                .foregroundStyle(syncRequested ? .green : .blue)
            }
            Section("Device") {
                LabeledContent("Max HR", value: "\(connectivity.maxHR) bpm")
            }
        }
        .navigationTitle("Settings")
    }
}
