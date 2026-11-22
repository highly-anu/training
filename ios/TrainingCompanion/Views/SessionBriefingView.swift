import SwiftUI

/// Before a session: one row an exercise — its name, today's numbers and a
/// strip with one mark for every earlier time it was done — under it the one
/// suggestion (design-system §6.61). The dated lines, the chart, the standard
/// and the package's note are the row's sheet (`BriefingHistorySheet`). The
/// document is the server's (`SessionBriefing`); this only lays it out. Used
/// before the start in the workout player and in the detail of a session
/// that is not done — never after one, which is §6.54's.
struct SessionBriefingView: View {
    @ObservedObject var loader: SessionBriefingLoader
    var tint: Color = AppColor.accent
    /// Opens an earlier session to confirm it, from a row's sheet; without it
    /// the session is named there, not tappable.
    var onOpenSession: ((String) -> Void)? = nil
    let retry: () async -> Void

    @State private var shown: SessionBriefing.Row?

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
            if let briefing = loader.briefing {
                let rows = briefing.rows
                VStack(alignment: .leading, spacing: AppMetrics.gapMedium) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        RowView(row: row, tint: tint) { shown = row }
                    }
                }
                .appCard()
                .task(id: rows.map(\.id)) {
                    if let index = WorkoutPlayerDebug.briefingSheet, rows.indices.contains(index) { shown = rows[index] }
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
        .sheet(item: $shown) { row in
            BriefingHistorySheet(row: row, tint: tint,
                                 pending: Set(loader.briefing?.pending.map(\.sessionKey) ?? []),
                                 onOpenSession: onOpenSession.map { open in
                                     { key in shown = nil; open(key) }
                                 })
        }
    }

    // MARK: - One exercise

    private struct RowView: View {
        let row: SessionBriefing.Row
        let tint: Color
        let open: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                if let header = row.header {
                    AppAdaptiveStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                        Text(header).font(.caption.weight(.semibold)).textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let detail = row.headerDetail {
                            Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                Button(action: open) {
                    VStack(alignment: .leading, spacing: AppMetrics.gapTight) {
                        AppAdaptiveStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                            Text(row.name).font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.todayText).font(.headline).monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(alignment: .center, spacing: AppMetrics.gapSmall) {
                            BriefingStrip(row: row, tint: tint)
                            Text(row.caption).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .fixedSize()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        if let suggestion = row.suggestion {
                            Text(suggestion.text).font(.footnote)
                                .foregroundStyle(suggestion.kind == "confirm_pending" ? AppColor.warning : .secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityHint("Shows every earlier session")
            }
        }
    }
}

// MARK: - The strip

/// Every earlier time as one mark, oldest first, then today's as the plan in
/// the modality colour: height is the row's number, colour how it went.
/// Missed and unconfirmed are outlined — the shape differs with the colour —
/// and a deload is ghosted. A run longer than the strip shows its newest;
/// the caption beside it says how many there are.
struct BriefingStrip: View {
    let row: SessionBriefing.Row
    let tint: Color

    static let height: CGFloat = 24
    private static let gap: CGFloat = 2
    private static let todayGap: CGFloat = 6
    private static let markWidth: ClosedRange<CGFloat> = 3...10

    var body: some View {
        GeometryReader { geo in
            let room = geo.size.width - Self.markWidth.lowerBound - Self.todayGap
            let places = max(0, Int((room + Self.gap) / (Self.markWidth.lowerBound + Self.gap)))
            let marks = row.marks(fitting: places)
            let values = marks.compactMap(\.value) + (row.todayValue.map { [$0] } ?? [])
            let width = min(Self.markWidth.upperBound, max(Self.markWidth.lowerBound,
                (room - Self.gap * CGFloat(max(0, marks.count - 1))) / CGFloat(max(1, marks.count))))
            HStack(alignment: .bottom, spacing: Self.gap) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    MarkShape(outlined: mark.status == .missed || mark.status == .unconfirmed,
                              color: mark.status.color.opacity(mark.isDeload ? AppColor.Opacity.ghost : 1))
                        .frame(width: width, height: Self.height * SessionBriefing.markHeight(mark.value, in: values))
                }
                MarkShape(outlined: false, color: tint)
                    .frame(width: width, height: Self.height * SessionBriefing.markHeight(row.todayValue, in: values))
                    .padding(.leading, Self.todayGap - Self.gap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private struct MarkShape: View {
        let outlined: Bool
        let color: Color

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            if outlined { shape.strokeBorder(color, lineWidth: 1) } else { shape.fill(color) }
        }
    }
}

extension SessionBriefing.Status {
    /// Clean and made are done; missed, unconfirmed and merely logged each
    /// have their own (the symbol and the strip's outline are the twin).
    var color: Color {
        switch self {
        case .clean, .made: return AppColor.complete
        case .missed: return AppColor.destructive
        case .unconfirmed: return AppColor.warning
        case .logged: return .secondary
        }
    }
}
