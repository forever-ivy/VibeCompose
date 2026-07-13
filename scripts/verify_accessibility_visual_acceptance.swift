import AppKit
import Foundation

struct AccessibilitySurfaceImage {
    let name: String
    let rep: NSBitmapImageRep

    var width: Int { rep.pixelsWide }
    var height: Int { rep.pixelsHigh }
}

enum AccessibilityVisualVerificationError:
    Error,
    CustomStringConvertible
{
    case usage
    case unreadable(String)
    case tooSmall(String, Int, Int)
    case unexpectedBackingScale(String, Int, Int, Int)
    case tooUniform(String, Int)
    case geometryMismatch(String, Int, Int, Int, Int)
    case insufficientDifference(String, Int)
    case weakerEdgeContrast(String, Double, Double, Double)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_accessibility_visual_acceptance.swift artifact-directory"
        case .unreadable(let path):
            return "Could not read accessibility visual snapshot: \(path)"
        case .tooSmall(let name, let width, let height):
            return "\(name) is unexpectedly small: \(width)x\(height)"
        case .unexpectedBackingScale(
            let name,
            let width,
            let height,
            let scale
        ):
            return "\(name) is not normalized to a \(scale)x backing scale: \(width)x\(height)"
        case .tooUniform(let name, let buckets):
            return "\(name) is too visually uniform: \(buckets) sampled color buckets"
        case .geometryMismatch(
            let name,
            let baselineWidth,
            let baselineHeight,
            let contrastWidth,
            let contrastHeight
        ):
            return "\(name) changed geometry from \(baselineWidth)x\(baselineHeight) to \(contrastWidth)x\(contrastHeight)"
        case .insufficientDifference(let name, let changedPixels):
            return "\(name) Increase Contrast changed only \(changedPixels) pixels"
        case .weakerEdgeContrast(
            let name,
            let baselineContrast,
            let contrastContrast,
            let tolerance
        ):
            return String(
                format:
                    "%@ local edge contrast decreased from %.5f to %.5f "
                    + "(tolerance %.5f)",
                name,
                baselineContrast,
                contrastContrast,
                tolerance
            )
        }
    }
}

let expectedSurfaces = [
    "settings-account",
    "settings-dictation",
    "settings-appearance",
    "settings-ai-polish",
    "settings-context",
    "settings-paste",
    "settings-privacy",
    "settings-advanced",
    "onboarding-welcome",
    "onboarding-connect",
    "onboarding-microphone",
    "onboarding-practice",
    "history",
    "terminology",
    "quick-add",
]

func load(path: String, name: String) throws -> AccessibilitySurfaceImage {
    guard
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let rep = NSBitmapImageRep(data: data)
    else {
        throw AccessibilityVisualVerificationError.unreadable(path)
    }
    return AccessibilitySurfaceImage(name: name, rep: rep)
}

func normalizedLogicalImage(
    _ image: AccessibilitySurfaceImage,
    backingScale: Int
) throws -> AccessibilitySurfaceImage {
    guard
        backingScale > 0,
        image.width.isMultiple(of: backingScale),
        image.height.isMultiple(of: backingScale)
    else {
        throw AccessibilityVisualVerificationError.unexpectedBackingScale(
            image.name,
            image.width,
            image.height,
            backingScale
        )
    }

    let targetWidth = image.width / backingScale
    let targetHeight = image.height / backingScale
    guard
        let sourceImage = image.rep.cgImage,
        let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space:
                CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw AccessibilityVisualVerificationError.unreadable(image.name)
    }

    context.interpolationQuality = .high
    context.draw(
        sourceImage,
        in: CGRect(
            x: 0,
            y: 0,
            width: targetWidth,
            height: targetHeight
        )
    )
    guard let normalizedImage = context.makeImage() else {
        throw AccessibilityVisualVerificationError.unreadable(image.name)
    }

    return AccessibilitySurfaceImage(
        name: image.name,
        rep: NSBitmapImageRep(cgImage: normalizedImage)
    )
}

func luminance(_ color: NSColor) -> Double {
    (0.2126 * Double(color.redComponent))
        + (0.7152 * Double(color.greenComponent))
        + (0.0722 * Double(color.blueComponent))
}

func sampledColors(
    in image: AccessibilitySurfaceImage
) -> [NSColor] {
    let stepX = max(1, image.width / 220)
    let stepY = max(1, image.height / 160)
    var colors: [NSColor] = []
    colors.reserveCapacity(40_000)

    for y in stride(from: 0, to: image.height, by: stepY) {
        for x in stride(from: 0, to: image.width, by: stepX) {
            guard
                let color = image.rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB),
                color.alphaComponent > 0.05
            else {
                continue
            }
            colors.append(color)
        }
    }
    return colors
}

func sampledColorBucketCount(_ colors: [NSColor]) -> Int {
    var buckets = Set<Int>()
    for color in colors {
        let red = Int((color.redComponent * 15).rounded())
        let green = Int((color.greenComponent * 15).rounded())
        let blue = Int((color.blueComponent * 15).rounded())
        let alpha = Int((color.alphaComponent * 15).rounded())
        buckets.insert((red << 12) | (green << 8) | (blue << 4) | alpha)
    }
    return buckets.count
}

func luminanceSpread(_ colors: [NSColor]) -> Double {
    guard !colors.isEmpty else {
        return 0
    }
    let luminances = colors.map(luminance)
    let mean = luminances.reduce(0, +) / Double(luminances.count)
    let variance = luminances.reduce(0) {
        $0 + (($1 - mean) * ($1 - mean))
    } / Double(luminances.count)
    return sqrt(variance)
}

