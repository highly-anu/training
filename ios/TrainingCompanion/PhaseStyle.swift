import SwiftUI

/// Colour for a phase KIND — the shared vocabulary in
/// data/commons/phase_kinds.yaml, whose `display` colours tools/gen_client_vocab.py
/// writes into ClientVocab.swift and the web's `lib/phaseColors.ts` alike
/// (design-system §3.2).
///
/// A phase's *name* is its methodology's own (`ProgramWeek.phaseLabel`,
/// `PhilosophyPhase.name`); only its colour comes from the kind. Program ▸
/// Current used to colour base/build/peak/taper with system colours and grey
/// everything else, so Uphill's transition and specific phases, and every
/// maintenance block, read as one undifferentiated grey.
enum PhaseStyle {
    static func color(for kind: String) -> Color {
        ClientVocab.phases[kind].map { ClientVocab.color($0.hex) } ?? .secondary
    }
}
