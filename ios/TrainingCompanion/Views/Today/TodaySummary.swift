import SwiftUI

/// Today's three questions in one row (design-system §6.53): am I recovered,
/// am I doing the plan, is it working. Each tile is one number or mark in its
/// status colour and opens the Analytics section that explains it — the
/// detail (HRV, the weekly bars, the measure's sentence) lives there. Until
/// 1.39 each was a full card, and today's session shared the screen with
/// three dashboards.
struct TodaySummary: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Three across; one a row at the accessibility sizes.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AppMetrics.gapSmall))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppMetrics.gapSmall))
        layout {
            readiness
            adherence
            progress
        }
        // Three tiles of one height: the tallest's.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Readiness

    private var readiness: some View {
        let result = appState.readinessResult
        return TodayTile(title: "Readiness",
                         value: result.map { "\($0.score)" },
                         note: result?.statusLabel ?? "No data",
                         color: result?.statusColor,
                         hint: "Opens Analytics, Recovery") { router.showAnalytics(.recovery) }
    }

    // MARK: - Adherence

    /// The server's completion (`/analytics/program` scorecard), the number
    /// Analytics ▸ Progress and the web's Today card show, under the
    /// scorecard's own verdict: under 70 % of the committed work is off plan
    /// whatever the total says. "0 % · Off plan" is a verdict; it must not
    /// stand in for a document still loading, one from an older server
    /// without counts, or a week whose first session is still ahead.
    private var adherence: some View {
        let hint = "Opens Analytics, Progress"
        let open = { router.showAnalytics(.progress) }
        guard let sc = appState.programAnalytics?.scorecard, sc.plannedSessions != nil else {
            return TodayTile(title: "Adherence", value: nil,
                             note: appState.isLoadingProgramAnalytics ? "Measuring…" : "Not measured",
                             color: nil, hint: hint, action: open)
        }
        guard (sc.plannedSessions ?? 0) > 0 else {
            return TodayTile(title: "Adherence", value: nil, note: "Nothing due yet",
                             color: nil, hint: hint, action: open)
        }
        let week = sc.currentWeek.map { "\($0.completed)/\($0.due) this week" }
        return TodayTile(title: "Adherence",
                         value: "\(Int((sc.overallPct ?? 0).rounded()))%",
                         note: week ?? AnalyticsStatusStyle.label(sc.headline),
                         color: AnalyticsStatusStyle.color(sc.headline),
                         accessibilityNote: AnalyticsStatusStyle.label(sc.headline),
                         hint: hint, action: open)
    }

    // MARK: - Progress

    /// Is the training working, in the methodology's own currency: the
    /// status of the program's first methodology's headline measure, as the
    /// server words it. The sentence itself is on Analytics ▸ Progress.
    private var progress: some View {
        let hint = "Opens Analytics, Progress"
        let open = { router.showAnalytics(.progress) }
        guard let h = appState.programAnalytics?.methodologies.first?.headlineSummary else {
            return TodayTile(title: "Progress", value: nil,
                             note: appState.isLoadingProgramAnalytics ? "Measuring…" : "Not measured",
                             color: nil, hint: hint, action: open)
        }
        guard h.text != nil else {
            return TodayTile(title: "Progress", value: nil,
                             note: h.inScope == 0 ? "No sessions yet" : "Not logged yet",
                             color: nil, accessibilityNote: h.label, hint: hint, action: open)
        }
        let symbol = h.trendDirection == "improving" ? "arrow.up.right"
            : h.trendDirection == "declining" ? "arrow.down.right" : "arrow.right"
        return TodayTile(title: "Progress", symbol: symbol,
                         note: AnalyticsStatusStyle.label(h.status),
                         color: AnalyticsStatusStyle.color(h.status),
                         accessibilityNote: [h.label, h.text].compactMap { $0 }.joined(separator: ", "),
                         hint: hint, action: open)
    }
}

/// One tile of `TodaySummary`: a title, a number (or a symbol, or a dash
/// when there is none), a line under it.
struct TodayTile: View {
    let title: String
    var value: String? = nil
    var symbol: String? = nil
    let note: String
    /// The status colour; nil draws the tile quiet.
    let color: Color?
    /// Said after the note by VoiceOver: what the tile leaves to Analytics.
    var accessibilityNote: String? = nil
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                Text(title)
                    .font(AppFont.microStrong)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if let symbol {
                        // As text, so the tile keeps the number's line height.
                        Text(Image(systemName: symbol))
                    } else {
                        Text(value ?? "–")
                    }
                }
                .font(AppFont.metricCompact)
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
                .appNumeric(value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(note)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .appCard(compact: true, border: color)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, note, accessibilityNote].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(hint)
    }
}
