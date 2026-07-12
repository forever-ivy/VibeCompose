import AppKit
import Foundation

struct SurfaceImage {
    let name: String
    let rep: NSBitmapImageRep

    var width: Int { rep.pixelsWide }
    var height: Int { rep.pixelsHigh }
}

enum SurfaceVerificationError: Error, CustomStringConvertible {
    case usage
    case unreadable(String)
    case tooSmall(String, Int, Int)
    case tooUniform(String, Int)
    case managerGeometryMismatch(Int, Int, Int, Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_product_surfaces.swift history terminology quick-add"
        case .unreadable(let path):
            return "Could not read product surface snapshot: \(path)"
        case .tooSmall(let name, let width, let height):
            return "\(name) snapshot is unexpectedly small: \(width)x\(height)"
        case .tooUniform(let name, let colorBuckets):
            return "\(name) snapshot is too visually uniform: \(colorBuckets) sampled color buckets"
        case .managerGeometryMismatch(
            let historyWidth,
            let historyHeight,
            let terminologyWidth,
            let terminologyHeight
        ):
            return "History and Terminology manager geometry diverged: \(historyWidth)x\(historyHeight) vs \(terminologyWidth)x\(terminologyHeight)"
        }
    }
}

func load(path: String, name: String) throws -> SurfaceImage {
    guard
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let rep = NSBitmapImageRep(data: data)
    else {
        throw SurfaceVerificationError.unreadable(path)
    }
    return SurfaceImage(name: name, rep: rep)
}

func sampledColorBucketCount(_ image: SurfaceImage) -> Int {
    var buckets = Set<Int>()
    let stepX = max(1, image.width / 80)
    let stepY = max(1, image.height / 60)

    for y in stride(from: 0, to: image.height, by: stepY) {
        for x in stride(from: 0, to: image.width, by: stepX) {
            guard
                let color = image.rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
            else {
                continue
            }
            let red = Int((color.redComponent * 15).rounded())
            let green = Int((color.greenComponent * 15).rounded())
            let blue = Int((color.blueComponent * 15).rounded())
            let alpha = Int((color.alphaComponent * 15).rounded())
            buckets.insert((red << 12) | (green << 8) | (blue << 4) | alpha)
        }
    }

    return buckets.count
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 3 else {
        throw SurfaceVerificationError.usage
    }

    let history = try load(path: args[0], name: "history")
    let terminology = try load(path: args[1], name: "terminology")
    let quickAdd = try load(path: args[2], name: "quick-add")
    let surfaces = [history, terminology, quickAdd]

    for surface in surfaces {
        guard surface.width >= 900, surface.height >= 650 else {
            throw SurfaceVerificationError.tooSmall(
                surface.name,
                surface.width,
                surface.height
            )
        }
        let buckets = sampledColorBucketCount(surface)
        guard buckets >= 12 else {
            throw SurfaceVerificationError.tooUniform(surface.name, buckets)
        }
        print("\(surface.name): \(surface.width)x\(surface.height), \(buckets) sampled color buckets")
    }

    guard
        history.width == terminology.width,
        history.height == terminology.height
    else {
        throw SurfaceVerificationError.managerGeometryMismatch(
            history.width,
            history.height,
            terminology.width,
            terminology.height
        )
    }

    print("OpenWhisper product surface acceptance passed.")
} catch {
    fputs("Product surface acceptance failed: \(error)\n", stderr)
    exit(1)
}
