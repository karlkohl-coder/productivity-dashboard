#!/usr/bin/env swift
// Erzeugt Resources/AppIcon.icns – ein schlichtes Raster-Symbol.
import AppKit

let accent = NSColor(srgbRed: 0.29, green: 0.44, blue: 0.98, alpha: 1)
let sizes = [16, 32, 128, 256, 512]  // von iconutil erwartete Kantenlängen

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    // Abgerundeter Hintergrund im Squircle-Stil.
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [accent.blended(withFraction: 0.15, of: .white) ?? accent, accent])?
        .draw(in: bg, angle: -90)

    // Vier Kacheln, eine hervorgehoben – Anspielung auf das Dashboard-Raster.
    let pad = s * 0.24
    let gap = s * 0.055
    let tile = (s - pad * 2 - gap) / 2
    let cells: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 1, 1.0), (1, 1, 0.55), (0, 0, 0.55), (1, 0, 0.8)
    ]
    for (cx, cy, alpha) in cells {
        let r = NSRect(x: pad + cx * (tile + gap), y: pad + cy * (tile + gap), width: tile, height: tile)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: tile * 0.22, yRadius: tile * 0.22).fill()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG-Erzeugung fehlgeschlagen")
    }
    return png
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let data = render(size)
    try! data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    if true {
        let double = render(size * 2)
        try! double.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("iconset geschrieben")
