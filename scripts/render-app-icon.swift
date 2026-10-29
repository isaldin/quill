// Renders the Quill app icon: a gold fountain-pen nib with sound waves on a navy squircle.
// Usage: swift scripts/render-app-icon.swift <output.png>   (1024x1024; `make icon` builds the iconset)
import AppKit

// Canvas 1024, icon body 824 with ~185 corner radius (macOS icon grid).
let size: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func background(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32) {
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    // Soft drop shadow like system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(path); ctx.setFillColor(color(bottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: nil, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    // Subtle top highlight.
    let h = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(h, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.midY), options: [])
    ctx.restoreGState()
}

render { ctx in
    background(ctx, 0x1E3A8A, 0x0B1533)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 470)
    // Sound waves on both sides of the point, fading from gold to bronze.
    ctx.setLineWidth(26); ctx.setLineCap(.round)
    for (r, c) in [(150, 0xFCD34D), (230, 0xE0A526), (310, 0xA8701A)] as [(CGFloat, UInt32)] {
        ctx.setStrokeColor(color(c))
        for mid in [CGFloat.pi, 0] {
            ctx.addArc(center: CGPoint(x: 0, y: -60), radius: r, startAngle: mid - .pi * 0.16,
                       endAngle: mid + .pi * 0.16, clockwise: false)
            ctx.strokePath()
        }
    }
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let nib = CGMutablePath()
    nib.move(to: CGPoint(x: 0, y: -170))
    nib.addCurve(to: CGPoint(x: 110, y: 160), control1: CGPoint(x: 60, y: -80), control2: CGPoint(x: 120, y: 40))
    nib.addLine(to: CGPoint(x: 90, y: 330)); nib.addLine(to: CGPoint(x: -90, y: 330)); nib.addLine(to: CGPoint(x: -110, y: 160))
    nib.addCurve(to: CGPoint(x: 0, y: -170), control1: CGPoint(x: -120, y: 40), control2: CGPoint(x: -60, y: -80))
    let g = CGGradient(colorsSpace: nil, colors: [color(0xFDE68A), color(0xD97706)] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(nib); ctx.clip()
    ctx.drawLinearGradient(g, start: CGPoint(x: -110, y: 330), end: CGPoint(x: 110, y: -170), options: [])
    ctx.restoreGState()
    ctx.setBlendMode(.destinationOut)
    ctx.setLineWidth(14); ctx.move(to: CGPoint(x: 0, y: -180)); ctx.addLine(to: CGPoint(x: 0, y: 110)); ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: -26, y: 100, width: 52, height: 52)); ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}
