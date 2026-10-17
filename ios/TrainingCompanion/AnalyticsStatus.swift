import SwiftUI

/// The engine's statuses folded onto the app's three colours, and put into
/// words — the same mapping as the web's `components/analytics/status.ts`,
/// so a "behind" reads the same amber on both. A status the engine adds later
/// degrades to neutral, not to a missing style.
enum AnalyticsStatusStyle {

    static func color(_ status: String) -> Color {
        switch status {
        case "ahead", "on_track", "met", "on_target", "stable_by_design", "on_plan", "loading_as_expected", "fresh":
            return .green
        case "behind", "partial", "off_target", "no_target", "very_fatigued", "still_fatigued_in_recovery":
            return .yellow
        case "stalled", "below", "off_plan", "error":
            return .red
        default:
            return .secondary
        }
    }

    static func label(_ status: String) -> String {
        switch status {
        case "ahead": return "Ahead"
        case "on_track": return "On track"
        case "behind": return "Behind"
        case "stalled": return "Stalled"
        case "stable_by_design": return "Holding"
        case "insufficient_data": return "Not enough data"
        case "on_target": return "On target"
        case "off_target": return "Off target"
        case "no_target": return "No target"
        case "met": return "Met"
        case "partial": return "Partly met"
        case "below": return "Below"
        case "off_plan": return "Off plan"
        case "on_plan": return "On plan"
        case "not_started": return "Not started"
        case "error": return "Error"
        case "no_load_data": return "No load data"
        case "loading_as_expected": return "Loading as expected"
        case "very_fatigued": return "Very fatigued"
        case "fresh": return "Fresh"
        case "still_fatigued_in_recovery": return "Still fatigued in a recovery week"
        default: return status.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Why a primitive could not measure — the engine's reason codes, in words.
    static func coverageReason(_ code: String?) -> String {
        switch code {
        case "no_sets_logged": return "No sets logged yet. Log reps and kg on a completed session."
        case "no_kg_logged": return "Reps are logged but not the kg. Add the weight to each set."
        case "rounds_not_logged": return "Rounds are not being logged. Enter rounds on an AMRAP or EMOM session."
        case "duration_not_logged": return "Minutes are not being captured. Match a workout or log the session duration."
        case "distance_not_logged": return "Distance is not being captured. Match a workout or log kilometres."
        case "hold_not_logged": return "Hold times are not being logged. The watch records them."
        case "timed_sets_not_logged": return "Reps per minute needs reps and seconds on the same set."
        case "no_rpe_target": return "This program prescribes no RPE targets, so load-at-RPE cannot be measured."
        case "rpe_not_logged": return "RPE is not being logged with sets."
        case "no_sets_near_target": return "No logged sets were within ±1 of the target RPE."
        case "no_heart_rate": return "No heart-rate data on the matched workouts."
        case "no_gps_hr": return "Needs a matched run or ride with GPS and heart-rate samples."
        case "no_exercises_in_scope": return "No exercises in this scope have been completed yet."
        case "clean_not_logged": return "A movement is earned by clean sessions. Tick \"Clean\" on a skill when every rep was owned."
        case "no_pr_logged": return "No result logged for these standards yet. Log one under Profile ▸ Standards."
        default: return "Nothing logged for this metric yet."
        }
    }
}

/// A small coloured capsule naming a status.
struct AnalyticsStatusBadge: View {
    let status: String

    var body: some View {
        TintCapsule(text: AnalyticsStatusStyle.label(status), color: AnalyticsStatusStyle.color(status))
    }
}
