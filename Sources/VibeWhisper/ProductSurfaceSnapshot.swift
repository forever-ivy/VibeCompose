import AppKit
import CoreGraphics
import Foundation

enum ProductSurfaceSnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case visuallyEmptyWindowCapture
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The VibeWhisper product window has no content view to capture."
        case .bitmapUnavailable:
            return "The VibeWhisper product window could not create a bitmap snapshot."
        case .visuallyEmptyWindowCapture:
            return "The VibeWhisper window capture was visually empty."
        case .pngEncodingFailed:
            return "The VibeWhisper product window could not encode its snapshot as PNG."
        }
    }
}

@MainActor
enum ProductSurfaceSnapshot {
    static let normalizedBackingScale: CGFloat = 2

    static func write(window: NSWindow?, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let window {
            prepareForDeterministicCapture(window)
        }

        if
            let window,
            window.windowNumber > 0,
            let windowImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ),
            let normalizedImage = normalizedWindowImage(
                windowImage,
                pointSize: window.frame.size
            ),
            isVisuallyPopulated(normalizedImage),
            let png = NSBitmapImageRep(cgImage: normalizedImage)
                .representation(using: .png, properties: [:])
        {
            try png.write(to: url, options: [.atomic])
            return
        }

        guard let contentView = window?.contentView else {
            throw ProductSurfaceSnapshotError.missingContentView
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        let bounds = contentView.bounds
        guard
            bounds.width > 0,
            bounds.height > 0,
            let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            throw ProductSurfaceSnapshotError.bitmapUnavailable
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)
        guard
            let sourceImage = bitmap.cgImage,
            let normalizedImage = normalizedWindowImage(
                sourceImage,
                pointSize: bounds.size
            )
        else {
            throw ProductSurfaceSnapshotError.pngEncodingFailed
        }
        guard isVisuallyPopulated(normalizedImage) else {
            throw ProductSurfaceSnapshotError.visuallyEmptyWindowCapture
        }
        guard
            let png = NSBitmapImageRep(cgImage: normalizedImage)
                .representation(using: .png, properties: [:])
        else {
            throw ProductSurfaceSnapshotError.pngEncodingFailed
        }
        try png.write(to: url, options: [.atomic])
    }

    static func isVisuallyPopulated(
        _ image: CGImage,
        minimumDistinctBuckets: Int = 2
    ) -> Bool {
        guard minimumDistinctBuckets > 0 else {
            return true
        }
        guard
            let dataProvider = image.dataProvider,
            let data = dataProvider.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return false
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bitsPerPixel = image.bitsPerPixel
        let bytesPerPixel = bitsPerPixel / 8
        guard
            width > 0,
            height > 0,
            bytesPerPixel >= 3,
            bytesPerRow >= width * bytesPerPixel
        else {
            return false
        }

        let sampleColumns = min(24, width)
        let sampleRows = min(18, height)
        var buckets = Set<Int>()
        for row in 0..<sampleRows {
            let y = min(
                height - 1,
                ((row * 2 + 1) * height) / (sampleRows * 2)
            )
            for column in 0..<sampleColumns {
                let x = min(
                    width - 1,
                    ((column * 2 + 1) * width) / (sampleColumns * 2)
                )
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let bucket =
                    ((red >> 5) << 6)
                    | ((green >> 5) << 3)
                    | (blue >> 5)
                buckets.insert(bucket)
                if buckets.count >= minimumDistinctBuckets {
                    return true
                }
            }
        }
        return false
    }

    static func centeredCaptureFrame(
        windowFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        guard
            windowFrame.width > 0,
            windowFrame.height > 0,
            visibleFrame.width > 0,
            visibleFrame.height > 0
        else {
            return windowFrame
        }

        let desiredX = visibleFrame.midX - (windowFrame.width / 2)
        let desiredY = visibleFrame.midY - (windowFrame.height / 2)
        let maximumX = max(
            visibleFrame.minX,
            visibleFrame.maxX - windowFrame.width
        )
        let maximumY = max(
            visibleFrame.minY,
            visibleFrame.maxY - windowFrame.height
        )

        var frame = windowFrame
        frame.origin = NSPoint(
            x: min(max(desiredX, visibleFrame.minX), maximumX),
            y: min(max(desiredY, visibleFrame.minY), maximumY)
        )
        return frame
    }

    static func normalizedWindowImage(
        _ image: CGImage,
        pointSize: NSSize,
        scale: CGFloat = normalizedBackingScale
    ) -> CGImage? {
        guard
            pointSize.width > 0,
            pointSize.height > 0,
            scale > 0
        else {
            return nil
        }

        let targetWidth = Int((pointSize.width * scale).rounded())
        let targetHeight = Int((pointSize.height * scale).rounded())
        guard targetWidth > 0, targetHeight > 0 else {
            return nil
        }
        if image.width == targetWidth, image.height == targetHeight {
            return image
        }

        guard
            let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace
                    ?? CGColorSpace(name: CGColorSpace.sRGB)
                    ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: targetHeight
            )
        )
        return context.makeImage()
    }

    private static func prepareForDeterministicCapture(_ window: NSWindow) {
        let candidateScreens = NSScreen.screens
        let screen =
            candidateScreens.first(where: {
                $0.visibleFrame.width >= window.frame.width
                    && $0.visibleFrame.height >= window.frame.height
            })
            ?? window.screen
            ?? candidateScreens.first
        guard let screen else {
            return
        }

        let captureFrame = centeredCaptureFrame(
            windowFrame: window.frame,
            visibleFrame: screen.visibleFrame
        )
        if captureFrame.origin != window.frame.origin {
            window.setFrame(captureFrame, display: true)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}
