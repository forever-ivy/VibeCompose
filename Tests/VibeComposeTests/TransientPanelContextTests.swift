import CoreGraphics
import Foundation
import Testing
@testable import VibeCompose

@Suite("Transient panel focus context")
struct TransientPanelContextTests {
    @Test("preview delivery keeps the context captured before presentation")
    func previewDeliveryDoesNotRecaptureFrontmostApplication() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/VibeCompose/AppCoordinator.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("targetContext: launchAppContext"))
        #expect(
            !source.contains(
                "launchAppContext: launchAppContextProvider(),"
            )
        )
    }

    @Test("focused window screen wins over a stale saved panel screen")
    func focusedWindowDeterminesPresentationScreen() throws {
        let left = TransientPanelScreen(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852)
        )
        let right = TransientPanelScreen(
            frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 1_440, y: 24, width: 1_920, height: 1_032)
        )
        let focusedWindow = CGRect(
            x: 1_620,
            y: 120,
            width: 1_200,
            height: 800
        )

        let selected = try #require(
            TransientPanelPlacement.preferredScreen(
                focusedWindowFrame: focusedWindow,
                screens: [left, right],
                fallback: left
            )
        )

        #expect(selected == right)
        #expect(
            TransientPanelPlacement.shouldReuseSavedFrame(
                CGRect(x: 200, y: 200, width: 600, height: 480),
                on: selected
            ) == false
        )
    }

    @Test("IME marked text owns navigation and commit keys")
    func markedTextKeepsInputMethodKeyEvents() {
        for keyCode: UInt16 in [53, 125, 126, 36, 76] {
            #expect(
                TransientPanelKeyRouting.shouldHandlePanelCommand(
                    keyCode: keyCode,
                    hasMarkedText: true
                ) == false
            )
            #expect(
                TransientPanelKeyRouting.shouldHandlePanelCommand(
                    keyCode: keyCode,
                    hasMarkedText: false
                ) == true
            )
        }
    }

    @Test("IME marked text blocks cancelOperation panel dismiss")
    func markedTextBlocksCancelOperationDismiss() {
        #expect(
            TransientPanelKeyRouting.shouldDismissOnCancelOperation(
                hasMarkedText: true
            ) == false
        )
        #expect(
            TransientPanelKeyRouting.shouldDismissOnCancelOperation(
                hasMarkedText: false
            ) == true
        )
    }

    @Test("skill switcher and preview capture host before activation")
    func transientPanelsCaptureHostBeforeActivation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let switcher = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/VibeCompose/SkillSwitcherWindowController.swift"
            ),
            encoding: .utf8
        )
        let preview = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/VibeCompose/PreviewRuntime.swift"
            ),
            encoding: .utf8
        )
        let coordinator = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/VibeCompose/AppCoordinator.swift"
            ),
            encoding: .utf8
        )

        // Capture must appear before activate so restore/placement stay on the host.
        for source in [switcher, preview] {
            let captureIndex = try #require(
                source.range(
                    of: "TransientPanelPresentationContext.capture()"
                )?.lowerBound
            )
            let activateIndex = try #require(
                source.range(
                    of: "NSApp.activate(ignoringOtherApps: true)"
                )?.lowerBound
            )
            #expect(captureIndex < activateIndex)
            #expect(source.contains(".moveToActiveSpace"))
            #expect(
                source.contains(
                    "shouldDismissOnCancelOperation"
                )
            )
        }

        // Standalone Skill Switcher entry resolves Skills against the live host.
        #expect(
            coordinator.contains(
                """
                let targetContext = launchAppContextProvider()
                        refreshSkillMenu(launchAppContext: targetContext)
                """
            )
            || coordinator.contains(
                "refreshSkillMenu(launchAppContext: targetContext)"
            )
        )
    }
}
