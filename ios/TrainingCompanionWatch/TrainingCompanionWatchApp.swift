import SwiftUI

@main
struct TrainingCompanionWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager()
    @StateObject private var sessionState = WorkoutSessionState()
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(connectivity)
                .environmentObject(sessionState)
                .environmentObject(workoutManager)
                .onAppear {
                    workoutManager.sessionState = sessionState
                    Task { await workoutManager.requestAuthorization() }
                    sessionState.restoreIfNeeded()
                }
        }
    }
}
