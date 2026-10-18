import SwiftUI

/// The Progress score in full (design-system §6.37), pushed from the Score
/// card: the number, its band and the server's sentence for why; each
/// measure behind the number with its points; the measures still collecting
/// data and what to log for them; how many of each method's measures can be
/// read; the bands; and what the score is for. "How is this scored?" folded
/// the same inside the card until 2026-10-18, and the methods' counts were a
/// card of their own above the measures.
struct ScoreDetailView: View {
    let review: ProgressionReview
    /// The program's analytics document, for each method's measurable count.
    var doc: ProgramAnalytics?

    private var counted: [ScoreMeasure] { (review.scoreBreakdown?.measures ?? []).filter { $0.points != nil } }
    private var collecting: [ScoreMeasure] { (review.scoreBreakdown?.measures ?? []).filter { $0.points == nil } }
    private var pending: [PendingMeasure] { review.pendingMeasures ?? [] }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    ScoreHeadline(review: review)
                    Spacer()
                    if review.overallScore != nil, let band = ProgressionScore.band(review) {
                        TintCapsule(text: band.label, color: ProgressionScore.color(band.id))
                    }
                }
                if let status = review.scoreStatus {
                    Text(status.reason)
                }
                LabeledContent {
                    Text("\(review.compliancePct)%").monospacedDigit()
                } label: {
                    Label(review.scopeLabel ?? "Sessions done", systemImage: "checkmark.circle")
                        .labelStyle(.inline)
                }
            }
            if !counted.isEmpty {
                Section {
                    ForEach(counted) { ScoreMeasureRow(measure: $0) }
                } header: {
                    Text("Measures")
                } footer: {
                    if let summary = review.scoreBreakdown?.summary { Text(summary) }
                }
            } else if let summary = review.scoreBreakdown?.summary {
                Section { Text(summary) }
            }
            if !collecting.isEmpty || !pending.isEmpty {
                Section("Collecting data") {
                    ForEach(collecting) { ScoreMeasureRow(measure: $0) }
                    ForEach(pending) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.label)
                            Text(m.reason).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let doc, !doc.methodologies.isEmpty {
                Section("Measurable") {
                    ForEach(doc.methodologies) { method in
                        let applicable = method.applicable ?? method.total
                        LabeledContent {
                            Text("\(method.measurable) of \(applicable)").monospacedDigit()
                        } label: {
                            Label(Self.name(method, in: doc), systemImage: "ruler")
                                .labelStyle(.inline)
                        }
                        .accessibilityLabel("\(Self.name(method, in: doc)): \(method.measurable) of \(applicable) measures have data")
                    }
                }
            }
            if let status = review.scoreStatus {
                Section("Bands") {
                    ForEach(Array(status.bands.enumerated()), id: \.element.id) { i, band in
                        HStack {
                            Circle().fill(ProgressionScore.color(band.id)).frame(width: 8, height: 8)
                            Text(band.label).fontWeight(band.id == status.id ? .semibold : .regular)
                            Spacer()
                            Text(ProgressionScore.range(status.bands, at: i))
                                .monospacedDigit().foregroundStyle(.secondary)
                            if band.id == status.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(band.id == status.id ? .isSelected : [])
                    }
                }
            }
            AboutSection(about: AboutText(measures: review.purpose))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func name(_ method: ProgramAnalytics.Methodology, in doc: ProgramAnalytics) -> String {
        doc.frame?.philosophies.first { $0.id == method.philosophy }?.name ?? method.philosophy
    }
}

/// The score out of 100 in its band's colour, or "Not enough data" before
/// any measure has a trend — the Score card's and the detail's first line.
struct ScoreHeadline: View {
    let review: ProgressionReview

    var body: some View {
        let band = ProgressionScore.band(review)
        let color = ProgressionScore.color(band?.id)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let s = review.overallScore {
                Text("\(s)")
                    .font(.largeTitle.bold()).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(color)
                Text("/ 100").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("Not enough data", systemImage: "hourglass")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How many measures are stalled, behind, on track or ahead, each as its
/// symbol and number — the server's `score_status.counts`, worst first.
struct ScoreCounts: View {
    let counts: [ScoreCount]

    var body: some View {
        LegendFlow(spacing: 14, lineSpacing: 6) {
            ForEach(counts) { c in
                Label {
                    Text("\(c.count) \(c.label)").monospacedDigit()
                } icon: {
                    Image(systemName: AnalyticsStatusStyle.symbol(c.status))
                        .foregroundStyle(AnalyticsStatusStyle.color(c.status))
                }
                .labelStyle(.inline)
                .font(.subheadline)
            }
        }
    }
}

/// One measure behind the score: its name and the server's change line, its
/// status as a symbol and its points — or how far it is from a trend.
private struct ScoreMeasureRow: View {
    let measure: ScoreMeasure
    /// The symbol column, so the names line up whatever the symbol's width.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let status = measure.status, measure.points != nil {
                Image(systemName: AnalyticsStatusStyle.symbol(status))
                    .foregroundStyle(AnalyticsStatusStyle.color(status))
                    .frame(width: iconWidth)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(measure.name)
                if let detail = measure.detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let points = measure.points {
                Text("\(points) pts").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([measure.name, measure.status.map(AnalyticsStatusStyle.label),
                             measure.points.map { "\($0) points" }, measure.detail]
                            .compactMap { $0 }.joined(separator: ", "))
    }
}
