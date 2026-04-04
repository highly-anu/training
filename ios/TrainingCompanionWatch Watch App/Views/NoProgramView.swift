import SwiftUI

struct NoProgramView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(connectivity.programState == .programExpired
                 ? "Program Complete"
                 : "No Program")
                .font(.headline)
            Text(connectivity.programState == .programExpired
                 ? "Generate a new one on the web app."
                 : "Set up a program on the web app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Request Sync") {
                connectivity.requestSync()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
    }
}
