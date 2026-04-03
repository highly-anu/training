import SwiftUI

/// Container for the three-page active workout TabView.
/// S3-A (Current Exercise), S3-B (Session Progress), S3-C (Live Metrics).
struct ActiveWorkoutView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var showRestTimer = false
    @State private var isSessionComplete = false

    var body: some View {
        Group {
            if case .sessionComplete = sessionState.phase {
                SessionCompleteView()
            } else if case .resting = sessionState.phase {
                RestTimerView()
            } else {
                TabView {
                    CurrentExerciseView()
                        .tabItem { Label("Exercise", systemImage: "figure.strengthtraining.traditional") }
                    SessionProgressView()
                        .tabItem { Label("Progress", systemImage: "list.bullet") }
                    LiveMetricsView()
                        .tabItem { Label("Metrics", systemImage: "heart.fill") }
                }
                .tabViewStyle(.page)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
