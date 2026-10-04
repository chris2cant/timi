import AppKit
import Foundation

let sourceURL = URL(fileURLWithPath: "artwork/AppIcon.svg")
let outputDirectory = URL(
  fileURLWithPath: "Timi/Assets.xcassets/AppIcon.appiconset",
  isDirectory: true
)

let variants: [(filename: String, pixels: Int)] = [
  ("AppIcon-16.png", 16),
  ("AppIcon-16@2x.png", 32),
  ("AppIcon-32.png", 32),
  ("AppIcon-32@2x.png", 64),
  ("AppIcon-128.png", 128),
  ("AppIcon-128@2x.png", 256),
  ("AppIcon-256.png", 256),
  ("AppIcon-256@2x.png", 512),
  ("AppIcon-512.png", 512),
  ("AppIcon-512@2x.png", 1_024),
]

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
  fatalError("Unable to load \(sourceURL.path)")
}

for variant in variants {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: variant.pixels,
    pixelsHigh: variant.pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create the \(variant.pixels)-pixel bitmap")
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels),
    from: .zero,
    operation: .copy,
    fraction: 1
  )
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode \(variant.filename)")
  }
  try data.write(to: outputDirectory.appendingPathComponent(variant.filename))
}
