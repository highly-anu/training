import SwiftUI

/// A result a logged session suggests, with the athlete's three answers:
/// Save, correct it and save, or "Not a test" (design-system §6.32; the web's
/// `SuggestionRow`). The same row on Profile ▸ Standards' "To confirm", on
/// Today and under the test slot that produced it. Every word and number is
/// the server's — the value, its level, what it would follow — and a
/// suggestion is never a result until it is saved.
struct StandardSuggestionRow: View {
    let suggestion: StandardSuggestion
    /// Under the slot it came from: no session line.
    var compact = false
    var showName = true

    @EnvironmentObject var appState: AppState
    @State private var correcting = false
    @State private var text = ""
    @State private var busy = false
    @State private var failure: String? = nil

    private var s: StandardSuggestion { suggestion }

    private var standing: String {
        if let replaced = s.replacesText { return "Corrects \(replaced)" }
        if s.isBest, s.current != nil { return "New best" }
        return s.current.map { "Was \($0.valueText)" } ?? "First result"
    }

    private var from: String {
        let what = s.sessionName ?? (s.origin == "derived_single" ? "A single in training" : "A logged session")
        let day = StandardLevel.date(s.loggedOn).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        return [what, day].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if showName { Text(s.name).font(.subheadline).fontWeight(.medium).lineLimit(1) }
                if correcting {
                    TextField("Result", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .frame(width: 90)
                        .onSubmit { Task { await decide("confirm") } }
                } else {
                    Text(s.valueText).font(.subheadline).fontWeight(.semibold).monospacedDigit()
                }
                if let input = s.inputText, !correcting {
                    Text("(\(input))").font(.caption).foregroundStyle(.secondary)
                }
                StandardLevelBadge(level: s.level, domain: s.domain)
            }
            Text(compact ? standing : "\(standing) · \(from)")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { Task { await decide("confirm") } } label: {
                    Label("Save result", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                if !correcting {
                    Button("Correct") { text = s.valueText; correcting = true }
                        .buttonStyle(.bordered)
                }
                Button("Not a test") { Task { await decide("dismiss") } }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .disabled(busy)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, compact ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested result: \(s.name), \(s.valueText)")
    }

    private func decide(_ action: String) async {
        busy = true
        defer { busy = false }
        let typed = action == "confirm" && correcting && text.trimmingCharacters(in: .whitespaces) != s.valueText
            ? text.trimmingCharacters(in: .whitespaces) : nil
        if let why = await appState.decideSuggestion(id: s.id, action: action, text: typed) {
            failure = why
            AppHaptics.error()
        } else {
            failure = nil
            correcting = false
            AppHaptics.success()
        }
    }
}

/// Under a test's scored slot, or a test standard on the session screen: the
/// suggestion that session's logged outcome produced, if one is waiting.
struct SessionSuggestion: View {
    let standardId: String
    let sessionKey: String
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let s = appState.standardSuggestions.first(where: {
            $0.benchmarkId == standardId && $0.isFromTest(sessionKey: sessionKey)
        }) {
            StandardSuggestionRow(suggestion: s, compact: true, showName: false)
        }
    }
}
