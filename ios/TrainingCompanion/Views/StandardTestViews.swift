import SwiftUI

/// Marks a session that tests the phase's standards (design-system §6.32).
struct TestBadge: View {
    var body: some View {
        Label("Test", systemImage: "trophy.fill")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("A test of this phase's standards")
    }
}

/// One standard a test measures: where the athlete stands and the number to
/// beat for the next level, in the server's words. Taps open its sheet.
struct StandardTargetRow: View {
    let standardId: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let b = appState.benchmarks.first { $0.id == standardId }
        let r = appState.standardResults?.standards[standardId]
        Button { router.openStandard(standardId) } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy").font(.caption2).foregroundStyle(Color.accentColor)
                Text(b?.name ?? standardId).font(.caption).lineLimit(1)
                Spacer(minLength: 4)
                if let r {
                    Text(r.best.valueText).font(.caption).fontWeight(.semibold).monospacedDigit()
                    StandardLevelBadge(level: r.best.level, domain: b?.domain)
                } else {
                    Text("first result").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(target(r, b) ?? "")
        if let t = target(r, b) {
            Text(t).font(.caption2).foregroundStyle(.secondary).padding(.leading, 18)
        }
    }

    private func target(_ r: StandardResult?, _ b: AppBenchmark?) -> String? {
        if let r, let next = r.current.next, let text = r.current.nextText { return "\(text) for \(next)" }
        if r == nil, let entry = b?.thresholdTexts["entry"] { return "\(entry) for entry" }
        return nil
    }
}
