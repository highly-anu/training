import XCTest

/// The design tokens stay the only place a colour, a fixed font size, a curve
/// or a button style is written (design-system §2, §4, §6.6, §7). The phone
/// had 23 fixed sizes, five `Color(red:)` palettes and three card radii
/// before 1.35; this reads the sources so they cannot come back.
final class DesignTokenTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TrainingCompanion")

    /// Each rule: what must not be written, and the files that own it.
    private static let rules: [(name: String, pattern: String, owners: Set<String>)] = [
        ("a fixed font size — use a text style or AppFont",
         #"\.system\(size:"#, ["AppTheme.swift"]),
        ("a colour literal — name it in AppColor",
         #"(?<![A-Za-z])Color\(red:"#, ["AppTheme.swift", "ClientVocab.swift"]),
        ("a bare withAnimation — pass an AppAnimation preset",
         #"withAnimation\s*\{"#, []),
        ("a curve of its own — use an AppAnimation preset",
         #"\.(easeIn|easeOut|easeInOut|linear)\(duration:"#, ["AppAnimationSettings.swift"]),
        ("a button style picked per screen — use .appButton(_:)",
         #"\.buttonStyle\(\.bordered(Prominent)?\)"#, ["AppCard.swift"]),
    ]

    func testNoViewWritesWhatATokenOwns() throws {
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100, "the sources were not found at \(Self.sources.path)")

        var found: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for rule in Self.rules where !rule.owners.contains(file.lastPathComponent) {
                let regex = try NSRegularExpression(pattern: rule.pattern)
                for (index, line) in lines.enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    let range = NSRange(line.startIndex..., in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        found.append("\(file.lastPathComponent):\(index + 1) — \(rule.name)")
                    }
                }
            }
        }
        XCTAssertTrue(found.isEmpty, "\n" + found.joined(separator: "\n"))
    }
}