func localEdgeContrast(
    in image: AccessibilitySurfaceImage
) -> Double {
    guard image.width > 1, image.height > 1 else {
        return 0
    }

    let step = max(1, min(image.width, image.height) / 500)
    var total = 0.0
    var edgeCount = 0

    for y in stride(from: 0, to: image.height - step, by: step) {
        for x in stride(from: 0, to: image.width - step, by: step) {
            guard
                let center = image.rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB),
                let right = image.rep.colorAt(x: x + step, y: y)?
                    .usingColorSpace(.deviceRGB),
                let down = image.rep.colorAt(x: x, y: y + step)?
                    .usingColorSpace(.deviceRGB),
                center.alphaComponent > 0.05,
                right.alphaComponent > 0.05,
                down.alphaComponent > 0.05
            else {
                continue
            }

            total += abs(luminance(center) - luminance(right))
            total += abs(luminance(center) - luminance(down))
            edgeCount += 2
        }
    }

    guard edgeCount > 0 else {
        return 0
    }
    return total / Double(edgeCount)
}

func changedPixelCount(
    from baseline: AccessibilitySurfaceImage,
    to contrast: AccessibilitySurfaceImage
) -> Int {
    var count = 0
    let width = min(baseline.width, contrast.width)
    let height = min(baseline.height, contrast.height)

    for y in 0..<height {
        for x in 0..<width {
            guard
                let left = baseline.rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB),
                let right = contrast.rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
            else {
                continue
            }
            let distance =
                abs(left.redComponent - right.redComponent)
                + abs(left.greenComponent - right.greenComponent)
                + abs(left.blueComponent - right.blueComponent)
                + abs(left.alphaComponent - right.alphaComponent)
            if distance > 0.06 {
                count += 1
            }
        }
    }
    return count
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1 else {
        throw AccessibilityVisualVerificationError.usage
    }

    let root = URL(fileURLWithPath: args[0], isDirectory: true)
    let normalizedBackingScale = 2
    let minimumChangedPixels = 400
    let minimumColorBuckets = 12
    let absoluteEdgeTolerance = 0.0001
    let relativeEdgeTolerance = 0.01

    for surface in expectedSurfaces {
        let baselineSource = try load(
            path: root
                .appendingPathComponent("\(surface)-baseline.png")
                .path,
            name: "\(surface)-baseline"
        )
        let contrastSource = try load(
            path: root
                .appendingPathComponent(
                    "\(surface)-increase-contrast.png"
                )
                .path,
            name: "\(surface)-increase-contrast"
        )

        for image in [baselineSource, contrastSource] {
            guard image.width >= 900, image.height >= 650 else {
                throw AccessibilityVisualVerificationError.tooSmall(
                    image.name,
                    image.width,
                    image.height
                )
            }
        }
        guard
            baselineSource.width == contrastSource.width,
            baselineSource.height == contrastSource.height
        else {
            throw AccessibilityVisualVerificationError.geometryMismatch(
                surface,
                baselineSource.width,
                baselineSource.height,
                contrastSource.width,
                contrastSource.height
            )
        }

        let baseline = try normalizedLogicalImage(
            baselineSource,
            backingScale: normalizedBackingScale
        )
        let contrast = try normalizedLogicalImage(
            contrastSource,
            backingScale: normalizedBackingScale
        )

        let baselineColors = sampledColors(in: baseline)
        let contrastColors = sampledColors(in: contrast)
        for (image, colors) in [
            (baseline, baselineColors),
            (contrast, contrastColors),
        ] {
            let buckets = sampledColorBucketCount(colors)
            guard buckets >= minimumColorBuckets else {
                throw AccessibilityVisualVerificationError.tooUniform(
                    image.name,
                    buckets
                )
            }
        }

        let changedPixels = changedPixelCount(
            from: baseline,
            to: contrast
        )
        guard changedPixels >= minimumChangedPixels else {
            throw AccessibilityVisualVerificationError
                .insufficientDifference(surface, changedPixels)
        }

        let baselineSpread = luminanceSpread(baselineColors)
        let contrastSpread = luminanceSpread(contrastColors)
        let baselineEdgeContrast = localEdgeContrast(in: baseline)
        let contrastEdgeContrast = localEdgeContrast(in: contrast)
        let edgeTolerance = max(
            absoluteEdgeTolerance,
            baselineEdgeContrast * relativeEdgeTolerance
        )
        guard
            contrastEdgeContrast + edgeTolerance
                >= baselineEdgeContrast
        else {
            throw AccessibilityVisualVerificationError.weakerEdgeContrast(
                surface,
                baselineEdgeContrast,
                contrastEdgeContrast,
                edgeTolerance
            )
        }

        print(
            "\(surface): source "
                + "\(baselineSource.width)x\(baselineSource.height), "
                + "logical \(baseline.width)x\(baseline.height), "
                + "\(changedPixels) changed pixels, "
                + String(
                    format:
                        "local edge contrast %.5f -> %.5f, ",
                    baselineEdgeContrast,
                    contrastEdgeContrast
                )
                + String(
                    format:
                        "luminance spread diagnostic %.5f -> %.5f",
                    baselineSpread,
                    contrastSpread
                )
        )
    }

    print("OpenWhisper accessibility visual acceptance passed.")
} catch {
    fputs("Accessibility visual acceptance failed: \(error)\n", stderr)
    exit(1)
}
