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
        }
    }
}
