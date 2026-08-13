#!/usr/bin/swift
//
// Slice one square source image into both app icon sets.
//
//     swift Tools/make-appicon.swift ~/Downloads/dundu-icon.png
//
// The App Store rejects icons carrying an alpha channel, so every slice is
// composited onto opaque white first. iOS takes a single 1024 and masks the
// squircle itself; macOS keeps its own rounding and wants the whole ladder,
// so a source that already has the squircle baked in suits both.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <source.png>\n".utf8))
    exit(1)
}

let sourceURL = URL(fileURLWithPath: args[1])
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iosSet = root.appendingPathComponent("iOS/Assets.xcassets/AppIcon.appiconset")
let macSet = root.appendingPathComponent("macOS/Assets.xcassets/AppIcon.appiconset")

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read image at \(sourceURL.path)\n".utf8))
    exit(1)
}

if image.width != image.height {
    let note = "warning: source is \(image.width)x\(image.height), not square — it will be squashed to fit\n"
    FileHandle.standardError.write(Data(note.utf8))
}

/// Draws the source into a square of `size`, flattened onto white.
func slice(_ size: Int, to url: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(rect)
    context.interpolationQuality = .high
    context.draw(image, in: rect)

    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

try slice(1024, to: iosSet.appendingPathComponent("AppIcon-1024.png"))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try slice(size, to: macSet.appendingPathComponent("AppIcon-\(size).png"))
}

print("iOS   → \(iosSet.path)/AppIcon-1024.png")
print("macOS → \(macSet.path)/AppIcon-{16…1024}.png")
