// Renders the DMG window background (660×400 pt, plus @2x) into Resources/dmg/background.tiff.
// The app icon sits at (170, 200) and the Applications folder at (490, 200); this draws the
// title, an arrow between those spots, and a footer. Re-run after changing the design:
//
//   swift scripts/make-dmg-background.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("Resources/dmg")
let size = NSSize(width: 660, height: 400)

let paper = NSColor(red: 0.969, green: 0.953, blue: 0.918, alpha: 1)
let ink = NSColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
let muted = NSColor(red: 0.44, green: 0.42, blue: 0.38, alpha: 1)
let accent = NSColor(red: 0.85, green: 0.35, blue: 0.16, alpha: 1)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Flip so y grows downward, matching Finder icon positions.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)

    paper.setFill()
    NSRect(origin: .zero, size: size).fill()

    func draw(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let w = s.size().width
        NSGraphicsContext.saveGraphicsState()
        // Text draws upside down in the flipped context, so unflip locally.
        let t = NSAffineTransform()
        t.translateX(by: (size.width - w) / 2, yBy: centerY + s.size().height / 2)
        t.scaleX(by: 1, yBy: -1)
        t.concat()
        s.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
    }

    let serif = NSFont(name: "NewYork-Bold", size: 26) ?? NSFont.systemFont(ofSize: 26, weight: .bold)
    draw("Drag Vibemetric into Applications", font: serif, color: ink, centerY: 62)
    draw("Then open it from Applications or Launchpad.", font: .systemFont(ofSize: 14), color: muted, centerY: 96)

    // Arrow from the app icon (x 170) to Applications (x 490), between the two icons.
    let y: CGFloat = 200
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y))
    arrow.line(to: NSPoint(x: 392, y: y))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    accent.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 376, y: y - 14))
    head.line(to: NSPoint(x: 398, y: y))
    head.line(to: NSPoint(x: 376, y: y + 14))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    draw("vibemetric.app", font: .monospacedSystemFont(ofSize: 13, weight: .medium), color: muted, centerY: 366)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let tmp = FileManager.default.temporaryDirectory
try render(scale: 1).write(to: tmp.appendingPathComponent("bg.png"))
try render(scale: 2).write(to: tmp.appendingPathComponent("bg@2x.png"))
// One TIFF holding both resolutions, so Finder uses the sharp one on Retina screens.
let tiff = Process()
tiff.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiff.arguments = ["-cathidpicheck", tmp.appendingPathComponent("bg.png").path, tmp.appendingPathComponent("bg@2x.png").path,
                  "-out", out.appendingPathComponent("background.tiff").path]
try tiff.run()
tiff.waitUntilExit()
print("Wrote \(out.appendingPathComponent("background.tiff").path)")
