import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @AppStorage("hrAlertsEnabled") private var hrAlertsEnabled = true

    var body: some View {
        List {
            Section("Feedback") {
                Toggle("HR Zone Alerts", isOn: $hrAlertsEnabled)
                    .font(.caption)
            }

            Section("Sync") {
                if let date = connectivity.lastSyncDate {
                    LabeledContent("Last sync", value: date)
                        .font(.caption)
                }
                Button {
                    connectivity.requestSync()
                } label: {
                    Label("Force Sync", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
