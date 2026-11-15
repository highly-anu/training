import SwiftUI
import Charts

/// Before a session: per item of it, today's numbers, the suggestion, the
/// earlier times the same session was done and where it stands in its cycle
/// (design-system §6.61). The document is the server's (`SessionBriefing`);
/// this only lays it out. Used before the start in the workout player and
/// in the detail of a session that is not done — never after one, which is
/// §6.54's.
struct SessionBriefingView: View {
    @ObservedObject var loader: SessionBriefingLoader
    var tint: Color = AppColor.accent
    /// Opens an earlier session to confirm it; without it the line is said, not tappable.
    var onOpenSession: ((String) -> Void)? = nil
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            if let briefing = loader.briefing {
                ForEach(briefing.pending) { pending in
                    PendingRow(pending: pending, open: onOpenSession)
                }
                ForEach(briefing.items) { item in
                    ItemCard(item: item, tint: tint)
                }
            } else if loader.isLoading {
                HStack(spacing: AppMetrics.gapSmall) {
                    ProgressView()
                    Text("Reading your earlier sessions").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(compact: true)
                .accessibilityElement(children: .combine)
            } else if let error = loader.error {
                AppErrorBanner(message: error, retry: retry)
            }
        }
    }

    // MARK: - A session to confirm first

    private struct PendingRow: View {
        let pending: SessionBriefing.Pending
        let open: ((String) -> Void)?

        var body: some View {
            let row = HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(AppColor.warning)
                Text(pending.text).font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if open != nil {
                    Text("Confirm").font(.footnote.weight(.semibold)).foregroundStyle(AppColor.accent)
                }
            }
            .appCard(compact: true, tint: AppColor.warning)
            if let open {
                Button { open(pending.sessionKey) } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens that session")
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - One item

    private struct ItemCard: View {
        let item: SessionBriefing.Item
        let tint: Color

        var body: some View {
            AppCard(header: item.title) {
                if let cycle = item.cycleText {
                    Text(cycle).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            } content: {
                today
                if let suggestion = item.suggestion {
                    Label(suggestion.text, systemImage: Self.symbol(suggestion.kind))
                        .font(.subheadline)
                        .foregroundStyle(suggestion.kind == "confirm_pending" ? AppColor.warning : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let step = item.cycleStep, let of = item.cycleOf, of > 1 {
                    ProgressView(value: Double(step), total: Double(of))
                        .tint(tint)
                        .accessibilityLabel(item.cycleText ?? "Step \(step) of \(of)")
                }
                if !item.series.isEmpty {
                    SeriesChart(item: item, tint: tint)
                }
                if !item.history.isEmpty {
                    VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                        ForEach(item.history.reversed()) { occurrence in
                            OccurrenceRow(occurrence: occurrence)
                        }
                    }
                } else if item.times == 0 {
                    Text("The first time on record.").font(.footnote).foregroundStyle(.secondary)
                }
                if let standard = item.standard, standard.best != nil || standard.target != nil {
                    Label([standard.best.map { "Best \($0)" }, standard.target].compactMap { $0 }.joined(separator: " · "),
                          systemImage: "trophy")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let notes = item.notes {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder private var today: some View {
            if item.lines.count > 1, Set(item.lines.map(\.text)).count > 1 {
                VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                    ForEach(item.lines, id: \.exerciseId) { line in
                        AppAdaptiveStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                            Text(line.name).font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(line.text).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            } else {
                Text(item.lines.first?.text ?? item.todayText)
                    .font(AppFont.metricCompact)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .accessibilityLabel("Today: \(item.lines.first?.text ?? item.todayText)")
            }
        }

        static func symbol(_ kind: String) -> String {
            switch kind {
            case "confirm_pending": return "questionmark.circle"
            case "next_step", "next_load": return "arrow.up.right"
            case "cycle_end": return "flag.checkered"
            case "beat_last", "standard_target": return "trophy"
            default: return "clock.arrow.circlepath"
            }
        }
    }

    private struct OccurrenceRow: View {
        let occurrence: SessionBriefing.Occurrence

        var body: some View {
            AppAdaptiveStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapTight) {
                    Image(systemName: occurrence.status.symbol)
                        .font(.caption)
                        .foregroundStyle(Self.color(occurrence.status))
                        .accessibilityHidden(true)
                    Text(occurrence.dayText.prefix(1).uppercased() + occurrence.dayText.dropFirst())
                        .font(.footnote)
                    if occurrence.isDeload {
                        Text("Deload").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                Text(occurrence.text)
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(occurrence.dayText): \(occurrence.text). \(occurrence.status.label).")
        }

        static func color(_ status: SessionBriefing.Status) -> Color {
            switch status {
            case .clean, .made: return AppColor.complete
            case .missed: return AppColor.destructive
            case .unconfirmed: return AppColor.warning
            case .logged: return .secondary
            }
        }
    }

    /// The item's metric across its occurrences, today's as the plan: bars,
    /// because each is one session, not a reading on a continuous scale.
    private struct SeriesChart: View {
        let item: SessionBriefing.Item
        let tint: Color

        var body: some View {
            let points = Array(item.series.enumerated())
            Chart {
                ForEach(points, id: \.offset) { index, point in
                    BarMark(x: .value("Session", String(index)), y: .value(item.metric?.label ?? "", point.value), width: .ratio(0.6))
                        .foregroundStyle(point.planned ? tint : AppColor.complete.opacity(point.isDeload ? AppColor.Opacity.ghost : 1))
                        .annotation(position: .top, spacing: 2) {
                            Text(point.value == point.value.rounded() ? String(Int(point.value)) : String(format: "%.1f", point.value))
                                .font(AppFont.micro).monospacedDigit()
                                .foregroundStyle(point.planned ? .primary : .secondary)
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 84)
            .appChartEntry()
            .appChartSummary(item.metric?.label ?? "Earlier sessions", SessionBriefing.seriesSummary(item))
        }
    }
}
