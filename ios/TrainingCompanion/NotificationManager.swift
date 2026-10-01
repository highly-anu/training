import Foundation
import Combine
import UserNotifications

// Local session reminders. Nothing here needs a server: the stored program
// says which days have sessions, and the phone schedules one notification per
// training day at the athlete's chosen time. Rescheduled whenever the program
// loads or changes, so a moved session moves its reminder with it.

/// Which days get a reminder and what each says — computed without the
/// notification center so it can be tested.
enum NotificationPlan {

    struct Reminder: Equatable {
        /// "yyyy-MM-dd" — one reminder per day, whatever the session count.
        let dateKey: String
        let fireDate: DateComponents
        let title: String
        let body: String

        var identifier: String { NotificationPlan.identifierPrefix + dateKey }
    }

    static let identifierPrefix = "session-reminder-"
    /// iOS keeps at most 64 pending local notifications per app.
    static let horizonDays = 14
    static let defaultReminderMinutes = 7 * 60

    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                   "Thursday", "Friday", "Saturday"]

    /// One reminder per upcoming training day within the horizon, at
    /// `reminderMinutes` past midnight. Days whose sessions are all logged as
    /// complete are skipped, and so is today once its time has passed.
    ///
    /// Weeks are addressed by array index from the start date — the same
    /// mapping `AppState.week(for:)` uses — never by `week_number`, which a
    /// regenerated block numbers from its absolute program week.
    static func reminders(program: GeneratedProgram?,
                          startDate: String?,
                          now: Date = Date(),
                          reminderMinutes: Int = defaultReminderMinutes,
                          completedKeys: Set<String> = [],
                          calendar: Calendar = .current) -> [Reminder] {
        guard let program, let startDate else { return [] }
        let df = DateFormatter()
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.dateFormat = "yyyy-MM-dd"
        guard let start = df.date(from: String(startDate.prefix(10))) else { return [] }

        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: start)
        var out: [Reminder] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let days = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            guard days >= 0 else { continue }
            let weekIdx = days / 7
            guard weekIdx < program.weeks.count else { break }
            let week = program.weeks[weekIdx]
            let dayName = dayNames[calendar.component(.weekday, from: day) - 1]

            let sessions = (week.schedule[dayName] ?? []).enumerated()
                .filter { !completedKeys.contains("\(week.weekNumber)-\(dayName)-\($0.offset)") }
                .map(\.element)
            guard !sessions.isEmpty else { continue }

            var fire = calendar.dateComponents([.year, .month, .day], from: day)
            fire.hour = reminderMinutes / 60
            fire.minute = reminderMinutes % 60
            guard let fireDate = calendar.date(from: fire), fireDate > now else { continue }

            let names = sessions.map { $0.archetype?.name ?? ModalityStyle.label(for: $0.modality) }
            let minutes = sessions.compactMap { $0.archetype?.durationEstimateMinutes }.reduce(0, +)
            var body = names.joined(separator: " + ")
            if minutes > 0 { body += " · \(minutes) min" }
            if sessions.contains(where: { $0.isDeload }) { body += " (deload)" }

            out.append(Reminder(dateKey: df.string(from: day), fireDate: fire,
                                title: "Training today", body: body))
        }
        return out
    }
}

/// Owns the settings and the notification center. `isEnabled` and the time
/// persist in UserDefaults; the schedule itself is derived from the program on
/// every change, never stored.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    static let enabledKey = "notifications.sessionReminders"
    static let minutesKey = "notifications.reminderMinutes"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    /// Minutes past midnight, local time.
    @Published var reminderMinutes: Int {
        didSet { UserDefaults.standard.set(reminderMinutes, forKey: Self.minutesKey) }
    }
    /// True once the system has refused permission; Settings explains where
    /// to turn it back on.
    @Published private(set) var authorizationDenied = false

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let stored = defaults.integer(forKey: Self.minutesKey)
        reminderMinutes = defaults.object(forKey: Self.minutesKey) == nil
            ? NotificationPlan.defaultReminderMinutes : stored
    }

    /// Asks the system once; later calls return the stored answer.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorizationDenied = !granted
            return granted
        } catch {
            authorizationDenied = true
            return false
        }
    }

    /// Replace every pending reminder with the plan for the current program.
    func reschedule(program: GeneratedProgram?, startDate: String?, completedKeys: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        await removePending(center)
        guard isEnabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            authorizationDenied = true
            return
        }
        authorizationDenied = false

        for reminder in NotificationPlan.reminders(program: program, startDate: startDate,
                                                   reminderMinutes: reminderMinutes,
                                                   completedKeys: completedKeys) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireDate, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier,
                                                        content: content, trigger: trigger))
        }
    }

    /// Turning reminders off forgets every pending one.
    func cancelAll() async {
        await removePending(UNUserNotificationCenter.current())
    }

    private func removePending(_ center: UNUserNotificationCenter) async {
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationPlan.identifierPrefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
    }
}
