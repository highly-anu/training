// Draws a custom symbol beside the SF Symbols it will sit among, in dark and
// light, large and at list size in the modality colours — the review sheet for
// a new icon (ios/docs/custom-icons.md).
//
//   swift ios/tools/preview_symbol.swift kettlebell /tmp/kb.png \
//       dumbbell.fill figure.strengthtraining.traditional figure.run bolt.fill
//
// It reads the symbolset's Regular-S path (M/L/C/Z, as symbol_template.py
// writes it) and sizes it as the template places it, so what the sheet shows is
// what Xcode compiles — but check the app in the simulator before committing.
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: preview_symbol.swift <symbol name> <out.png> [system symbols…]"); exit(1)
}
let name = args[1], outPath = args[2], neighbours = Array(args.dropFirst(3))
let toolDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let svgURL = toolDir.appendingPathComponent("../TrainingCompanion/Assets.xcassets/\(name).symbolset/\(name).svg")
guard let svg = try? String(contentsOf: svgURL, encoding: .utf8) else {
    print("no symbolset at \(svgURL.standardized.path)"); exit(1)
}

// MARK: - The Regular-S path, in template units

guard let groupStart = svg.range(of: "<g id=\"Regular-S\">"),
      let dStart = svg.range(of: "d=\"", range: groupStart.upperBound..<svg.endIndex),
      let dEnd = svg.range(of: "\"", range: dStart.upperBound..<svg.endIndex) else {
    print("no Regular-S path in \(name).svg"); exit(1)
}
let d = String(svg[dStart.upperBound..<dEnd.lowerBound])
let baseline = 696.0, capline = 625.541

func templatePath() -> CGPath {
    let path = CGMutablePath()
    let scanner = Scanner(string: d)
    scanner.charactersToBeSkipped = .whitespaces
    func pt() -> CGPoint {
        let x = scanner.scanDouble() ?? 0, y = scanner.scanDouble() ?? 0
        return CGPoint(x: x, y: y)
    }
    while !scanner.isAtEnd {
        guard let cmd = scanner.scanCharacter() else { break }
        switch cmd {
        case "M": path.move(to: pt())
        case "L": path.addLine(to: pt())
        case "C": let c1 = pt(), c2 = pt(), p = pt(); path.addCurve(to: p, control1: c1, control2: c2)
        case "Z": path.closeSubpath()
        default: print("unsupported path command \(cmd)"); exit(1)
        }
    }
    return path
}
let glyph = templatePath()

// MARK: - Drawing

let W: CGFloat = 1500, H: CGFloat = 860
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocusFlipped(true)
let ctx = NSGraphicsContext.current!.cgContext

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
// ModalityStyle's colours: movement skill, power, max strength.
let rowColours: [(NSColor, String)] = [(hex(0x14b8a6), "Movement skill"), (hex(0xeab308), "Power"),
                                       (hex(0xef4444), "Max strength")]

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor) {
    (s as NSString).draw(at: NSPoint(x: x, y: y),
                         withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
}

/// An SF Symbol at point size `pt`, vertically centred in a `pt * 1.3` line.
func system(_ symbol: String, _ x: CGFloat, _ y: CGFloat, _ pt: CGFloat, _ color: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular).applying(.init(paletteColors: [color]))
    guard let im = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else {
        text("no symbol \(symbol)", x, y, 13, .systemRed); return
    }
    im.draw(in: NSRect(x: x, y: y + (pt * 1.3 - im.size.height) / 2, width: im.size.width, height: im.size.height))
}

/// The custom symbol at point size `pt`: template units are points at 100 pt,
/// and SwiftUI's default (medium) scale is the Small row × 1/0.783.
func custom(_ x: CGFloat, _ y: CGFloat, _ pt: CGFloat, _ color: NSColor) {
    let s = pt / 100 / 0.783
    let box = glyph.boundingBoxOfPath
    let mid = (baseline + capline) / 2
    ctx.saveGState()
    ctx.translateBy(x: x - box.minX * s, y: y + pt * 1.3 / 2 - mid * s)
    ctx.scaleBy(x: s, y: s)
    ctx.addPath(glyph)
    ctx.setFillColor(color.cgColor)
    ctx.fillPath()                      // non-zero, as the template is filled
    ctx.restoreGState()
}

func card(_ rect: CGRect, _ colour: NSColor) {
    ctx.setFillColor(colour.cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.fillPath()
}

func panel(_ y0: CGFloat, dark: Bool) {
    let bg = dark ? hex(0x000000) : hex(0xF2F2F7), surface = dark ? hex(0x1C1C1E) : hex(0xFFFFFF)
    let fg: NSColor = dark ? .white : .black, sub = dark ? hex(0x8E8E93) : hex(0x6C6C70)
    ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: 0, y: y0, width: W, height: 430))
    text(dark ? "Dark" : "Light", 30, y0 + 16, 22, sub)

    // Large, beside its neighbours.
    for (i, symbol) in ([name] + neighbours.prefix(5)).enumerated() {
        let x = 40 + CGFloat(i) * 240
        card(CGRect(x: x - 10, y: y0 + 56, width: 220, height: 150), surface)
        if i == 0 { custom(x + 70, y0 + 80, 56, fg) } else { system(symbol, x + 70, y0 + 80, 56, fg) }
        text(i == 0 ? "\(symbol) (custom)" : symbol, x, y0 + 172, 14, sub)
    }
    // At list size (.title3), in the modality colours, beside the first neighbour.
    for (col, drawCustom) in [(CGFloat(30), true), (760, false)] {
        card(CGRect(x: col, y: y0 + 225, width: 700, height: 190), surface)
        for (i, row) in rowColours.enumerated() {
            let y = y0 + 240 + CGFloat(i) * 60
            if drawCustom { custom(col + 22, y + 4, 20, row.0) }
            else if let first = neighbours.first { system(first, col + 22, y + 4, 20, row.0) }
            text("\(row.1) session", col + 80, y, 22, fg)
            text(drawCustom ? name : (neighbours.first ?? ""), col + 80, y + 28, 15, sub)
        }
    }
}

panel(0, dark: true)
panel(430, dark: false)
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print(outPath)
