import SwiftUI

/// A measure or reading in words, as the server writes it
/// (`src/analytics/vocabulary.about`): what it measures, what has to be logged
/// for it and where, and the package's own note. Every field is optional, so
/// an older server's document simply shows no About section.
struct AboutText: Decodable, Equatable {
    struct Need: Decodable, Equatable {
        let label: String
        let place: String

        private enum CodingKeys: String, CodingKey { case label, place = "where" }
    }

    let measures: String?
    let needs: [Need]
    let notes: String?
    /// Terms explained one per row — a screen of several readings (CTL,
    /// ATL, TSB) rather than one measure; never decoded, built on the phone
    /// from the server's `TERMS`.
    var terms: [AnalyticsTerm] = []

    init(measures: String?, needs: [Need] = [], notes: String? = nil) {
        self.measures = measures
        self.needs = needs
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case measures, needs, notes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measures = try? c.decodeIfPresent(String.self, forKey: .measures)
        needs = ((try? c.decodeIfPresent([Lossy<Need>].self, forKey: .needs)) ?? [])?.compactMap(\.value) ?? []
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }

    var isEmpty: Bool { (measures ?? "").isEmpty && needs.isEmpty && (notes ?? "").isEmpty && terms.isEmpty }
}

/// One load or recovery term in words (`vocabulary.TERMS`): "TSB · form" and
/// what it is, in a sentence or two.
struct AnalyticsTerm: Decodable, Equatable {
    let label: String
    let text: String
}

extension AboutText {
    /// The About for a screen that explains terms rather than a measure: one
    /// term is its sentence; several are a row each, named, in the order
    /// given. A term the server lacks is skipped.
    init(terms ids: [String], from terms: [String: AnalyticsTerm]) {
        let found = ids.compactMap { terms[$0] }
        if found.count == 1 {
            self.init(measures: found[0].text)
        } else {
            self.init(measures: nil)
            self.terms = found
        }
    }
}

/// The end of every detail screen (design-system §6.37), as Apple Health ends
/// a metric's screen with "About": what the number measures and the
/// package's note, then what to log for it and where. The cards above say
/// numbers and symbols; the explanation lives here, once, in the server's words.
struct AboutSection: View {
    let about: AboutText

    var body: some View {
        if !(about.measures ?? "").isEmpty || !(about.notes ?? "").isEmpty || !about.terms.isEmpty {
            Section("About") {
                if let measures = about.measures, !measures.isEmpty { Text(measures) }
                ForEach(about.terms, id: \.label) { term in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.label).font(.subheadline).fontWeight(.semibold)
                        Text(term.text)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
                if let notes = about.notes, !notes.isEmpty {
                    Text(notes).foregroundStyle(.secondary)
                }
            }
        }
        if !about.needs.isEmpty {
            Section("What to log") {
                ForEach(about.needs, id: \.label) { need in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(need.label)
                        Text(need.place).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A series as a small line with its last point marked — no axes; the words
/// beside it carry the reading. The one sparkline: the standards' block line
/// and the Exercises card's chart were two of them. The caller says what it
/// shows to VoiceOver, or hides it.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var width: CGFloat = 64
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = hi - lo == 0 ? 1 : hi - lo
            let pts = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat((v - lo) / span)))
            }
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                pts.dropFirst().forEach { p.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let last = pts.last {
                Circle().fill(color).frame(width: 5, height: 5).position(last)
            }
        }
        .frame(width: width, height: height)
        .padding(.vertical, 2)
    }
}
