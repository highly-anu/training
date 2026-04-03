import SwiftUI

struct NoProgramView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            if connectivity.programExpired {
                Text("Program Complete")
                    .font(.headline)
                Text("Generate a new program in the web app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No Program Synced")
                    .font(.headline)
                Text("Open Training Companion on your iPhone to sync today's workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    connectivity.requestSync()
                } label: {
                    Label("Request Sync", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
