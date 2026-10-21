import AppKit

// Icona vettoriale del prototipo: nessun asset o marchio di servizi esterni.
let side = 1024
let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.045, green: 0.10, blue: 0.14, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
NSColor(srgbRed: 0.48, green: 0.87, blue: 0.95, alpha: 1).setFill()
let note = NSBezierPath()
note.move(to: NSPoint(x: 415, y: 300))
note.line(to: NSPoint(x: 415, y: 720))
note.line(to: NSPoint(x: 730, y: 780))
note.line(to: NSPoint(x: 730, y: 390))
note.line(to: NSPoint(x: 660, y: 390))
note.line(to: NSPoint(x: 660, y: 625))
note.line(to: NSPoint(x: 485, y: 590))
note.line(to: NSPoint(x: 485, y: 300))
note.close()
note.fill()
NSBezierPath(ovalIn: NSRect(x: 285, y: 235, width: 200, height: 140)).fill()
NSBezierPath(ovalIn: NSRect(x: 530, y: 320, width: 200, height: 140)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
  to: URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
