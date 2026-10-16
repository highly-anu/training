import SwiftUI

/// The score's band, label and colour for Today's card and Analytics ▸
/// Progress alike. The server's status when it sent one; the thresholds it
/// uses otherwise (an older server).
enum ProgressionScore {
    static func band(_ review: ProgressionReview) -> (id: String, label: String)? {
        if let s = review.scoreStatus { return (s.id, s.label) }
        guard let score = review.overallScore else { return nil }
        if score >= 70 { return ("on_track", "On Track") }
        if score >= 45 { return ("mixed", "Mixed") }
        return ("off_track", "Off Track")
    }

    static func color(_ bandId: String?) -> Color {
        switch bandId {
        case "on_track":  return .green
        case "mixed":     return .yellow
        case "off_track": return .red
        default:          return .secondary
        }
    }

    /// "70 and up", "45–69", "below 45" — each band's range from the next one up.
    static func range(_ bands: [ScoreBand], at index: Int) -> String {
        let b = bands[index]
        if index == 0 { return "\(b.min) and up" }
        let upper = bands[index - 1].min - 1
        return b.min == 0 ? "below \(upper + 1)" : "\(b.min)–\(upper)"
    }
}
