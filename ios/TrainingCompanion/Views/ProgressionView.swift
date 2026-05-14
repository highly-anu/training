import SwiftUI

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
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await appState.loadProgressionReview()
        }
    }

    // MARK: - Review content

    private func reviewContent(review: ProgressionReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewCard(review: review)
                if !review.exerciseFindings.isEmpty {
                    findingsSection(findings: review.exerciseFindings)
                }
                if !review.recommendations.isEmpty {
                    recommendationsSection(recommendations: review.recommendations)
                }
                if !review.adjustments.isEmpty {
                    adjustmentsSection(adjustments: review.adjustments)
                }
                Spacer(minLength: 32)
            }
            .padding()
        }
    }

    // MARK: - Overview card

    private func overviewCard(review: ProgressionReview) -> some View {
        let score = review.overallScore
        let color: Color = score.map { scoreColor($0) } ?? .secondary

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                        Text(scoreLabel(s))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text("Not enough data yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statPill(label: "Compliance", value: "\(review.compliancePct)%")
                    statPill(label: "Period", value: review.periodType == "biweekly" ? "Bi-weekly" : "Weekly")
                }
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
                        Text("\(formatValue(actual))\(finding.unit)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    if let expected = finding.expectedValue {
                        Text("(target \(formatValue(expected))\(finding.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(finding.changeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
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

    private func adjustmentsSection(adjustments: [ProgressionAdjustment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Suggested Adjustments")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(adjustments) { adj in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adj.target.capitalized)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            Text(adj.reason)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(12)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func scoreColor(_ score: Int) -> Color {
        if score >= 70 { return .green }
        if score >= 45 { return .yellow }
        return .red
    }

    private func scoreLabel(_ score: Int) -> String {
        if score >= 70 { return "On Track" }
        if score >= 45 { return "Mixed" }
        return "Off Track"
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ahead", "on_track": return .green
        case "behind":            return .yellow
        case "stalled":           return .red
        default:                  return .secondary
        }
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

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}
