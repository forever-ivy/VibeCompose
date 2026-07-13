import AppKit
import CoreGraphics

enum StatusMenuVisualState: Sendable, Equatable {
    case ready
    case setupRequired
    case recording
    case processing
    case error
    case demo

    var menuLabel: String {
        switch self {
        case .ready:
            return "OW"
        case .setupRequired:
            return "SET"
        case .recording:
            return "REC"
        case .processing:
            return L10n.text("Working")
        case .error:
            return "ERR"
        case .demo:
            return "DMO"
        }
    }

    var stateDescription: String {
        switch self {
        case .ready:
            return L10n.text("Ready")
        case .setupRequired:
            return L10n.text("Setup required")
        case .recording:
            return L10n.text("Recording")
        case .processing:
            return L10n.text("Processing")
        case .error:
            return L10n.text("Error")
        case .demo:
            return L10n.text("Demo")
        }
    }

    var usesTemplateAttention: Bool {
        switch self {
        case .ready:
            return false
        case .setupRequired, .recording, .processing, .error, .demo:
            return true
        }
    }

    fileprivate var barHeights: [CGFloat] {
        switch self {
        case .ready:
            return [0.42, 0.72, 0.56]
        case .setupRequired:
            return [0.4, 0.82, 0.3]
        case .recording:
            return [0.5, 0.96, 0.68]
        case .processing:
            return [0.58, 0.84, 0.74]
        case .error:
            return [0.44, 0.84, 0.24]
        case .demo:
            return [0.48, 0.9, 0.6]
        }
    }
}

enum OpenWhisperPalette {
    static let graphite = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.15, alpha: 0.96)
    static let mist = NSColor(srgbRed: 0.94, green: 0.96, blue: 0.985, alpha: 1)
    static let mistMuted = NSColor(srgbRed: 0.78, green: 0.82, blue: 0.88, alpha: 1)
    static let signalBlue = NSColor(srgbRed: 0.18, green: 0.52, blue: 1, alpha: 1)
    static let iceBlue = NSColor(srgbRed: 0.48, green: 0.78, blue: 1, alpha: 1)
    static let success = NSColor(srgbRed: 0.35, green: 0.84, blue: 0.62, alpha: 1)
    static let amber = NSColor(srgbRed: 1, green: 0.75, blue: 0.32, alpha: 1)
    static let error = NSColor(srgbRed: 1, green: 0.45, blue: 0.46, alpha: 1)
}

enum OpenWhisperStatusIconRenderer {
    static func image(for state: StatusMenuVisualState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let strokeColor = NSColor.black.withAlphaComponent(state.usesTemplateAttention ? 0.92 : 0.82)
        let barColor = NSColor.black.withAlphaComponent(state.usesTemplateAttention ? 1 : 0.92)

        let bubbleRect = NSRect(x: 1.5, y: 4.0, width: 14.2, height: 9.4)
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 4.6, yRadius: 4.6)
        bubble.lineWidth = 1.35
        strokeColor.setStroke()
        bubble.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.1, y: 3.6))
        tail.line(to: NSPoint(x: 6.0, y: 2.0))
        tail.line(to: NSPoint(x: 7.2, y: 3.2))
        tail.line(to: NSPoint(x: 5.3, y: 4.8))
        tail.close()
        tail.lineWidth = 1.15
        strokeColor.setStroke()
        tail.stroke()

        let barXPositions: [CGFloat] = [7.4, 10.0, 12.6]
        for (index, normalizedHeight) in state.barHeights.enumerated() {
            let height = max(3.1, normalizedHeight * 6.2)
            let barRect = NSRect(
                x: barXPositions[index],
                y: 8.6 - (height / 2),
                width: 1.7,
                height: height
            )
            let bar = NSBezierPath(roundedRect: barRect, xRadius: 0.85, yRadius: 0.85)
            barColor.setFill()
            bar.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

extension NSColor {
    static func blend(from start: NSColor, to end: NSColor, amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        let startRGB = start.usingColorSpace(.sRGB) ?? start
        let endRGB = end.usingColorSpace(.sRGB) ?? end

        return NSColor(
            srgbRed: startRGB.redComponent + ((endRGB.redComponent - startRGB.redComponent) * t),
            green: startRGB.greenComponent + ((endRGB.greenComponent - startRGB.greenComponent) * t),
            blue: startRGB.blueComponent + ((endRGB.blueComponent - startRGB.blueComponent) * t),
            alpha: startRGB.alphaComponent + ((endRGB.alphaComponent - startRGB.alphaComponent) * t)
        )
    }
}
