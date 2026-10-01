import SwiftUI

/// The phone's exercise reference (design system §6.14): what a movement is,
/// how to do it, what it needs and what it leads to. Presented from any row
/// that names an exercise — a planned session's rows, and the alternatives in
/// the swap sheet — so the athlete never has to leave the session to look a
/// movement up. Reads the catalog entry from `GET /api/exercises` and the
/// package's media from `GET /api/exercises/<id>/media`.
struct ExerciseDetailSheet: View {
    let exerciseId: String
    let name: String
    /// The prescription this sheet was opened from, when there is one.
    var assignment: ProgramExerciseAssignment? = nil

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var media: ExerciseMedia? = nil
    @State private var isLoading = true

    private var catalogEntry: AppExercise? { appState.exerciseCatalog[exerciseId] }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if let assignment { prescriptionSection(assignment) }
                if let url = media?.gifURL { animationSection(url) }
                if let text = media?.description, !text.isEmpty {
                    Section("What it is") { Text(text).font(.subheadline) }
                }
                if let focus = media?.coachingFocus, !focus.isEmpty {
                    Section("Coaching focus") {
                        Label(focus, systemImage: "scope").font(.subheadline)
                    }
                }
                bulletSection("Cues", items: media?.cuePoints ?? [], icon: "checkmark.circle")
                bulletSection("Common errors", items: media?.commonErrors ?? [], icon: "xmark.circle",
                              tint: .orange)
                requirementsSection
                if isLoading && media == nil && catalogEntry == nil {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let category = catalogEntry?.category {
                        chip(category.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    if let effort = catalogEntry?.effort {
                        chip("\(effort.capitalized) effort")
                    }
                    if let difficulty = catalogEntry?.difficulty {
                        chip(difficulty.capitalized)
                    }
                }
                if let patterns = catalogEntry?.movementPatterns, !patterns.isEmpty {
                    Text(patterns.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let muscles = media?.musclesPrimary, !muscles.isEmpty {
                    Text(muscles.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let note = catalogEntry?.notes, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).italic()
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func prescriptionSection(_ ea: ProgramExerciseAssignment) -> some View {
        Section("This session") {
            VStack(alignment: .leading, spacing: 4) {
                Text(LoadFormat.describe(ea))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)
                if let note = ea.loadNote, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let note = ea.notes, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).italic()
                }
            }
        }
    }

    private func animationSection(_ url: URL) -> some View {
        Section {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("Could not load the demo", systemImage: "photo")
                        .font(.caption).foregroundStyle(.secondary)
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // Opens in Safari — the sheet stays a reference, not a browser.
            Link(destination: url) {
                Label(media?.animation?.gifSource.map { "Source: \($0.replacingOccurrences(of: "_", with: " "))" }
                      ?? "Open demo", systemImage: "safari")
                    .font(.caption)
            }
        } header: {
            Text("Demo")
        }
    }

    @ViewBuilder
    private func bulletSection(_ title: String, items: [String], icon: String,
                               tint: Color = .green) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.self) { item in
                    Label {
                        Text(item).font(.subheadline)
                    } icon: {
                        Image(systemName: icon).foregroundStyle(tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var requirementsSection: some View {
        let requires = catalogEntry?.requires ?? []
        let unlocks = catalogEntry?.unlocks ?? []
        let equipment = catalogEntry?.equipment ?? []
        if !requires.isEmpty || !unlocks.isEmpty || !equipment.isEmpty {
            Section("Prerequisites & progression") {
                if !equipment.isEmpty {
                    row("Equipment", equipment.map(humanize).joined(separator: ", "), icon: "dumbbell")
                }
                if !requires.isEmpty {
                    row("Requires", requires.map(resolveName).joined(separator: ", "), icon: "arrow.turn.down.right")
                }
                if !unlocks.isEmpty {
                    row("Unlocks", unlocks.map(resolveName).joined(separator: ", "), icon: "arrow.up.right")
                }
            }
        }
    }

    // MARK: - Pieces

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline)
            }
        }
    }

    /// A requirement is a concept ("bracing_mechanics") or another exercise;
    /// the catalog gives the exercise its name.
    private func resolveName(_ id: String) -> String {
        appState.exerciseCatalog[id]?.name ?? humanize(id)
    }

    private func humanize(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func load() async {
        isLoading = true
        async let catalog: () = appState.loadExercisesIfNeeded()
        async let fetched = appState.api?.fetchExerciseMedia(id: exerciseId)
        _ = await catalog
        media = (try? await fetched) ?? nil
        isLoading = false
    }
}
