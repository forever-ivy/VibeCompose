import AppKit
import CoreGraphics
import Testing
@testable import OpenWhisper

@MainActor
@Test
func productSurfaceSnapshotNormalizesOneXInputToStableTwoXOutput() throws {
    let sourceContext = try #require(
        CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    sourceContext.setFillColor(
        NSColor.systemBlue.usingColorSpace(.deviceRGB)?.cgColor
            ?? NSColor.blue.cgColor
    )
    sourceContext.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    let sourceImage = try #require(sourceContext.makeImage())

    let normalized = try #require(
        ProductSurfaceSnapshot.normalizedWindowImage(
            sourceImage,
            pointSize: NSSize(width: 3, height: 2)
        )
    )

    #expect(ProductSurfaceSnapshot.normalizedBackingScale == 2)
    #expect(normalized.width == 6)
    #expect(normalized.height == 4)
}

@MainActor
@Test
func productSurfaceSnapshotRejectsInvalidLogicalGeometry() throws {
    let sourceContext = try #require(
        CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    let sourceImage = try #require(sourceContext.makeImage())

    #expect(
        ProductSurfaceSnapshot.normalizedWindowImage(
            sourceImage,
            pointSize: .zero
        ) == nil
    )
}

@MainActor
@Test
func productSurfaceSnapshotRejectsUniformWindowImages() throws {
    let uniformContext = try #require(
        CGContext(
            data: nil,
            width: 40,
            height: 30,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    uniformContext.setFillColor(NSColor.black.cgColor)
    uniformContext.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    let uniformImage = try #require(uniformContext.makeImage())
    #expect(ProductSurfaceSnapshot.isVisuallyPopulated(uniformImage) == false)

    let populatedContext = try #require(
        CGContext(
            data: nil,
            width: 40,
            height: 30,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    populatedContext.setFillColor(NSColor.black.cgColor)
    populatedContext.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    populatedContext.setFillColor(NSColor.white.cgColor)
    populatedContext.fill(CGRect(x: 20, y: 0, width: 20, height: 30))
    let populatedImage = try #require(populatedContext.makeImage())
    #expect(ProductSurfaceSnapshot.isVisuallyPopulated(populatedImage))
}

@MainActor
@Test
func productSurfaceSnapshotCentersCaptureInsideVisibleScreen() {
    let frame = ProductSurfaceSnapshot.centeredCaptureFrame(
        windowFrame: NSRect(x: -500, y: 1_200, width: 900, height: 709),
        visibleFrame: NSRect(x: 0, y: 25, width: 1_440, height: 875)
    )

    #expect(frame.origin.x == 270)
    #expect(frame.origin.y == 108)
    #expect(frame.maxX <= 1_440)
    #expect(frame.maxY <= 900)
    #expect(frame.minX >= 0)
    #expect(frame.minY >= 25)
}
