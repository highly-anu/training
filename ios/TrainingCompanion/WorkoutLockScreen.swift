import ActivityKit
import Foundation
import UserNotifications

/// What the workout player shows while the phone is locked or in another app
/// (design-system §6.44): a notification at each moment the clock moves the
/// workout on — a rest over, an interval's work and rest, a timed step's end
/// — from the engine's forecast, and the Live Activity, the step and its
/// countdown on the Lock Screen and in the Dynamic Island. The engine itself
/// never runs in the background; it catches up when the app comes back.
@MainActor
final class WorkoutLockScreen: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkoutLockScreen()

    /// The player's notifications, apart from the session reminders
    /// (NotificationManager's `session-reminder-`), which keep theirs.
    static let prefix = "workout-cue-"
    /// iOS keeps 64 pending notifications in all; the player takes at most this many.
    static let maxCues = 40

    private var activity: Activity<WorkoutActivityAttributes>?

    /// Asked once, when the first workout starts: the cues need alerts and sound.
    func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Notifications

    /// The forecast's moments as notifications, each with what is next.
    func scheduleCues(_ events: [WorkoutSessionState.ForecastEvent], session: String) {
        cancelCues()
        let center = UNUserNotificationCenter.current()
        for (i, event) in Self.cues(events, session: session).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let seconds = max(1, event.at.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(Self.prefix)\(i)", content: content, trigger: trigger))
        }
    }

    struct Cue: Equatable {
        let at: Date
        let title: String
        let body: String
    }

    /// The notifications for a forecast: the moment's words as the title,
    /// the session as the body, at most `maxCues`. Pure, for the tests.
    nonisolated static func cues(_ events: [WorkoutSessionState.ForecastEvent], session: String) -> [Cue] {
        events.prefix(maxCues).map { e in
            let parts = e.text.components(separatedBy: " · ")
            let title = parts.first ?? e.text
            let detail = parts.dropFirst().joined(separator: " · ")
            return Cue(at: e.at, title: title, body: detail.isEmpty ? session : "\(detail) — \(session)")
        }
    }

    func cancelCues() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.removeDeliveredNotifications(withIdentifiers: (0..<Self.maxCues).map { "\(Self.prefix)\($0)" })
    }

    /// In the app the player says it itself: a cue is not shown over it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(Self.prefix) ? [] : [.banner, .sound, .list]
    }

    // MARK: - Live Activity

    /// The Live Activity as the player stands: started with the workout,
    /// updated on each move.
    func update(_ player: WorkoutPlayerModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let session = player.session,
              player.startedAt != nil else { return }
        let state = Self.state(player.engine, session: session)
        let content = ActivityContent(state: state, staleDate: state.endsAt?.addingTimeInterval(60))
        if let activity {
            Task { await activity.update(content) }
        } else {
            let attributes = WorkoutActivityAttributes(sessionName: player.target.title, modalityId: session.modalityId)
            activity = try? Activity.request(attributes: attributes, content: content)
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        cancelCues()
    }

    /// The activity's state from the engine. Pure, for the tests.
    static func state(_ engine: WorkoutSessionState, session: WatchSession) -> WorkoutActivityAttributes.ContentState {
        let forecast = engine.forecast(limit: 2)
        let phase: WorkoutActivityAttributes.ContentState.Phase
        switch engine.phase {
        case .resting: phase = .rest
        case let .emomInterval(_, _, isWork, _): phase = isWork ? .work : .rest
        case .sessionComplete: phase = .done
        default: phase = engine.clockDrivesNext ? .work : .waiting
        }
        let index = engine.phase.exerciseIndex ?? 0
        return .init(title: engine.cueText, phase: phase, endsAt: forecast.first?.at,
                     next: forecast.first?.text, step: min(index + 1, session.exercises.count),
                     steps: session.exercises.count)
    }
}
