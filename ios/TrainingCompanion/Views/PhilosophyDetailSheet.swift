import SwiftUI

/// What a methodology is: its summary, emphasis, core principles and how it
/// trains (design-system §6.18). Presented from the builder's philosophy
/// cards and from Program ▸ Current's "About this methodology" — the phone's
/// counterpart to the web's Explore link. It used to be private to the
/// builder, so the program the athlete was on had no way to explain itself.
struct PhilosophyDetailSheet: View {
    let philosophy: PhilosophyCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let summary = philosophy.summary, !summary.isEmpty {
                    Section {
                        Text(summary)
                    }
                }
                if let bias = philosophy.bias, !bias.isEmpty {
                    Section("Emphasis") {
                        ForEach(bias, id: \.self) { mod in
                            Label(ModalityStyle.label(for: mod), systemImage: ModalityStyle.icon(for: mod))
                                .foregroundStyle(ModalityStyle.color(for: mod))
                        }
                    }
                }
                if let principles = philosophy.corePrinciples, !principles.isEmpty {
                    Section("Core principles") {
                        ForEach(principles, id: \.self) { Text(humanised($0)) }
                    }
                }
                if philosophy.intensityModel != nil || philosophy.progressionPhilosophy != nil {
                    Section("How it trains") {
                        if let model = philosophy.intensityModel {
                            LabeledContent("Intensity", value: humanised(model))
                        }
                        if let progression = philosophy.progressionPhilosophy {
                            LabeledContent("Progression", value: humanised(progression))
                        }
                    }
                }
            }
            .navigationTitle(philosophy.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    /// `linear_progression_is_fastest_novice_path` → "Linear progression is fastest novice path".
    private func humanised(_ identifier: String) -> String {
        let words = identifier.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
