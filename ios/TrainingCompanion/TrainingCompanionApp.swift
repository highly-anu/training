import SwiftUI
import BackgroundTasks
import TipKit

@main
struct TrainingCompanionApp: App {
    @StateObject private var auth = AuthManager()

    // Defaults to dark; AppAppearance.system hands control back to iOS.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.fallback.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .fallback
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    init() {
        // Two tips, each shown once (design-system §6.52).
        try? Tips.configure()
        #if DEBUG
        // Screenshots: TC_TIPS=show draws every tip, =hide none.
        switch ProcessInfo.processInfo.environment["TC_TIPS"] {
        case "show": Tips.showAllTipsForTesting()
        case "hide": Tips.hideAllTipsForTesting()
        default: break
        }
        #endif
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "haerdsoft.sync",
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
    let request = BGAppRefreshTaskRequest(identifier: "haerdsoft.sync")
    // Earliest next fire: 6 hours from now (system may delay further)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}
