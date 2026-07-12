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

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_app_icon.swift <iconset-output-dir>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let graphite = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.15, alpha: 1)
let mist = NSColor(srgbRed: 0.94, green: 0.96, blue: 0.985, alpha: 1)
let iceBlue = NSColor(srgbRed: 0.48, green: 0.78, blue: 1, alpha: 1)

for spec in specs {
    let image = NSImage(size: NSSize(width: spec.size, height: spec.size))
    image.lockFocus()

    let canvas = NSRect(origin: .zero, size: image.size)
    NSGraphicsContext.current?.imageInterpolation = .high

    let backgroundInset = spec.size * 0.065
    let backgroundRect = canvas.insetBy(dx: backgroundInset, dy: backgroundInset)
    let backgroundRadius = spec.size * 0.22
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: backgroundRadius,
        yRadius: backgroundRadius
    )
    graphite.setFill()
    backgroundPath.fill()

    let highlightRect = NSRect(
        x: backgroundRect.minX + (spec.size * 0.08),
        y: backgroundRect.midY + (spec.size * 0.1),
        width: backgroundRect.width * 0.74,
        height: backgroundRect.height * 0.26
    )
    let highlight = NSBezierPath(
        roundedRect: highlightRect,
        xRadius: spec.size * 0.08,
        yRadius: spec.size * 0.08
    )
    mist.withAlphaComponent(0.06).setFill()
    highlight.fill()

    let bubbleRect = NSRect(
        x: spec.size * 0.23,
        y: spec.size * 0.31,
        width: spec.size * 0.54,
        height: spec.size * 0.36
    )
    let bubblePath = NSBezierPath(
        roundedRect: bubbleRect,
        xRadius: spec.size * 0.11,
        yRadius: spec.size * 0.11
    )
    mist.withAlphaComponent(0.16).setFill()
    bubblePath.fill()
    bubblePath.lineWidth = max(1.5, spec.size * 0.013)
    mist.withAlphaComponent(0.7).setStroke()
    bubblePath.stroke()

    let tailSize = spec.size * 0.092
    let tailCenter = NSPoint(x: spec.size * 0.36, y: spec.size * 0.285)
    let tailPath = NSBezierPath()
    tailPath.move(to: NSPoint(x: tailCenter.x, y: tailCenter.y + (tailSize / 2)))
    tailPath.line(to: NSPoint(x: tailCenter.x + (tailSize / 2), y: tailCenter.y))
    tailPath.line(to: NSPoint(x: tailCenter.x, y: tailCenter.y - (tailSize / 2)))
    tailPath.line(to: NSPoint(x: tailCenter.x - (tailSize / 2), y: tailCenter.y))
    mist.withAlphaComponent(0.16).setFill()
    tailPath.fill()
    tailPath.lineWidth = max(1.3, spec.size * 0.011)
    mist.withAlphaComponent(0.7).setStroke()
    tailPath.stroke()

    let barWidth = max(3, spec.size * 0.05)
    let barSpacing = spec.size * 0.03
    let barHeights: [CGFloat] = [0.18, 0.34, 0.25]
    let startX = spec.size * 0.42
    let centerY = spec.size * 0.49
    for (index, barHeightFactor) in barHeights.enumerated() {
        let height = spec.size * barHeightFactor
        let rect = NSRect(
            x: startX + CGFloat(index) * (barWidth + barSpacing),
            y: centerY - (height / 2),
            width: barWidth,
            height: height
        )
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        let color = index == 1 ? iceBlue : mist.withAlphaComponent(0.78)
        color.setFill()
        path.fill()
    }

    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("failed to render \(spec.filename)\n", stderr)
        exit(1)
    }

    try pngData.write(to: outputDirectory.appendingPathComponent(spec.filename))
}
