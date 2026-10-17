import SwiftUI

/// The progression review — a section of Analytics (Progress), reached from
/// the Today card through `router.showAnalytics(.progress)`. No title of its
/// own: the Analytics container owns the navigation bar.
struct ProgressionView: View {
    @EnvironmentObject var appState: AppState
    /// The symbol column of the recommendation rows, at the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 18

    var body: some View {
        Group {
            if let review = appState.progressionReview {
                reviewContent(review: review)
            } else {
                emptyState
            }
        }
        .task { await appState.loadIfStale("programAnalytics") { await appState.loadProgramAnalytics() } }
        .task { await appState.loadIfStale("exerciseHistory") { await appState.loadExerciseHistory() } }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadProgressionReview()
                await appState.loadProgramAnalytics()
                await appState.loadExerciseHistory()
            }
        }
    }

    // MARK: - Review content

    /// The other Analytics sections' layout: a column of `AnalyticsCard`s,
    /// 16 pt apart, inset as theirs are (§6.15).
    private func reviewContent(review: ProgressionReview) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                overviewCard(review: review)
                // Each methodology in its own currency, then where the athlete
                // stands — the web's Progress tab, from the same document.
                if let doc = appState.programAnalytics, doc.hasProgram {
                    ForEach(doc.methodologies) { method in
                        MethodologySectionView(method: method, doc: doc)
                    }
                    if let benchmarks = doc.benchmarks, !benchmarks.rows.isEmpty {
                        ProgramStandardsCard(benchmarks: benchmarks)
                    }
                }
                if let history = appState.exerciseHistory, !history.exercises.isEmpty {
                    ExerciseProgressSection(response: history, findings: review.exerciseFindings)
                }
                if !review.recommendations.isEmpty {
                    recommendationsSection(recommendations: review.recommendations)
                }
                if !review.adjustments.isEmpty {
                    adjustmentsSection(adjustments: review.adjustments)
                }
                if review.scoreBreakdown.map({ $0.basis != "not_started" }) ?? (review.overallScore != nil),
                   review.recommendations.isEmpty, review.adjustments.isEmpty {
                    AnalyticsCard(header: "Recommendations") {
                        Label("Nothing to change — keep going.", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Overview card

    private func overviewCard(review: ProgressionReview) -> some View {
        let score = review.overallScore
        let band = ProgressionScore.band(review)
        let color = ProgressionScore.color(band?.id)

        return AnalyticsCard(header: "Score") {
            if score != nil, let band {
                TintCapsule(text: band.label, color: color)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if let s = score {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(s)")
                                .font(.largeTitle.bold()).fontDesign(.rounded)
                                .foregroundStyle(color)
                            Text("/ 100")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Not enough data", systemImage: "hourglass")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // What the percentage covers is said to VoiceOver; on
                    // screen it repeated the percentage in words (§1.4).
                    Label("\(review.compliancePct)%", systemImage: "checkmark.circle")
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        .accessibilityLabel("\(review.compliancePct) percent of sessions done"
                                            + (review.scopeLabel.map { ", \($0)" } ?? ""))
                }
                if let status = review.scoreStatus {
                    Text(status.reason)
                        .font(.subheadline)
                }
                if review.scoreBreakdown != nil || review.scoreStatus != nil {
                    ScoreExplanation(breakdown: review.scoreBreakdown, status: review.scoreStatus,
                                     pending: review.pendingMeasures ?? [])
                }
            }
        }
    }

    // MARK: - Recommendations section

    private func recommendationsSection(recommendations: [String]) -> some View {
        AnalyticsCard(header: "Recommendations") {
            VStack(alignment: .leading, spacing: 8) {
                // The text is the identity; a review never repeats a line.
                ForEach(Array(NSOrderedSet(array: recommendations)) as! [String], id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                            .frame(width: iconWidth)
                        Text(rec)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    // MARK: - Adjustments section

    /// The review's adjustments were advice nothing could act on. The ones the
    /// server can apply edit the stored program from the current week on, under
    /// the revision check, and this copy is replaced with what was saved.
    private func adjustmentsSection(adjustments: [ProgressionAdjustment]) -> some View {
        AnalyticsCard(header: "Suggested adjustments") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(adjustments) { adj in
                    AdjustmentRow(adjustment: adj)
                    if adj.id != adjustments.last?.id { Divider() }
                }
            }
            if let conflict = appState.programSaveConflict {
                Label(conflict, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView("No progression data yet", systemImage: "chart.line.uptrend.xyaxis",
                               description: Text("Log sets to start tracking."))
    }

    // MARK: - Helpers

    /// "80kg", "45s", but "3 exercises" — the server's own rule for its
    /// change line (`progression_findings`), so the two lines agree.
    static func withUnit(_ value: String, _ unit: String) -> String {
        ["", "kg", "%", "s", "km", "m"].contains(unit) ? value + unit : "\(value) \(unit)"
    }
}

/// "How is this scored?": the sum behind the number, each measure it counts
/// or is still collecting, the measures waiting for data, and the three bands,
/// the current one marked. Folded by default — the reason line above it says
/// what matters. The measures had sections of their own until 2026-10-16,
/// beside the methodology cards that show them in full.
struct ScoreExplanation: View {
    let breakdown: ScoreBreakdown?
    let status: ScoreStatus?
    var pending: [PendingMeasure] = []
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                AppHaptics.selection()
                withAnimation(AppAnimation.springStandard) { open.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("How is this scored?")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .font(.footnote.weight(.medium))
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                if let b = breakdown {
                    Text(b.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // One part (sessions only) is the summary already; two are a sum.
                    ForEach(b.parts.count > 1 ? b.parts : []) { part in
                        HStack {
                            Text(part.label)
                            Spacer()
                            Text("\(part.value) × \(part.weight.formatted(.number.precision(.fractionLength(0...1)))) = \(part.points)")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                if let measures = breakdown?.measures, !measures.isEmpty {
                    Divider()
                    ForEach(measures) { m in
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.name).font(.subheadline)
                                + Text(m.detail.map { " · \($0)" } ?? "").font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Text(m.points.map { "\($0) pts" } ?? "collecting")
                                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if !pending.isEmpty {
                    Divider()
                    ForEach(pending) { m in
                        (Text(m.label).font(.subheadline)
                            + Text(" · \(m.reason)").font(.footnote).foregroundColor(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let s = status {
                    Divider()
                    ForEach(Array(s.bands.enumerated()), id: \.element.id) { i, band in
                        HStack {
                            Circle()
                                .fill(ProgressionScore.color(band.id))
                                .frame(width: 8, height: 8)
                            Text(band.label)
                                .fontWeight(band.id == s.id ? .semibold : .regular)
                            Spacer()
                            Text(ProgressionScore.range(s.bands, at: i))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}

/// One suggested adjustment and, where the server can apply it, the button
/// that does. Owns its own in-flight and outcome state so one tap never
/// blocks the others.
private struct AdjustmentRow: View {
    let adjustment: ProgressionAdjustment

    @EnvironmentObject var appState: AppState
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 18
    @State private var isApplying = false
    @State private var applied = false
    @State private var outcome: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: adjustment.isAppliable ? "slider.horizontal.3" : "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(adjustment.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if let target = adjustment.targetLabel {
                            Text("· \(target)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(adjustment.reason)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if adjustment.isAppliable {
                    Button {
                        Task { await apply() }
                    } label: {
                        if isApplying {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(applied ? "Applied" : "Apply")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(applied ? .green : .orange)
                    .disabled(isApplying || applied)
                } else {
                    TintCapsule(text: "advice", color: .secondary)
                }
            }
            if let outcome {
                Text(outcome)
                    .font(.caption)
                    .foregroundStyle(applied ? Color.green : Color.orange)
            }
        }
    }

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        do {
            let result = try await appState.applyAdjustment(adjustment)
            applied = true
            AppHaptics.success()
            outcome = result.summary { appState.allWeeks[safe: $0]?.weekNumber }
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
