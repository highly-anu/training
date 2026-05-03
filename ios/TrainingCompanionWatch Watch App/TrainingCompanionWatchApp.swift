import SwiftUI

@main
struct TrainingCompanionWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager()
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
                .environmentObject(workoutManager)
                .environmentObject(workoutManager.sessionState)
                .task { await workoutManager.requestAuthorization() }
                .onOpenURL { url in
                    // Handle deep links from the watch widget.
                    // trainingcompanion://start?session=<sessionId>  → navigate to that session
                    // trainingcompanion://today                       → open session list (default)
                    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          components.host == "start",
                          let sessionId = components.queryItems?.first(where: { $0.name == "session" })?.value
                    else { return }
                    connectivity.pendingDeepLinkSessionId = sessionId
                }
        }
    }
}
