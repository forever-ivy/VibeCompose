#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: CGFloat
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", size: 16),
    .init(filename: "icon_16x16@2x.png", size: 32),
    .init(filename: "icon_32x32.png", size: 32),
    .init(filename: "icon_32x32@2x.png", size: 64),
    .init(filename: "icon_128x128.png", size: 128),
    .init(filename: "icon_128x128@2x.png", size: 256),
    .init(filename: "icon_256x256.png", size: 256),
    .init(filename: "icon_256x256@2x.png", size: 512),
    .init(filename: "icon_512x512.png", size: 512),
    .init(filename: "icon_512x512@2x.png", size: 1024),
]

guard CommandLine.arguments.count == 4 else {
    fputs(
        "usage: render_app_icon.swift <logo-source.png> <iconset-output-dir> <status-template-output.png>\n",
        stderr
    )
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[2],
    isDirectory: true
)
let statusTemplateURL = URL(
    fileURLWithPath: CommandLine.arguments[3]
)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("failed to load logo source at \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)
try FileManager.default.createDirectory(
    at: statusTemplateURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

func squareCrop(
    for image: NSImage,
    insetFraction: CGFloat
) -> NSRect {
    let side = min(image.size.width, image.size.height)
    let inset = side * insetFraction
    return NSRect(
        x: (image.size.width - side) / 2 + inset,
        y: (image.size.height - side) / 2 + inset,
        width: side - (inset * 2),
        height: side - (inset * 2)
    )
}

func pngData(for image: NSImage) -> Data? {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }
    return bitmap.representation(
        using: .png,
        properties: [:]
    )
}

func renderApplicationIcon(
    size: CGFloat,
    sourceImage: NSImage
) -> NSImage {
    let image = NSImage(
        size: NSSize(width: size, height: size)
    )
    image.lockFocus()

    let canvas = NSRect(origin: .zero, size: image.size)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    canvas.fill()

    let backgroundInset = size * 0.055
    let backgroundRect = canvas.insetBy(
        dx: backgroundInset,
        dy: backgroundInset
    )
    let backgroundRadius = size * 0.205
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: backgroundRadius,
        yRadius: backgroundRadius
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = max(0.75, size * 0.034)
    shadow.shadowOffset = NSSize(
        width: 0,
        height: -size * 0.012
    )
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.set()
    NSColor.white.setFill()
    backgroundPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    backgroundPath.addClip()
    sourceImage.draw(
        in: backgroundRect,
        from: squareCrop(
            for: sourceImage,
            insetFraction: 0.067
        ),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [
            .interpolation: NSImageInterpolation.high,
        ]
    )
    NSGraphicsContext.restoreGraphicsState()

    backgroundPath.lineWidth = max(0.45, size * 0.0016)
    NSColor.black.withAlphaComponent(0.075).setStroke()
    backgroundPath.stroke()

    image.unlockFocus()
    return image
}

for spec in specs {
    let image = renderApplicationIcon(
        size: spec.size,
        sourceImage: sourceImage
    )
    guard let data = pngData(for: image) else {
        fputs("failed to render \(spec.filename)\n", stderr)
        exit(1)
    }
    try data.write(
        to: outputDirectory.appendingPathComponent(
            spec.filename
        )
    )
}

func smoothStep(_ value: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - (2 * clamped))
}

func renderStatusTemplate(
    sourceImage: NSImage
) -> NSBitmapImageRep? {
    let pixelSize = 72
    guard
        let sourceBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let bitmapContext = NSGraphicsContext(
            bitmapImageRep: sourceBitmap
        )
    else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = bitmapContext
    let rasterBounds = NSRect(
        x: 0,
        y: 0,
        width: pixelSize,
        height: pixelSize
    )
    NSColor.white.setFill()
    rasterBounds.fill()
    NSGraphicsContext.current?.imageInterpolation = .high
    sourceImage.draw(
        in: rasterBounds.insetBy(dx: 4, dy: 4),
        from: squareCrop(
            for: sourceImage,
            insetFraction: 0.142
        ),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [
            .interpolation: NSImageInterpolation.high,
        ]
    )
    bitmapContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard
        let outputBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        return nil
    }

    guard
        let sourceBytes = sourceBitmap.bitmapData,
        let outputBytes = outputBitmap.bitmapData
    else {
        return nil
    }

    for y in 0..<pixelSize {
        for x in 0..<pixelSize {
            let sourceOffset =
                (y * sourceBitmap.bytesPerRow)
                + (x * sourceBitmap.samplesPerPixel)
            let red = CGFloat(sourceBytes[sourceOffset]) / 255
            let green = CGFloat(sourceBytes[sourceOffset + 1]) / 255
            let blue = CGFloat(sourceBytes[sourceOffset + 2]) / 255
            let maximum = max(red, max(green, blue))
            let minimum = min(red, min(green, blue))
            let saturation = maximum - minimum
            let alpha = smoothStep(
                (saturation - 0.035) / 0.22
            )
            let outputOffset =
                (y * outputBitmap.bytesPerRow)
                + (x * outputBitmap.samplesPerPixel)
            outputBytes[outputOffset] = 0
            outputBytes[outputOffset + 1] = 0
            outputBytes[outputOffset + 2] = 0
            outputBytes[outputOffset + 3] = UInt8(
                min(255, max(0, Int((alpha * 255).rounded())))
            )
        }
    }

    return outputBitmap
}

guard
    let statusTemplate = renderStatusTemplate(
        sourceImage: sourceImage
    ),
    let statusData = statusTemplate.representation(
        using: .png,
        properties: [:]
    )
else {
    fputs("failed to render status bar template icon\n", stderr)
    exit(1)
}

try statusData.write(to: statusTemplateURL)
