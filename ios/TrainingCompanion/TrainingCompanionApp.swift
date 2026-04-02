import SwiftUI
import BackgroundTasks

@main
struct TrainingCompanionApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.training.sync",
            using: nil
        ) { [self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            handleBackgroundSync(task, auth: auth)
        }
    }
}

private func handleBackgroundSync(_ task: BGAppRefreshTask, auth: AuthManager) {
    let sync = SyncManager()
    sync.configure(auth: auth)   // must be called before syncAll() or api is nil
    task.expirationHandler = { sync.cancel() }

    Task {
        await sync.syncAll()
        task.setTaskCompleted(success: true)
        scheduleNextSync()
    }
}

func scheduleNextSync() {
    let request = BGAppRefreshTaskRequest(identifier: "com.training.sync")
    // Earliest next fire: 6 hours from now (system may delay further)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}
