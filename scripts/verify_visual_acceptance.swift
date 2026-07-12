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

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_visual_acceptance.swift recording processing result error retryable-error"
        case .unreadableImage(let path):
            return "Could not read screenshot: \(path)"
        case .missingHud(let state, let visiblePixels):
            return "\(state) did not contain enough visible HUD pixels (\(visiblePixels) visible)"
        case .duplicateState(let left, let right, let changedPixels):
            return "\(left) and \(right) look too similar as HUD windows (\(changedPixels) changed pixels)"
        }
    }
}

let expectedStateNames = [
    "recording",
    "processing",
    "result",
    "error",
    "retryable-error",
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

    for state in states {
        let visiblePixels = visiblePixelCount(in: state)
        guard visiblePixels >= minimumVisiblePixels else {
            throw VerificationError.missingHud(state.name, visiblePixels)
        }
        print("\(state.name): \(state.width)x\(state.height), \(visiblePixels) visible HUD pixels")
    }

    for index in 0..<(states.count - 1) {
        let left = states[index]
        let right = states[index + 1]
        if left.width != right.width || left.height != right.height {
            print("\(left.name) -> \(right.name): distinct window size \(left.width)x\(left.height) -> \(right.width)x\(right.height)")
            continue
        }

        let changedPixels = changedPixelCount(from: left, to: right)
        guard changedPixels >= minimumChangedPixels else {
            throw VerificationError.duplicateState(left.name, right.name, changedPixels)
        }
        print("\(left.name) -> \(right.name): \(changedPixels) changed HUD-window pixels")
    }

    print("OpenWhisper visual acceptance passed.")
} catch {
    fputs("Visual acceptance failed: \(error)\n", stderr)
    exit(1)
}
