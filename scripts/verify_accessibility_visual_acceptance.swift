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
    case tooUniform(String, Int)
    case geometryMismatch(String, Int, Int, Int, Int)
    case insufficientDifference(String, Int)
    case weakerContrast(String, Double, Double)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_accessibility_visual_acceptance.swift artifact-directory"
        case .unreadable(let path):
            return "Could not read accessibility visual snapshot: \(path)"
        case .tooSmall(let name, let width, let height):
            return "\(name) is unexpectedly small: \(width)x\(height)"
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
        case .weakerContrast(
            let name,
            let baselineSpread,
            let contrastSpread
        ):
            return "\(name) luminance spread decreased from \(baselineSpread) to \(contrastSpread)"
        }
    }
}

let expectedSurfaces = [
    "settings-account",
    "settings-dictation",
    "settings-ai-polish",
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
    let luminances = colors.map {
        (0.2126 * Double($0.redComponent))
            + (0.7152 * Double($0.greenComponent))
            + (0.0722 * Double($0.blueComponent))
    }
    let mean = luminances.reduce(0, +) / Double(luminances.count)
    let variance = luminances.reduce(0) {
        $0 + (($1 - mean) * ($1 - mean))
    } / Double(luminances.count)
    return sqrt(variance)
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
    let minimumChangedPixels = 400
    let minimumColorBuckets = 12
    let luminanceTolerance = 0.0005

    for surface in expectedSurfaces {
        let baseline = try load(
            path: root
                .appendingPathComponent("\(surface)-baseline.png")
                .path,
            name: "\(surface)-baseline"
        )
        let contrast = try load(
            path: root
                .appendingPathComponent(
                    "\(surface)-increase-contrast.png"
                )
                .path,
            name: "\(surface)-increase-contrast"
        )

        for image in [baseline, contrast] {
            guard image.width >= 900, image.height >= 650 else {
                throw AccessibilityVisualVerificationError.tooSmall(
                    image.name,
                    image.width,
                    image.height
                )
            }
        }
        guard
            baseline.width == contrast.width,
            baseline.height == contrast.height
        else {
            throw AccessibilityVisualVerificationError.geometryMismatch(
                surface,
                baseline.width,
                baseline.height,
                contrast.width,
                contrast.height
            )
        }

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
        guard contrastSpread + luminanceTolerance >= baselineSpread else {
            throw AccessibilityVisualVerificationError.weakerContrast(
                surface,
                baselineSpread,
                contrastSpread
            )
        }

        print(
            "\(surface): \(baseline.width)x\(baseline.height), "
                + "\(changedPixels) changed pixels, "
                + String(
                    format:
                        "luminance spread %.5f -> %.5f",
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
