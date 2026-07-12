import AppKit
import CoreGraphics
import Foundation

enum ProductSurfaceSnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The OpenWhisper product window has no content view to capture."
        case .bitmapUnavailable:
            return "The OpenWhisper product window could not create a bitmap snapshot."
        case .pngEncodingFailed:
            return "The OpenWhisper product window could not encode its snapshot as PNG."
        }
    }
}

@MainActor
enum ProductSurfaceSnapshot {
    static func write(window: NSWindow?, to url: URL) throws {
        if
            let window,
            window.windowNumber > 0,
            let windowImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ),
            let png = NSBitmapImageRep(cgImage: windowImage)
                .representation(using: .png, properties: [:])
        {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
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
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ProductSurfaceSnapshotError.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url, options: [.atomic])
    }
}
