import SwiftUI

/// The progression review — a section of Analytics (Progress), reached from
/// the Today card through `router.showAnalytics(.progress)`. No title of its
/// own: the Analytics container owns the navigation bar.
struct ProgressionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let review = appState.progressionReview {
                reviewContent(review: review)
            } else {
                emptyState
            }
        }
        .refreshable {
            await AppRefresh.perform { await appState.loadProgressionReview() }
        }
    }

    // MARK: - Review content

    private func reviewContent(review: ProgressionReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let purpose = review.purpose {
                    Text(purpose)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                overviewCard(review: review)
                if !review.exerciseFindings.isEmpty {
                    findingsSection(findings: review.exerciseFindings)
                }
                if let pending = review.pendingMeasures, !pending.isEmpty {
                    pendingSection(pending)
                }
                if !review.recommendations.isEmpty {
                    recommendationsSection(recommendations: review.recommendations)
                }
                if !review.adjustments.isEmpty {
                    adjustmentsSection(adjustments: review.adjustments)
                }
                if review.overallScore != nil, review.recommendations.isEmpty, review.adjustments.isEmpty {
                    Label("Nothing to change — keep going.", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Spacer(minLength: 32)
            }
            .padding()
        }
    }

    // MARK: - Overview card

    private func overviewCard(review: ProgressionReview) -> some View {
        let score = review.overallScore
        let band = ProgressionScore.band(review)
        let color = ProgressionScore.color(band?.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let s = score {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(s)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                            Text("/ 100")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        if let band {
                            Text(band.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(color)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(color.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    } else {
                        Text("Not enough data yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(review.compliancePct)%")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Sessions done")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let scope = review.scopeLabel {
                        Text(scope)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if let status = review.scoreStatus {
                Text(status.reason)
                    .font(.subheadline)
            }
            if review.scoreBreakdown != nil || review.scoreStatus != nil {
                ScoreExplanation(breakdown: review.scoreBreakdown, status: review.scoreStatus)
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Waiting for data

    /// Measures of the methodology with nothing logged yet, and what starts them.
    private func pendingSection(_ pending: [PendingMeasure]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Waiting for data")
            VStack(spacing: 8) {
                ForEach(pending) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.label).font(.subheadline).fontWeight(.medium)
                        if let d = m.description {
                            Text(d).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(m.reason).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Findings section

    private func findingsSection(findings: [ExerciseFinding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Exercise Findings")
            VStack(spacing: 8) {
                ForEach(findings) { finding in
                    findingRow(finding: finding)
                }
            }
        }
    }

    private func findingRow(finding: ExerciseFinding) -> some View {
        let color = statusColor(finding.status)
        return HStack(alignment: .top, spacing: 10) {
            Text(statusIcon(finding.status))
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    if let actual = finding.actualValue {
                        Text(Self.withUnit(formatValue(actual), finding.unit))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    if let expected = finding.expectedValue {
                        Text("(target \(Self.withUnit(formatValue(expected), finding.unit)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(finding.changeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let d = finding.description {
                    Text(d)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let waiting = finding.waitingFor {
                    Text(waiting)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Recommendations section

    private func recommendationsSection(recommendations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recommendations")
            VStack(alignment: .leading, spacing: 6) {
                // The text is the identity; a review never repeats a line.
                ForEach(Array(NSOrderedSet(array: recommendations)) as! [String], id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .frame(width: 16)
                        Text(rec)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(12)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Adjustments section

    /// The review's adjustments were advice nothing could act on. The ones the
    /// server can apply edit the stored program from the current week on, under
    /// the revision check, and this copy is replaced with what was saved.
    private func adjustmentsSection(adjustments: [ProgressionAdjustment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Suggested Adjustments")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(adjustments) { adj in
                    AdjustmentRow(adjustment: adj)
                }
            }
            if let conflict = appState.programSaveConflict {
                Label(conflict, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Applied to the stored program from this week on; the web sees the same change.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No progression data yet")
                .font(.headline)
            Text("Log sessions with set data to start tracking your progression against each exercise target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: String) -> Color {
        AnalyticsStatusStyle.color(status)
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "ahead":            return "↑"
        case "on_track":         return "✓"
        case "behind":           return "↓"
        case "stalled":          return "⚠"
        default:                 return "–"
        }
    }

    /// "80kg", "45s", but "3 exercises" — the server's own rule for its
    /// change line (`progression_findings`), so the two lines agree.
    static func withUnit(_ value: String, _ unit: String) -> String {
        ["", "kg", "%", "s", "km", "m"].contains(unit) ? value + unit : "\(value) \(unit)"
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

/// "How is this scored?": the sum behind the number and the three bands,
/// the current one marked. Folded by default — the reason line above it
/// says what matters.
struct ScoreExplanation: View {
    let breakdown: ScoreBreakdown?
    let status: ScoreStatus?
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

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
                        .font(.footnote)
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
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
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
    @State private var isApplying = false
    @State private var applied = false
    @State private var outcome: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: adjustment.isAppliable ? "slider.horizontal.3" : "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                    .padding(.top, 2)
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
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(applied ? .green : .orange)
                    .disabled(isApplying || applied)
                } else {
                    Text("advice")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let outcome {
                Text(outcome)
                    .font(.caption)
                    .foregroundStyle(applied ? Color.green : Color.orange)
            }
        }
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
