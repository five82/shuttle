// Renders the shuttle app icon at every size the asset catalog needs.
//   swiftc -O -o render docs/render-icon.swift && ./render shuttle/Assets.xcassets/AppIcon.appiconset
//
// The mark: an open gradient ring with a pulse line running through it.
import AppKit

let outDir = CommandLine.arguments[1]
let base: CGFloat = 1024

struct RGB { var r: CGFloat, g: CGFloat, b: CGFloat }
func rgb(_ v: UInt32) -> RGB { RGB(r: CGFloat((v >> 16) & 0xff) / 255, g: CGFloat((v >> 8) & 0xff) / 255, b: CGFloat(v & 0xff) / 255) }
func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB { RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t) }
func color(_ c: RGB, _ alpha: CGFloat = 1) -> NSColor { NSColor(calibratedRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor { color(rgb(v), alpha) }

/// Piecewise-linear colour ramp over t in 0...1.
func ramp(_ stops: [(CGFloat, RGB)], _ t: CGFloat) -> RGB {
    let t = min(max(t, 0), 1)
    for i in 1..<stops.count where t <= stops[i].0 {
        let (t0, c0) = stops[i - 1], (t1, c1) = stops[i]
        return mix(c0, c1, (t - t0) / max(t1 - t0, 0.0001))
    }
    return stops.last!.1
}

let tileTop = rgb(0x2A3042), tileBottom = rgb(0x1B1F2B)
let ringRadius: CGFloat = 250
let ringWidth: CGFloat = 108
let capAngleLeft: CGFloat = 168      // where the purple cap sits
let capAngleRight: CGFloat = -6      // where the blue cap sits

// Top segment: right cap up over the top to the left cap. Cyan -> blue -> deep indigo.
let topStops: [(CGFloat, RGB)] = [(0, rgb(0x3CCBF7)), (0.35, rgb(0x2E8CF2)), (0.75, rgb(0x2F55B6)), (1, rgb(0x3A4FA8))]
// Bottom segment: left cap down under the bottom to the right cap. Purple -> violet -> blue.
let bottomStops: [(CGFloat, RGB)] = [(0, rgb(0xC77CF2)), (0.45, rgb(0x8A5FE8)), (0.8, rgb(0x4A82F1)), (1, rgb(0x3A9AF4))]
let pulseStops: [(CGFloat, RGB)] = [(0, rgb(0xB070EE)), (0.5, rgb(0x4A86F0)), (1, rgb(0x3AC0F5))]

func drawArcSegment(_ ctx: CGContext, from a0: CGFloat, to a1: CGFloat, stops: [(CGFloat, RGB)], width: CGFloat) {
    let steps = 160
    let sweep = a1 - a0
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
        let path = NSBezierPath()
        path.appendArc(withCenter: .zero, radius: ringRadius, startAngle: a0 + sweep * t0, endAngle: a0 + sweep * min(t1 + 0.012, 1), clockwise: sweep < 0)
        path.lineWidth = width
        color(ramp(stops, (t0 + t1) / 2)).setStroke()
        path.stroke()
    }
    for (t, angle) in [(CGFloat(0), a0), (CGFloat(1), a1)] {
        let rad = angle * .pi / 180
        let p = CGPoint(x: cos(rad) * ringRadius, y: sin(rad) * ringRadius)
        color(ramp(stops, t)).setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)).fill()
    }
}

func pulsePath() -> NSBezierPath {
    // Flat line with one heartbeat in the middle; Catmull-Rom smoothed.
    let inner = ringRadius - ringWidth / 2 + 6
    let pts: [CGPoint] = [
        CGPoint(x: -inner, y: 0), CGPoint(x: -120, y: 0), CGPoint(x: -98, y: 0), CGPoint(x: -84, y: 26), CGPoint(x: -70, y: 0),
        CGPoint(x: -52, y: -78), CGPoint(x: -34, y: 0), CGPoint(x: -6, y: 104), CGPoint(x: 16, y: 0),
        CGPoint(x: 36, y: -56), CGPoint(x: 56, y: 0), CGPoint(x: 74, y: 26), CGPoint(x: 90, y: 0), CGPoint(x: 112, y: 0), CGPoint(x: inner, y: 0),
    ]
    let path = NSBezierPath()
    path.move(to: pts[0])
    for i in 0..<(pts.count - 1) {
        let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }
    path.lineWidth = 20
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func draw(into ctx: CGContext, size s: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: s / base, y: s / base)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let inset: CGFloat = 100
    let tile = CGRect(x: inset, y: inset, width: base - 2 * inset, height: base - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: color(tileTop), ending: color(tileBottom))!.draw(in: tilePath, angle: -90)

    ctx.saveGState()
    tilePath.addClip()
    ctx.translateBy(x: 512, y: 512)

    // Soft shadow under the ring for a little depth.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: hex(0x000000, 0.55).cgColor)
    let shadowRing = NSBezierPath()
    shadowRing.appendArc(withCenter: .zero, radius: ringRadius, startAngle: 0, endAngle: 360)
    shadowRing.lineWidth = ringWidth
    hex(0x000000, 0.01).setStroke()
    shadowRing.stroke()
    ctx.restoreGState()

    // Ring: top segment beneath, bottom segment on top so its caps overlap.
    drawArcSegment(ctx, from: capAngleRight, to: capAngleLeft, stops: topStops, width: ringWidth)
    drawArcSegment(ctx, from: capAngleLeft, to: capAngleRight + 360, stops: bottomStops, width: ringWidth)

    // Pulse line with a horizontal gradient, clipped to its stroke.
    let pulse = pulsePath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: hex(0x000000, 0.45).cgColor)
    hex(0x4A86F0).setStroke()
    pulse.stroke()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(pulse.cgPath)
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let colors = [hex(0xB070EE).cgColor, hex(0x4A86F0).cgColor, hex(0x3AC0F5).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: -ringRadius, y: 0), end: CGPoint(x: ringRadius, y: 0), options: [])
    ctx.restoreGState()

    ctx.restoreGState()
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.setAllowsAntialiasing(true)
    draw(into: ctx.cgContext, size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: size).write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-\(size).png"))
}
print("rendered")
