import Foundation
import Testing
@testable import OpenWhisper

@Test
func accessibilityAuditPassesLabeledActionableControls() {
    let report = AccessibilityAuditReport.evaluate(
        surface: "settings-account",
        nodes: [
            AccessibilityAuditNode(
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                name: "OpenWhisper",
                identifier: nil,
                actionNames: []
            ),
            AccessibilityAuditNode(
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                name: "Connect ChatGPT",
                identifier: "connect",
                actionNames: ["AXPress"]
            ),
            AccessibilityAuditNode(
                role: "AXTextField",
                subrole: nil,
                roleDescription: "text field",
                name: "Account email",
                identifier: "email",
                actionNames: []
            ),
        ],
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    #expect(report.passed)
    #expect(report.actionableCount == 2)
    #expect(report.missingActionableNames.isEmpty)
    #expect(report.roles["AXButton"] == 1)
}

@Test
func accessibilityAuditFailsUnnamedActionableControls() {
    let report = AccessibilityAuditReport.evaluate(
        surface: "history",
        nodes: [
            AccessibilityAuditNode(
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                name: "",
                identifier: "refresh",
                actionNames: ["AXPress"]
            ),
        ]
    )

    #expect(report.passed == false)
    #expect(report.missingActionableNames == ["AXButton#refresh"])
}

@Test
func accessibilityAuditAcceptsStandardSubroleDescriptions() {
    let report = AccessibilityAuditReport.evaluate(
        surface: "settings-account",
        nodes: [
            AccessibilityAuditNode(
                role: "AXButton",
                subrole: "AXCloseButton",
                roleDescription: "close button",
                name: "",
                identifier: nil,
                actionNames: ["AXPress"]
            ),
        ]
    )

    #expect(report.passed)
    #expect(report.missingActionableNames.isEmpty)
}

@Test
func accessibilityAuditOutputAndSettingsPaneArgumentsAreParsed() {
    #expect(
        AppLaunchMode.accessibilityAuditOutputURL(
            environment: [:],
            arguments: [
                "OpenWhisper",
                "--accessibility-audit-output=/tmp/audit.json",
            ]
        ) == URL(fileURLWithPath: "/tmp/audit.json")
    )
    #expect(
        AppLaunchMode.settingsPane(
            arguments: ["OpenWhisper", "--settings-pane=ai-polish"]
        ) == .polish
    )
    #expect(
        AppLaunchMode.settingsPane(
            arguments: [
                "OpenWhisper",
                "--settings-pane",
                "dictation",
            ]
        ) == .dictation
    )
}
