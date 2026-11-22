import SwiftUI
import Charts

/// Everything behind one row of the briefing (design-system §6.61): today's
/// numbers, the cycle, the run as a chart, the standard, and every earlier
/// time with its day and what was done, newest first. A session still to
/// confirm opens from its line.
struct BriefingHistorySheet: View {
    let row: SessionBriefing.Row
    var tint: Color = AppColor.accent
    /// The sessions the briefing asks to confirm first.
    var pending: Set<String> = []
    var onOpenSession: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    Text(row.todayText)
                        .font(AppFont.metricCompact)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    if let cycle = row.item.cycleText {
                        VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                            Text(cycle).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            if let step = row.item.cycleStep, let of = row.item.cycleOf, of > 1 {
                                ProgressView(value: Double(step), total: Double(of)).tint(tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let suggestion = row.item.suggestion {
                        Label(suggestion.text, systemImage: Self.symbol(suggestion.kind))
                            .font(.subheadline)
                            .foregroundStyle(suggestion.kind == "confirm_pending" ? AppColor.warning : .primary)
                    }
                    if let standard = row.item.standard, standard.best != nil || standard.target != nil {
                        Label([standard.best.map { "Best \($0)" }, standard.target].compactMap { $0 }.joined(separator: " · "),
                              systemImage: "trophy")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !row.series.isEmpty {
                    Section(row.metric?.label ?? "Earlier sessions") {
                        SeriesChart(row: row, tint: tint)
                    }
                }
                Section {
                    if row.run.isEmpty {
                        Text("The first time on record.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(row.run.reversed().enumerated()), id: \.offset) { _, occurrence in
                        if let open = onOpenSession, let key = occurrence.sessionKey, pending.contains(key) {
                            Button { open(key) } label: { OccurrenceRow(occurrence: occurrence, action: "Confirm") }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens that session")
                        } else {
                            OccurrenceRow(occurrence: occurrence)
                        }
                    }
                } header: {
                    Text(row.run.isEmpty ? "Earlier sessions" : "Earlier sessions · \(row.run.count)")
                } footer: {
                    if let notes = row.item.notes { Text(notes) }
                }
            }
            .navigationTitle(row.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .appSheet(.flexible)
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

    // MARK: - One earlier time

    private struct OccurrenceRow: View {
        let occurrence: SessionBriefing.Occurrence
        var action: String? = nil

        var body: some View {
            AppAdaptiveStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapTight) {
                    Image(systemName: occurrence.status.symbol)
                        .font(.caption)
                        .foregroundStyle(occurrence.status.color)
                        .accessibilityHidden(true)
                    Text(occurrence.dayText.prefix(1).uppercased() + occurrence.dayText.dropFirst())
                        .font(.subheadline)
                    if occurrence.isDeload {
                        Text("Deload").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                Text(occurrence.text)
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let action {
                    Text(action).font(.footnote.weight(.semibold)).foregroundStyle(AppColor.accent)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(occurrence.dayText): \(occurrence.text). \(occurrence.status.label).")
        }
    }

    /// The row's number across every earlier time, today's as the plan: bars,
    /// because each is one session, not a reading on a continuous scale. A
    /// long run scrolls, resting on its newest.
    private struct SeriesChart: View {
        let row: SessionBriefing.Row
        let tint: Color

        private static let barRoom: CGFloat = 30

        var body: some View {
            let points = Array(row.series.enumerated())
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    Chart {
                        ForEach(points, id: \.offset) { index, point in
                            BarMark(x: .value("Session", String(index)), y: .value(row.metric?.label ?? "", point.value),
                                    width: .ratio(0.6))
                                .foregroundStyle(point.planned ? tint : AppColor.complete.opacity(point.isDeload ? AppColor.Opacity.ghost : 1))
                                .annotation(position: .top, spacing: 2) {
                                    Text(SessionBriefing.Row.number(point.value))
                                        .font(AppFont.micro).monospacedDigit()
                                        .foregroundStyle(point.planned ? .primary : .secondary)
                                }
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(width: max(geo.size.width, CGFloat(points.count) * Self.barRoom))
                }
                .defaultScrollAnchor(.trailing)
            }
            .frame(height: 96)
            .appChartEntry()
            .appChartSummary(row.metric?.label ?? "Earlier sessions", row.seriesSummary)
        }
    }
}
