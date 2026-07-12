import AppKit
import CoreGraphics
import Foundation

guard let screen = NSScreen.main else {
    exit(0)
}

let frame = screen.frame
let center = CGPoint(x: frame.midX, y: frame.midY)
CGWarpMouseCursorPosition(center)
CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
