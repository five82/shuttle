// Renders the shuttle app icon at every size the asset catalog needs.
//   swiftc -O -o render docs/render-icon.swift && ./render shuttle/Assets.xcassets/AppIcon.appiconset
//
// The mark: a navy tile with two clockwise arrow arcs (a sync cycle), a teal
// status dot at the hub, and three fading dots trailing out of the open side.
import AppKit

let outDir = CommandLine.arguments[1]
let base: CGFloat = 1024

struct RGB { var r: CGFloat, g: CGFloat, b: CGFloat }
func rgb(_ v: UInt32) -> RGB { RGB(r: CGFloat((v >> 16) & 0xff) / 255, g: CGFloat((v >> 8) & 0xff) / 255, b: CGFloat(v & 0xff) / 255) }
func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB { RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t) }
func color(_ c: RGB, _ alpha: CGFloat = 1) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
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

let tileTop = rgb(0x131F42), tileBottom = rgb(0x101A38)
let ringRadius: CGFloat = 250
let ringWidth: CGFloat = 56
let headLength: CGFloat = 96      // arrowhead length along the tangent
let headWidth: CGFloat = 118      // arrowhead base width

// Angles are in degrees, counter-clockwise from +x, y up. Both arrows run clockwise.
// Top arc: tail at lower-left, up over the top, head on the upper right.
let topTail: CGFloat = 200, topHead: CGFloat = 42
let topStops: [(CGFloat, RGB)] = [(0, rgb(0x3A4586)), (0.3, rgb(0x4955AA)), (0.7, rgb(0x6371F0)), (1, rgb(0x6A76FF))]
// Bottom arc: tail at lower-right, under the bottom, head on the lower left.
let bottomTail: CGFloat = -30, bottomHead: CGFloat = -146
let bottomStops: [(CGFloat, RGB)] = [(0, rgb(0x34405E)), (0.35, rgb(0x4E5C7D)), (0.75, rgb(0x6D7FA3)), (1, rgb(0x8598BE))]

func point(_ angle: CGFloat, _ r: CGFloat = ringRadius) -> CGPoint {
    let rad = angle * .pi / 180
    return CGPoint(x: cos(rad) * r, y: sin(rad) * r)
}

/// Stroke an arc from `tail` clockwise to `head` (angles decreasing) with a colour ramp, and cap the head with an arrowhead.
func drawArrowArc(_ ctx: CGContext, tail: CGFloat, head: CGFloat, stops: [(CGFloat, RGB)]) {
    // Stop the stroke short of the head so the arrowhead base sits flush on the arc.
    let headArc = headLength / ringRadius * 180 / .pi
    let end = head + headArc
    let sweep = end - tail  // negative: clockwise
    // Round the tail: a disc drawn first so the gradient stroke covers its leading half.
    let tailPoint = point(tail)
    color(ramp(stops, 0)).setFill()
    NSBezierPath(ovalIn: CGRect(x: tailPoint.x - ringWidth / 2, y: tailPoint.y - ringWidth / 2, width: ringWidth, height: ringWidth)).fill()
    let steps = 200
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
        let path = NSBezierPath()
        path.appendArc(withCenter: .zero, radius: ringRadius, startAngle: tail + sweep * t0, endAngle: tail + sweep * min(t1 + 0.01, 1), clockwise: true)
        path.lineWidth = ringWidth
        color(ramp(stops, (t0 + t1) / 2)).setStroke()
        path.stroke()
    }
    // Arrowhead: base centred on the arc at `end`, tip further clockwise along the tangent.
    let basePoint = point(end)
    let radial = CGPoint(x: cos(end * .pi / 180), y: sin(end * .pi / 180))
    let tangent = CGPoint(x: radial.y, y: -radial.x)  // clockwise direction
    let tip = CGPoint(x: basePoint.x + tangent.x * headLength, y: basePoint.y + tangent.y * headLength)
    let a = CGPoint(x: basePoint.x + radial.x * headWidth / 2, y: basePoint.y + radial.y * headWidth / 2)
    let b = CGPoint(x: basePoint.x - radial.x * headWidth / 2, y: basePoint.y - radial.y * headWidth / 2)
    let headPath = NSBezierPath()
    headPath.move(to: a); headPath.line(to: tip); headPath.line(to: b); headPath.close()
    headPath.lineJoinStyle = .round
    headPath.lineWidth = 10
    color(ramp(stops, 1)).setFill()
    color(ramp(stops, 1)).setStroke()
    headPath.fill()
    headPath.stroke()
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

    // Faint track across the open side, between the two arrows.
    let track = NSBezierPath()
    track.appendArc(withCenter: .zero, radius: ringRadius, startAngle: bottomTail, endAngle: topHead, clockwise: false)
    track.lineWidth = ringWidth
    track.lineCapStyle = .butt
    hex(0xFFFFFF, 0.06).setStroke()
    track.stroke()

    drawArrowArc(ctx, tail: topTail, head: topHead, stops: topStops)
    drawArrowArc(ctx, tail: bottomTail, head: bottomHead, stops: bottomStops)

    // Hub: teal status dot with a soft glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: hex(0x35E7C0, 0.45).cgColor)
    hex(0x35E7C0).setFill()
    NSBezierPath(ovalIn: CGRect(x: -44, y: -44, width: 88, height: 88)).fill()
    ctx.restoreGState()

    // Trailing dots fading out to the right.
    for (i, c) in [0x7C91B8, 0x455373, 0x394564].enumerated() {
        let x = 172 + CGFloat(i) * 66
        hex(UInt32(c)).setFill()
        NSBezierPath(ovalIn: CGRect(x: x - 24, y: -24, width: 48, height: 48)).fill()
    }

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
