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
        case .noProgram, .programExpired:
            NoProgramView()
        case .ready:
            SessionListView()
        }
    }
}
