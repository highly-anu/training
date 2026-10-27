import SwiftUI

/// What a methodology is: its summary, emphasis, core principles, how it
/// trains, and its tracks with their own phases (design-system §6.18). Presented from the builder's philosophy
/// cards and from Program ▸ Current's "About this methodology" — the phone's
/// counterpart to the web's Explore link. It used to be private to the
/// builder, so the program the athlete was on had no way to explain itself.
struct PhilosophyDetailSheet: View {
    let philosophy: PhilosophyCard
    /// The others it can be set beside (design-system §6.42); none, no menu.
    var compareWith: [PhilosophyCard] = []
    @Environment(\.dismiss) private var dismiss
    @State private var comparing: String?

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
                if let tracks = philosophy.tracks, !tracks.isEmpty {
                    ForEach(tracks) { track in
                        Section {
                            if let text = track.description, !text.isEmpty {
                                Text(text).font(.subheadline)
                            }
                            TrackPhaseList(track: track, showsDescriptions: true)
                                .padding(.vertical, 4)
                        } header: {
                            Text(tracks.count > 1 ? "Track — \(track.name)" : "Phases — \(track.name)")
                        }
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
                if !compareWith.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(compareWith.filter { $0.id != philosophy.id }) { other in
                                Button(other.name) { comparing = other.id }
                            }
                        } label: {
                            Label("Compare with…", systemImage: "rectangle.split.3x1")
                        }
                    }
                }
            }
            .navigationDestination(item: $comparing) { other in
                PhilosophyCompareView(ids: [philosophy.id, other])
            }
        }
    }

    /// `linear_progression_is_fastest_novice_path` → "Linear progression is fastest novice path".
    private func humanised(_ identifier: String) -> String {
        let words = identifier.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
