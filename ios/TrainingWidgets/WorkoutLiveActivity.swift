import ActivityKit
import SwiftUI
import WidgetKit

/// The workout player's Live Activity (design-system §6.44): the step the
/// athlete is on and its countdown, on the Lock Screen and in the Dynamic
/// Island, while the phone is locked or in another app. The app starts and
/// updates it on every move (WorkoutLockScreen); the countdown runs on the
/// system's clock (`Text(timerInterval:)`), so nothing updates it per second.
/// A tap opens the app, where the player still is.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityLockScreen(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = WidgetModalityStyle.color(for: context.attributes.modalityId)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(WorkoutActivityText.phaseWord(context.state), systemImage: WorkoutActivityText.symbol(context.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityClock(state: context.state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        if let next = context.state.next {
                            Text(next).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: WorkoutActivityText.symbol(context.state))
                    .foregroundStyle(tint)
            } compactTrailing: {
                WorkoutActivityClock(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: WorkoutActivityText.symbol(context.state))
                    .foregroundStyle(tint)
            }
        }
    }
}

/// The Lock Screen's banner: the session, the step and what follows on the
/// left, the countdown — or the step count while the step waits — on the right.
private struct WorkoutActivityLockScreen: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        let tint = WidgetModalityStyle.color(for: context.attributes.modalityId)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(context.attributes.sessionName) · \(WorkoutActivityText.phaseWord(context.state))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let next = context.state.next {
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                WorkoutActivityClock(state: context.state)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                Text("Step \(context.state.step) of \(context.state.steps)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
    }
}

/// The phase's countdown on the system clock; a step that waits for the
/// athlete shows its count instead.
private struct WorkoutActivityClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let end = state.endsAt, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
        } else {
            Text("\(state.step)/\(state.steps)")
        }
    }
}

private enum WorkoutActivityText {
    static func phaseWord(_ s: WorkoutActivityAttributes.ContentState) -> String {
        switch s.phase {
        case .work: return "Work"
        case .rest: return "Rest"
        case .waiting: return "Your move"
        case .done: return "Done"
        }
    }

    static func symbol(_ s: WorkoutActivityAttributes.ContentState) -> String {
        switch s.phase {
        case .work: return "figure.strengthtraining.traditional"
        case .rest: return "pause.circle.fill"
        case .waiting: return "hand.tap.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}
