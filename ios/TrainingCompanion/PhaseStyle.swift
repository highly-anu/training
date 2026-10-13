import SwiftUI

/// Colour for a phase KIND — the shared vocabulary in
/// data/commons/phase_kinds.yaml, the same keys and hex values as the web's
/// `lib/phaseColors.ts` (design-system §3.2).
///
/// A phase's *name* is its methodology's own (`ProgramWeek.phaseLabel`,
/// `PhilosophyPhase.name`); only its colour comes from the kind. Program ▸
/// Current used to colour base/build/peak/taper with system colours and grey
/// everything else, so Uphill's transition and specific phases, and every
/// maintenance block, read as one undifferentiated grey.
enum PhaseStyle {
    static func color(for kind: String) -> Color {
        switch kind {
        case "base":        return Color(red: 0.055, green: 0.647, blue: 0.914) // #0ea5e9
        case "build":       return Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
        case "peak":        return Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444
        case "taper":       return Color(red: 0.133, green: 0.773, blue: 0.369) // #22c55e
        case "transition":  return Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6
        case "specific":    return Color(red: 0.976, green: 0.451, blue: 0.086) // #f97316
        case "maintenance": return Color(red: 0.631, green: 0.631, blue: 0.667) // #a1a1aa
        case "rehab":       return Color(red: 0.518, green: 0.800, blue: 0.086) // #84cc16
        case "post_op":     return Color(red: 0.659, green: 0.333, blue: 0.969) // #a855f7
        case "deload", "recovery", "active":
                            return Color(red: 0.580, green: 0.639, blue: 0.722) // #94a3b8
        default:            return .secondary
        }
    }
}
