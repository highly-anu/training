import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        switch connectivity.programState {
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Syncing…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            syncProblem(icon: "iphone.slash", title: "iPhone unreachable",
                        detail: "Open the iPhone app to sync.")
        case .syncFailed:
            syncProblem(icon: "exclamationmark.icloud", title: "Couldn't sync",
                        detail: "The iPhone couldn't reach the server.")
        case .noProgram, .programExpired:
            NoProgramView()
        case .ready:
            SessionListView()
        }
    }

    private func syncProblem(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                connectivity.requestSync()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .font(.caption)
        }
        .padding()
    }
}
