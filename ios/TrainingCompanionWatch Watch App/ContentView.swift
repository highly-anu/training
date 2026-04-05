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
            VStack(spacing: 10) {
                Image(systemName: "iphone.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("iPhone unreachable")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Text("Open the iPhone app to sync.")
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
        case .noProgram, .programExpired:
            NoProgramView()
        case .ready:
            SessionListView()
        }
    }
}
