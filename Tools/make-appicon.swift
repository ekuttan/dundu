#!/usr/bin/swift
//
// Slice one square source image into both app icon sets.
//
//     swift Tools/make-appicon.swift ~/Downloads/dundu-icon.png
//
// The two platforms want opposite things from the same artwork:
//
//   iOS   — a full-bleed opaque square. The system draws the squircle mask
//           itself, and the App Store rejects any alpha channel. Artwork that
//           already carries its own rounded corners has to be cropped to the
//           shape and stretched to the edges, or the system mask cuts inside
//           the drawn corner and leaves pale slivers.
//   macOS — the shape itself, with transparency around it. The Dock does no
//           masking and expects the standard margin, so the squircle is drawn
//           at 80% of the canvas with clear space on all sides.
//
// So the source is measured once, cropped to its artwork, and then treated
// differently per platform.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <source.png>\n".utf8))
    exit(1)
}

let sourceURL = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
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
    let note = "warning: source is \(image.width)x\(image.height), not square\n"
    FileHandle.standardError.write(Data(note.utf8))
}

// MARK: - Measure the artwork

/// Reads the source into straight RGBA so pixels can be compared.
func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
    let width = image.width, height = image.height
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (buffer, width, height)
}

guard let (data, width, height) = pixels(of: image) else {
    FileHandle.standardError.write(Data("cannot rasterise the source\n".utf8))
    exit(1)
}

func colorAt(_ x: Int, _ y: Int) -> CGColor {
    let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
    return CGColor(
        red: Double(data[i]) / 255,
        green: Double(data[i + 1]) / 255,
        blue: Double(data[i + 2]) / 255,
        alpha: 1
    )
}

func isBackdrop(_ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    // White, or transparent — either way it is the plate the shape sits on.
    return data[i + 3] < 8 || (data[i] > 248 && data[i + 1] > 248 && data[i + 2] > 248)
}

/// How far in from the corner the artwork's own rounding starts, measured
/// along the top edge and expressed as a fraction of the width.
let cornerInset: Int = {
    for x in 0..<width where !isBackdrop(x, 0) { return x }
    return 0
}()
let cornerRatio = Double(cornerInset) / Double(width)

/// Apple's corner radius for the icon grid. Artwork rounded *more* than this
/// leaves pale slivers when the system mask cuts outside its corner.
let appleCornerRatio = 0.2237

print(String(format: "source corner radius: %.4f of width (Apple masks at %.4f)",
             cornerRatio, appleCornerRatio))

/// The artwork's own gradient, sampled just inside its straight edges at the
/// two ends of the diagonal. Painting the full square with this first means
/// the corners are filled with the colour that belongs there, instead of the
/// white the artwork was exported on.
let gradientStart = colorAt(cornerInset + 4, 2)
let gradientEnd = colorAt(width - cornerInset - 4, height - 3)

// MARK: - Draw

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func makeContext(_ size: Int, opaque: Bool) -> CGContext? {
    CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
    )
}

/// Lays the artwork's gradient across the whole square, then draws the
/// artwork clipped to its own rounded corners so the white plate never
/// appears. Everything downstream works from this.
func flattened(_ size: Int) -> CGImage? {
    guard let context = makeContext(size, opaque: true) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let gradient = CGGradient(
        colorsSpace: space,
        colors: [gradientStart, gradientEnd] as CFArray,
        locations: [0, 1]
       ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    } else {
        context.setFillColor(gradientStart)
        context.fill(rect)
    }

    context.saveGState()
    // Cut a little *inside* the artwork's own corner. Clipping exactly on it
    // leaves the anti-aliased pixels where the shape met its white plate, and
    // those read as a pale hairline tracing the corner.
    let radius = Double(size) * cornerRatio * 1.06
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    context.restoreGState()

    return context.makeImage()
}

/// iOS: full bleed, opaque, no alpha. The system draws the squircle.
func writeIOS(_ size: Int, to url: URL) throws {
    guard let output = flattened(size) else { throw CocoaError(.fileWriteUnknown) }
    try write(output, to: url)
}

/// macOS: the squircle at 80% of the canvas, transparent around it — the Dock
/// does no masking and expects the standard margin.
func writeMac(_ size: Int, to url: URL) throws {
    let supersample = max(size, 512)
    guard let art = flattened(supersample),
          let context = makeContext(size, opaque: false) else { throw CocoaError(.fileWriteUnknown) }
    let side = (Double(size) * 0.8).rounded()
    let origin = ((Double(size) - side) / 2).rounded()
    let rect = CGRect(x: origin, y: origin, width: side, height: side)

    context.interpolationQuality = .high
    context.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: side * appleCornerRatio,
        cornerHeight: side * appleCornerRatio,
        transform: nil
    ))
    context.clip()
    context.draw(art, in: rect)

    guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    try write(output, to: url)
}

try writeIOS(1024, to: iosSet.appendingPathComponent("AppIcon-1024.png"))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try writeMac(size, to: macSet.appendingPathComponent("AppIcon-\(size).png"))
}

print("iOS   → AppIcon-1024.png (full bleed, opaque)")
print("macOS → AppIcon-{16…1024}.png (squircle at 80%, transparent margin)")
