import SwiftUI

/// The progression review — a section of Analytics (Progress), reached from
/// the Today card through `router.showAnalytics(.progress)`. No title of its
/// own: the Analytics container owns the navigation bar.
struct ProgressionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    /// A detail pushed from outside (a deep link); the cards push their own.
    @State private var route: AppRouter.AnalyticsDetail?
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
        .navigationDestination(item: $route) { detail($0) }
        .task { await appState.loadIfStale("programAnalytics") { await appState.loadProgramAnalytics() } }
        .task { await appState.loadIfStale("exerciseHistory") { await appState.loadExerciseHistory() } }
        .task { applyPendingDetail() }
        .onChange(of: router.pendingAnalyticsDetail) { applyPendingDetail() }
        .onChange(of: appState.programAnalytics?.progress.count) { applyPendingDetail() }
        .onChange(of: appState.exerciseHistory?.exercises.count) { applyPendingDetail() }
        // The review's arrival, not its score: a review with no score yet
        // (collecting) left a score link waiting for good.
        .onChange(of: appState.progressionReview != nil) { applyPendingDetail() }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadProgressionReview()
                await appState.loadProgramAnalytics()
                await appState.loadExerciseHistory()
            }
        }
    }

    // MARK: - Pushed from outside

    @ViewBuilder
    private func detail(_ detail: AppRouter.AnalyticsDetail) -> some View {
        switch detail {
        case .measure(let id):
            if let entry = appState.programAnalytics?.progress.first(where: { $0.id == id }) {
                MeasureDetailView(entry: entry)
            }
        case .exercise(let id):
            if let item = appState.exerciseHistory?.exercises.first(where: { $0.exerciseId == id }) {
                ExerciseHistoryView(item: item,
                                    finding: appState.progressionReview?.exerciseFindings.first { $0.exerciseId == id })
            }
        case .score:
            if let review = appState.progressionReview {
                ScoreDetailView(review: review, doc: appState.programAnalytics)
            }
        default:
            EmptyView()
        }
    }

    /// Push what a deep link asked for once its data has loaded; one that
    /// names nothing loaded is dropped then.
    private func applyPendingDetail() {
        guard let pending = router.pendingAnalyticsDetail, pending.section == .progress else { return }
        switch pending {
        case .measure(let id):
            guard let progress = appState.programAnalytics?.progress else { return }
            if progress.contains(where: { $0.id == id }) { route = pending }
        case .exercise(let id):
            guard let items = appState.exerciseHistory?.exercises else { return }
            if items.contains(where: { $0.exerciseId == id }) { route = pending }
        case .score:
            guard appState.progressionReview != nil else { return }
            route = pending
        default:
            break
        }
        router.clearPendingAnalyticsDetail()
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

    /// The score, its band and the completion beside it, and how many
    /// measures are stalled, behind, on track or ahead (§6.37). Why, each
    /// measure's points, the bands and what the score is for are
    /// `ScoreDetailView`'s; "How is this scored?" folded them in here.
    private func overviewCard(review: ProgressionReview) -> some View {
        let band = ProgressionScore.band(review)

        return AnalyticsDetailCard(header: "Score", hint: "Opens how the score is made") {
            if review.overallScore != nil, let band {
                TintCapsule(text: band.label, color: ProgressionScore.color(band.id))
            }
        } destination: {
            ScoreDetailView(review: review, doc: appState.programAnalytics)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ScoreHeadline(review: review)
                    Spacer()
                    // What the percentage covers is said to VoiceOver; on
                    // screen it repeated the percentage in words (§1.4).
                    Label("\(review.compliancePct)%", systemImage: "checkmark.circle")
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        .accessibilityLabel("\(review.compliancePct) percent of sessions done"
                                            + (review.scopeLabel.map { ", \($0)" } ?? ""))
                }
                if let counts = review.scoreStatus?.counts, !counts.isEmpty {
                    ScoreCounts(counts: counts)
                } else if let status = review.scoreStatus {
                    // An older server sends the sentence only.
                    Text(status.reason).font(.subheadline)
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
