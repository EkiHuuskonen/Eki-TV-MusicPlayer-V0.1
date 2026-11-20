// Piirtää ArkistoSoitin-sovelluksen ikonin: swift tools/make_icon.swift <ulostulohakemisto>
import AppKit

func gradient(_ colors: [(CGFloat, CGFloat, CGFloat, CGFloat)], _ locs: [CGFloat]) -> CGGradient {
    let cs = CGColorSpaceCreateDeviceRGB()
    let cg = colors.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: $0.3) } as CFArray
    return CGGradient(colorsSpace: cs, colors: cg, locations: locs)!
}

func draw(_ ctx: CGContext, fullBleed: Bool = false) {
    // Koordinaatisto 0...1, origo vasemmassa alakulmassa
    // fullBleed = iOS/tvOS-ikoni: neliö reunasta reunaan ilman läpinäkyvyyttä (järjestelmä pyöristää kulmat)
    let rect = fullBleed ? CGRect(x: 0, y: 0, width: 1, height: 1) : CGRect(x: 0.098, y: 0.098, width: 0.804, height: 0.804)
    let shape = fullBleed ? CGPath(rect: rect, transform: nil) : CGPath(roundedRect: rect, cornerWidth: 0.185, cornerHeight: 0.185, transform: nil)

    // Varjo
    ctx.saveGState()
    if !fullBleed {
    ctx.setShadow(offset: CGSize(width: 0, height: -0.014), blur: 0.03, color: CGColor(gray: 0, alpha: 0.4))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
    }
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // Taustagradientti: violetti → magenta → oranssi
    let bg = gradient([(0.22, 0.18, 0.88, 1), (0.78, 0.22, 0.78, 1), (1.0, 0.62, 0.22, 1)], [0, 0.55, 1])
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0.1, y: 0.95), end: CGPoint(x: 0.9, y: 0.05), options: [])

    // Pehmeä valo vasemmasta yläkulmasta
    let glow = gradient([(1, 1, 1, 0.35), (1, 1, 1, 0)], [0, 1])
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 0.3, y: 0.78), startRadius: 0,
                           endCenter: CGPoint(x: 0.3, y: 0.78), endRadius: 0.55, options: [])

    // Vinyylilevy: tumma kiekko ja urat
    let c = CGPoint(x: 0.5, y: 0.5)
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.20))
    ctx.fillEllipse(in: CGRect(x: c.x - 0.385, y: c.y - 0.385, width: 0.77, height: 0.77))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); ctx.setLineWidth(0.005)
    for r in [0.36, 0.31, 0.26, 0.21] as [CGFloat] {
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // Nuotti (kaksi kahdeksasosaa palkilla)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -0.012), blur: 0.025, color: CGColor(gray: 0, alpha: 0.35))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    func head(_ x: CGFloat, _ y: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y); ctx.rotate(by: -0.38)
        ctx.fillEllipse(in: CGRect(x: -0.088, y: -0.062, width: 0.176, height: 0.124))
        ctx.restoreGState()
    }
    head(0.385, 0.40); head(0.635, 0.355)
    ctx.fill(CGRect(x: 0.442, y: 0.41, width: 0.034, height: 0.35))    // vasen vars
    ctx.fill(CGRect(x: 0.692, y: 0.365, width: 0.034, height: 0.355))  // oikea vars
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: 0.442, y: 0.805)); beam.addLine(to: CGPoint(x: 0.726, y: 0.76))
    beam.addLine(to: CGPoint(x: 0.726, y: 0.685)); beam.addLine(to: CGPoint(x: 0.442, y: 0.73))
    beam.closeSubpath()
    ctx.addPath(beam); ctx.fillPath()
    ctx.restoreGState()

    // Värikkäät tasoitinpalkit alareunaan
    let barColors: [(CGFloat, CGFloat, CGFloat)] = [(0.35, 0.95, 0.85), (0.55, 1.0, 0.45), (1.0, 0.92, 0.35), (1.0, 0.65, 0.35), (1.0, 0.45, 0.6)]
    let heights: [CGFloat] = [0.05, 0.085, 0.065, 0.10, 0.055]
    for i in 0..<5 {
        let x = 0.355 + CGFloat(i) * 0.065
        let col = barColors[i]
        ctx.setFillColor(CGColor(red: col.0, green: col.1, blue: col.2, alpha: 0.95))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 0.155, width: 0.04, height: heights[i]),
                           cornerWidth: 0.02, cornerHeight: 0.02, transform: nil))
        ctx.fillPath()
    }

    ctx.restoreGState()

    // Ohut kiiltoreuna
    if !fullBleed {
    ctx.saveGState()
    ctx.addPath(shape); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rim = gradient([(1, 1, 1, 0.45), (1, 1, 1, 0.05)], [0, 1])
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0.5, y: 0.9), end: CGPoint(x: 0.5, y: 0.1), options: [])
    ctx.restoreGState()
    }
}

func png(size: Int, fullBleed: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size), y: CGFloat(size))
    ctx.setLineWidth(1.0 / CGFloat(size))
    draw(ctx, fullBleed: fullBleed)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    try! png(size: size).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
try! png(size: 1024, fullBleed: true).write(to: URL(fileURLWithPath: "\(out)/fullbleed_1024.png"))
print("Ikoni piirretty: \(out)")
