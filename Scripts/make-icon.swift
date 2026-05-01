import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets/RollHDR.iconset", isDirectory: true)
let output = root.appendingPathComponent("Assets/RollHDR.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()

    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.00, green: 0.95, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 0.36, green: 0.40, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.30, alpha: 1.0)
    ])!
    let orb = NSRect(x: size * 0.16, y: size * 0.16, width: size * 0.68, height: size * 0.68)
    glow.draw(in: NSBezierPath(ovalIn: orb), angle: -35)

    NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
    let ring = NSBezierPath(ovalIn: orb.insetBy(dx: size * 0.025, dy: size * 0.025))
    ring.lineWidth = max(1, size * 0.035)
    ring.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = size * 0.28
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .black),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph
    ]
    let text = "HDR"
    let textRect = NSRect(x: size * 0.08, y: size * 0.36, width: size * 0.84, height: size * 0.34)
    text.draw(in: textRect, withAttributes: attrs)

    return image
}

for (name, size) in specs {
    let image = drawIcon(size: size)
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        fatalError("Could not render \(name)")
    }
    try png.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}

print(output.path)
