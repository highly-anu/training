import SwiftUI

/// No day to run: no program, one that has ended, or one that starts later.
struct NoProgramView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    private var title: String {
        switch connectivity.programState {
        case .programExpired: return "Program Complete"
        case .notStarted:     return "Starts \(startDay)"
        default:              return "No Program"
        }
    }

    private var detail: String {
        switch connectivity.programState {
        case .programExpired: return "Generate a new one on the web app."
        case .notStarted:     return "Your program begins then."
        default:              return "Set up a program on the web app."
        }
    }

    /// "Mon 20 Oct" from the server's `startsOn`.
    private var startDay: String {
        let parse = DateFormatter(); parse.dateFormat = "yyyy-MM-dd"; parse.locale = Locale(identifier: "en_US_POSIX")
        guard let iso = connectivity.startsOn, let date = parse.date(from: iso) else { return "soon" }
        let show = DateFormatter(); show.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return show.string(from: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: connectivity.programState == .notStarted
                  ? "calendar.badge.clock" : "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline)
            Text(detail)
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
