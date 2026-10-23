// Draws the workout icons' contact sheet: every icon, in the modality colours,
// at a Garmin hero's size, a list row's and a header's, on light and dark —
// the review sheet tools/icons/gen_workout_icons.py --preview writes.
//
//   swift tools/icons/render_icons.swift <sheet.json> <out.png>
//
// sheet.json: {"icons": [{"id", "label", "d"}], "colors": [{"name", "hex"}],
//              "sizes": [px…]} — each `d` an SVG path (M/L/C/Z) on a 100 box.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let data = FileManager.default.contents(atPath: args[1]),
      let sheet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let icons = sheet["icons"] as? [[String: String]],
      let colors = sheet["colors"] as? [[String: String]],
      let sizes = sheet["sizes"] as? [Double] else {
    print("usage: render_icons.swift <sheet.json> <out.png>"); exit(1)
}

func path(_ d: String) -> CGPath {
    let p = CGMutablePath()
    let s = Scanner(string: d.replacingOccurrences(of: ",", with: " "))
    s.charactersToBeSkipped = .whitespaces
    func pt() -> CGPoint { CGPoint(x: s.scanDouble() ?? 0, y: s.scanDouble() ?? 0) }
    while !s.isAtEnd {
        guard let c = s.scanCharacter() else { break }
        switch c {
        case "M": p.move(to: pt())
        case "L": p.addLine(to: pt())
        case "C": let a = pt(), b = pt(), e = pt(); p.addCurve(to: e, control1: a, control2: b)
        case "Z": p.closeSubpath()
        default: break
        }
    }
    return p
}

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

let pad = 14.0, labelW = 190.0
let cell = (sizes.max() ?? 96) + pad
let perTheme = Double(colors.count) * sizes.reduce(0) { $0 + $1 + pad }
let width = labelW + 2 * perTheme + 3 * pad
let height = Double(icons.count) * cell + 40
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1)   // y down, as the glyphs

let themes: [(bg: NSColor, fg: NSColor)] = [
    (NSColor(white: 0.98, alpha: 1), NSColor(white: 0.1, alpha: 1)),
    (NSColor(srgbRed: 0.07, green: 0.08, blue: 0.1, alpha: 1), NSColor(white: 0.92, alpha: 1)),
]
for (t, theme) in themes.enumerated() {
    let x0 = labelW + pad + Double(t) * (perTheme + pad)
    ctx.setFillColor(theme.bg.cgColor)
    ctx.fill(CGRect(x: t == 0 ? 0 : x0 - pad / 2, y: 0, width: t == 0 ? x0 + perTheme + pad / 2 : perTheme + pad, height: height))
}

func text(_ s: String, at p: CGPoint, size: CGFloat, color c: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform(); flip.translateX(by: p.x, yBy: p.y + size); flip.scaleX(by: 1, yBy: -1); flip.concat()
    (s as NSString).draw(at: .zero, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: c])
    NSGraphicsContext.restoreGraphicsState()
}

for (t, theme) in themes.enumerated() {
    var x = labelW + pad + Double(t) * (perTheme + pad)
    for c in colors {
        text(c["name"] ?? "", at: CGPoint(x: x, y: 10), size: 11, color: theme.fg)
        x += sizes.reduce(0) { $0 + $1 + pad }
    }
}
for (i, icon) in icons.enumerated() {
    let y = 40 + Double(i) * cell
    text(icon["id"] ?? "", at: CGPoint(x: pad, y: y + cell / 2 - 16), size: 13, color: themes[0].fg)
    text(icon["label"] ?? "", at: CGPoint(x: pad, y: y + cell / 2 + 2), size: 11, color: .gray)
    let shape = path(icon["d"] ?? "")
    for (t, _) in themes.enumerated() {
        var x = labelW + pad + Double(t) * (perTheme + pad)
        for c in colors {
            for s in sizes {
                ctx.saveGState()
                ctx.translateBy(x: x, y: y + (cell - pad - s) / 2)
                ctx.scaleBy(x: s / 100, y: s / 100)
                ctx.addPath(shape)
                ctx.setFillColor(color(c["hex"] ?? "#888888").cgColor)
                ctx.fillPath(using: .winding)
                ctx.restoreGState()
                x += s + pad
            }
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print(args[2])
