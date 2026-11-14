import SwiftUI

/// Words that run to several lines — a session's notes, how a workout went,
/// a method described (design-system §6.59). One field: it grows with what is
/// typed between `lines`, and scrolls beyond. Each screen used to write its
/// own `TextField(axis: .vertical)` with its own limits.
struct AppLongTextField: View {
    let prompt: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 3...8
    /// What VoiceOver calls the field when the prompt is an example, not a name.
    var label: String? = nil

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(lines)
            .accessibilityLabel(label ?? prompt)
    }
}
