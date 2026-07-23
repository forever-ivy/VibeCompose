import AppKit
import Foundation

struct LoadedImage {
    let name: String
    let rep: NSBitmapImageRep

    var width: Int { rep.pixelsWide }
    var height: Int { rep.pixelsHigh }
}

enum VerificationError: Error, CustomStringConvertible {
    case usage
    case unreadableImage(String)
    case missingHud(String, Int)
    case duplicateState(String, String, Int)
    case unstablePrimaryGeometry(String, Int, Int, Int, Int)
    case accessibilityVariantGeometryMismatch(String, String, Int, Int, Int, Int)
    case insufficientAccessibilityDifference(String, String, Int)
    case unstableReducedMotion(Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_visual_acceptance.swift recording processing result paste-sent copied error retryable-error reduced-motion reduced-motion-followup increase-contrast"
        case .unreadableImage(let path):
            return "Could not read screenshot: \(path)"
        case .missingHud(let state, let visiblePixels):
            return "\(state) did not contain enough visible HUD pixels (\(visiblePixels) visible)"
        case .duplicateState(let left, let right, let changedPixels):
            return "\(left) and \(right) look too similar as HUD windows (\(changedPixels) changed pixels)"
        case .unstablePrimaryGeometry(
            let state,
            let expectedWidth,
            let expectedHeight,
            let actualWidth,
            let actualHeight
        ):
            return "\(state) changed the primary HUD geometry from \(expectedWidth)x\(expectedHeight) to \(actualWidth)x\(actualHeight)"
        case .accessibilityVariantGeometryMismatch(
            let baseline,
            let variant,
            let baselineWidth,
            let baselineHeight,
            let variantWidth,
            let variantHeight
        ):
            return "\(variant) changed geometry from \(baseline) \(baselineWidth)x\(baselineHeight) to \(variantWidth)x\(variantHeight)"
        case .insufficientAccessibilityDifference(let baseline, let variant, let changedPixels):
            return "\(variant) did not visibly differ enough from \(baseline) (\(changedPixels) changed pixels)"
        case .unstableReducedMotion(let changedPixels):
            return "reduced-motion-static snapshots changed by \(changedPixels) pixels"
        }
    }
}

let expectedStateNames = [
    "recording",
    "processing",
    "result",
    "paste-sent",
    "copied",
    "error",
    "retryable-error",
    "reduced-motion",
    "reduced-motion-followup",
    "increase-contrast",
]

func loadImage(path: String, name: String) throws -> LoadedImage {
    guard
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let rep = NSBitmapImageRep(data: data)
    else {
        throw VerificationError.unreadableImage(path)
    }
    return LoadedImage(name: name, rep: rep)
}

func visiblePixelCount(in image: LoadedImage) -> Int {
    var count = 0

    for y in 0..<image.height {
        for x in 0..<image.width {
            guard
                let color = image.rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                color.alphaComponent > 0.08
            else {
                continue
            }

            count += 1
        }
    }

    return count
}

func changedPixelCount(from left: LoadedImage, to right: LoadedImage) -> Int {
    var count = 0
    let width = min(left.width, right.width)
    let height = min(left.height, right.height)

    for y in 0..<height {
        for x in 0..<width {
            guard
                let leftColor = left.rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                let rightColor = right.rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            else {
                continue
            }

            let distance = abs(leftColor.redComponent - rightColor.redComponent)
                + abs(leftColor.greenComponent - rightColor.greenComponent)
                + abs(leftColor.blueComponent - rightColor.blueComponent)
                + abs(leftColor.alphaComponent - rightColor.alphaComponent)
            if distance > 0.08 {
                count += 1
            }
        }
    }

    return count
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == expectedStateNames.count else {
        throw VerificationError.usage
    }

    let states = try zip(expectedStateNames, args).map { name, path in
        try loadImage(path: path, name: name)
    }
    let minimumVisiblePixels = 2_500
    let minimumChangedPixels = 500
    let minimumControlChangedPixels = 150
    let minimumAccessibilityChangedPixels = 80
    let maximumReducedMotionChangedPixels = 4

    for state in states {
        let visiblePixels = visiblePixelCount(in: state)
        guard visiblePixels >= minimumVisiblePixels else {
            throw VerificationError.missingHud(state.name, visiblePixels)
        }
        print("\(state.name): \(state.width)x\(state.height), \(visiblePixels) visible HUD pixels")
    }

    let primary = states[0]
    for state in states[1...6] {
        guard state.width == primary.width, state.height == primary.height else {
            throw VerificationError.unstablePrimaryGeometry(
                state.name,
                primary.width,
                primary.height,
                state.width,
                state.height
            )
        }
    }
    for index in 0..<6 {
        let left = states[index]
        let right = states[index + 1]
        if left.width != right.width || left.height != right.height {
            print("\(left.name) -> \(right.name): distinct window size \(left.width)x\(left.height) -> \(right.width)x\(right.height)")
            continue
        }

        let changedPixels = changedPixelCount(from: left, to: right)
        let requiredChangedPixels = left.name == "error"
            && right.name == "retryable-error"
            ? minimumControlChangedPixels
            : minimumChangedPixels
        guard changedPixels >= requiredChangedPixels else {
            throw VerificationError.duplicateState(left.name, right.name, changedPixels)
        }
        print("\(left.name) -> \(right.name): \(changedPixels) changed HUD-window pixels")
    }

    let processing = states[1]
    let retryableError = states[6]
    let reducedMotion = states[7]
    let reducedMotionFollowup = states[8]
    let increaseContrast = states[9]

    for (baseline, variant) in [
        (processing, reducedMotion),
        (reducedMotion, reducedMotionFollowup),
        (retryableError, increaseContrast),
    ] {
        guard baseline.width == variant.width, baseline.height == variant.height else {
            throw VerificationError.accessibilityVariantGeometryMismatch(
                baseline.name,
                variant.name,
                baseline.width,
                baseline.height,
                variant.width,
                variant.height
            )
        }
    }

    let reducedMotionDifference = changedPixelCount(
        from: processing,
        to: reducedMotion
    )
    guard reducedMotionDifference >= minimumAccessibilityChangedPixels else {
        throw VerificationError.insufficientAccessibilityDifference(
            processing.name,
            reducedMotion.name,
            reducedMotionDifference
        )
    }
    print(
        "processing -> reduced-motion: "
            + "\(reducedMotionDifference) changed HUD-window pixels"
    )

    let reducedMotionDrift = changedPixelCount(
        from: reducedMotion,
        to: reducedMotionFollowup
    )
    guard reducedMotionDrift <= maximumReducedMotionChangedPixels else {
        throw VerificationError.unstableReducedMotion(reducedMotionDrift)
    }
    print(
        "reduced-motion-static: "
            + "\(reducedMotionDrift) changed HUD-window pixels"
    )

    let contrastDifference = changedPixelCount(
        from: retryableError,
        to: increaseContrast
    )
    guard contrastDifference >= minimumAccessibilityChangedPixels else {
        throw VerificationError.insufficientAccessibilityDifference(
            retryableError.name,
            increaseContrast.name,
            contrastDifference
        )
    }
    print(
        "retryable-error -> increase-contrast: "
            + "\(contrastDifference) changed HUD-window pixels"
    )

    print("VibeWhisper visual acceptance passed.")
} catch {
    fputs("Visual acceptance failed: \(error)\n", stderr)
    exit(1)
}
