import SwiftUI

/// Today's readiness in full (design-system §6.37), pushed from its card on
/// Analytics ▸ Recovery: the score and its flags, the parts it is made of
/// against their maxima (the server's words), the watch's recovery readings,
/// the morning's readings, where each came from, and what readiness is.
struct ReadinessDetailView: View {
    let result: ReadinessResult
    /// The newest check-in or relay day, for the readings the score read.
    let latest: DailyBioLog?

    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(result.score)")
                            .font(.largeTitle).fontWeight(.bold).fontDesign(.rounded).monospacedDigit()
                            .foregroundStyle(result.statusColor)
                        TintCapsule(text: result.statusLabel, symbol: result.statusIcon, color: result.statusColor)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    ReadinessFlagChips(flags: result.flags)
                }
                .padding(.vertical, 2)
            }
            if let parts = result.parts, !parts.isEmpty {
                Section("Score") {
                    ForEach(parts) { part in partRow(part) }
                    if let capped = result.cappedAt {
                        LabeledContent {
                            Text("\(capped)").monospacedDigit()
                        } label: {
                            Label("Capped by recovery time left", systemImage: "hourglass")
                        }
                    }
                }
            }
            if let watch = result.watch, watch.bodyBattery != nil || watch.recoveryLeftH != nil {
                Section("Watch") {
                    if let bb = watch.bodyBattery {
                        LabeledContent("Body Battery") { Text("\(bb)").monospacedDigit() }
                    }
                    if let left = watch.recoveryLeftH {
                        LabeledContent("Recovery left") { Text("\(Int(left.rounded())) h").monospacedDigit() }
                    }
                }
            }
            if let latest, latest.hrv != nil || latest.restingHR != nil || (latest.sleepDurationMin ?? 0) > 0 {
                Section("Readings") {
                    if let hrv = latest.hrv {
                        LabeledContent("HRV") { Text("\(Int(hrv)) ms").monospacedDigit() }
                    }
                    if let hr = latest.restingHR {
                        LabeledContent("Resting HR") { Text("\(Int(hr)) bpm").monospacedDigit() }
                    }
                    if let sleep = latest.sleepDurationMin, sleep > 0 {
                        LabeledContent("Sleep") { Text(SleepFormat.duration(sleep)).monospacedDigit() }
                    }
                }
            }
            // Where each reading came from: the one sentence the card used to
            // carry under the score (§6.21), here with the parts it explains.
            if let note = result.sourceNote {
                Section("Sources") { Text(note).font(.subheadline) }
            }
            AboutSection(about: AboutText(terms: ["readiness"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Readiness")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["readiness"]) }
    }

    /// A part: its name, points of its maximum, and a bar of the share.
    private func partRow(_ part: ReadinessPart) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(part.label) {
                Text("\(part.points)/\(part.max)").monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                    // One colour for every part: the score's status colour
                    // made "Session fatigue 1/10" a green bar.
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(part.points) / CGFloat(max(part.max, 1)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(part.label): \(part.points) of \(part.max) points")
    }
}
