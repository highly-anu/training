import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager()
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if auth.isSignedIn {
            MainTabView()
                .environmentObject(router)
                .environmentObject(sync)
                .environmentObject(appState)
                .onAppear {
                    sync.configure(auth: auth, appState: appState)
                    appState.configure(auth: auth)
                    // Load everything except workouts immediately (Today tab needs program/profile/logs).
                    Task { await appState.loadAllExceptWorkouts() }
                    // HealthKit + Watch sync, then reload everything including workouts once.
                    Task {
                        do {
                            try await HealthKitManager.shared.requestPermissions()
                        } catch {
                            sync.lastError = "HealthKit: \(error.localizedDescription)"
                        }
                        await sync.syncAll()
                        await appState.loadAll()
                        presentRequestedWorkoutComplete()

                        // Near-real-time import: HealthKit wakes us when a new
                        // workout is written, instead of waiting for the ~6h
                        // background refresh. Observer queries must be
                        // re-registered every launch. Background delivery needs
                        // an entitlement, so a failure here is expected on
                        // builds without it and simply leaves the 6h path.
                        do {
                            try await HealthKitManager.shared.enableWorkoutBackgroundDelivery()
                        } catch {
                            AppLogger.shared.log(
                                "workout-import: background delivery unavailable — \(error.localizedDescription)")
                        }
                        HealthKitManager.shared.startWorkoutObserver {
                            await sync.importHealthWorkouts()
                            await appState.loadAll()
                        }
                    }
                    scheduleNextSync()
                    // A section asked for at launch (run_sim.sh ROUTE=…).
                    if let link = DeepLink.fromLaunchEnvironment() { router.open(link) }
                }
                .onChange(of: router.pendingWorkoutComplete) { _, _ in
                    if !appState.importedWorkouts.isEmpty { presentRequestedWorkoutComplete() }
                }
                // The "Workout complete" moment (§6.30): a workout stored since
                // the phone last looked, from any source.
                .sheet(item: Binding(
                    get: { appState.completedWorkout },
                    set: { if $0 == nil { appState.finishCompletedWorkout() } }
                )) { workout in
                    WorkoutCompleteSheet(workout: workout)
                        .id(workout.id)   // a fresh view, and fresh state, per workout
                        .environmentObject(appState)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Also a workout noticed while the app was in the
                    // background (a watch upload wakes it), whose sheet could
                    // not come up then; the refresh may not be due.
                    if phase == .active {
                        Task {
                            await appState.refreshIfStale()
                            appState.noticeCompletedWorkout()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchWorkoutStored)) { _ in
                    Task { await appState.refreshAfterWatchWorkout() }
                }
                .onOpenURL { url in
                    // .fit file import
                    if url.pathExtension.lowercased() == "fit" {
                        appState.pendingFITURL = url
                        return
                    }
                    // trainingcompanion://today | session?key=… (widgets) | program |
                    // analytics?section=… | profile — through the router (§6.9).
                    if let link = DeepLink.parse(url) { router.open(link) }
                }
                .sheet(isPresented: Binding(
                    get: { appState.pendingFITURL != nil },
                    set: { if !$0 { appState.pendingFITURL = nil } }
                )) {
                    FITImportSheet()
                        .environmentObject(appState)
                }
        } else {
            AuthView()
        }
    }

    private func presentRequestedWorkoutComplete() {
        guard let request = router.pendingWorkoutComplete else { return }
        router.clearPendingWorkoutComplete()
        if request == AppRouter.workoutCompleteDemo {
            appState.presentCompletedWorkoutDemo()
        } else {
            appState.presentCompletedWorkout(id: request.isEmpty ? nil : request)
        }
    }
}

// MARK: - Main Tab View

/// Five tabs: Today, Program, Log, Analytics, Profile. Connections, devices,
/// sync status and sign-out live under Profile ▸ Settings — the old "Sync"
/// tab was a debug screen holding the only sign-out and the integration
/// toggles. Log (2026-10-01) is the record: recorded workouts, the
/// suggestions inbox, and what was logged against planned sessions.
struct MainTabView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppRouter.Tab.dashboard)

            ProgramView()
                .tabItem { Label("Program", systemImage: "calendar") }
                .tag(AppRouter.Tab.program)

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
                .tag(AppRouter.Tab.analytics)

            LogView()
                .tabItem { Label("Log", systemImage: "list.clipboard") }
                .tag(AppRouter.Tab.log)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppRouter.Tab.profile)
        }
    }
}
