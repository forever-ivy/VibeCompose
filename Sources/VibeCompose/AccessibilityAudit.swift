import AppKit
import Foundation

struct AccessibilityAuditNode: Codable, Equatable, Sendable {
    let role: String
    let subrole: String?
    let roleDescription: String?
    let name: String
    let identifier: String?
    let actionNames: [String]

    var isActionable: Bool {
        AccessibilityAuditReport.actionableRoles.contains(role)
            || actionNames.contains("AXPress")
    }

    var hasAccessibleName: Bool {
        if !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return true
        }
        guard
            let subrole,
            !subrole.isEmpty,
            let roleDescription,
            !roleDescription.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            return false
        }
        return true
    }
}

struct AccessibilityAuditReport: Codable, Equatable, Sendable {
    static let actionableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXLink",
        "AXMenuButton",
        "AXPopUpButton",
        "AXRadioButton",
        "AXSearchField",
        "AXSlider",
        "AXTextArea",
        "AXTextField",
    ]

    let generatedAt: Date
    let surface: String
    let nodeCount: Int
    let actionableCount: Int
    let missingActionableNames: [String]
    let roles: [String: Int]
    let actionableNodes: [AccessibilityAuditNode]
    let passed: Bool

    static func evaluate(
        surface: String,
        nodes: [AccessibilityAuditNode],
        generatedAt: Date = Date()
    ) -> AccessibilityAuditReport {
        let actionableNodes = nodes.filter(\.isActionable)
        let missingActionableNames: [String] = actionableNodes.compactMap {
            node -> String? in
            guard !node.hasAccessibleName else {
                return nil
            }
            return node.identifier.map {
                "\(node.role)#\($0)"
            } ?? node.role
        }
        let roles = Dictionary(
            grouping: nodes,
            by: \.role
        ).mapValues(\.count)

        return AccessibilityAuditReport(
            generatedAt: generatedAt,
            surface: surface,
            nodeCount: nodes.count,
            actionableCount: actionableNodes.count,
            missingActionableNames: missingActionableNames,
            roles: roles,
            actionableNodes: actionableNodes,
            passed: !nodes.isEmpty
                && !actionableNodes.isEmpty
                && missingActionableNames.isEmpty
        )
    }
}

enum AccessibilityAuditError: LocalizedError {
    case missingWindow
    case missingAccessibilityRoot

    var errorDescription: String? {
        switch self {
        case .missingWindow:
            return "The VibeCompose accessibility audit has no window."
        case .missingAccessibilityRoot:
            return "The VibeCompose accessibility audit could not resolve an accessibility root."
        }
    }
}

@MainActor
enum AccessibilityAudit {
    static func write(
        window: NSWindow?,
        surface: String,
        to outputURL: URL
    ) throws {
        guard let window else {
            throw AccessibilityAuditError.missingWindow
        }

        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // AppKit exposes this public accessibility attribute only through its
        // Objective-C selector. Enabling it makes SwiftUI publish the same
        // virtual accessibility children VoiceOver receives.
        _ = NSApplication.shared.perform(
            NSSelectorFromString(
                "setAccessibilityEnhancedUserInterface:"
            ),
            with: NSNumber(value: true)
        )

        guard let root = NSAccessibility.unignoredDescendant(of: window) else {
            throw AccessibilityAuditError.missingAccessibilityRoot
        }

        var nodes: [AccessibilityAuditNode] = []
        var visited = Set<ObjectIdentifier>()
        collect(
            root,
            depth: 0,
            visited: &visited,
            nodes: &nodes
        )
        let report = AccessibilityAuditReport.evaluate(
            surface: surface,
            nodes: nodes
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: outputURL,
            options: [.atomic]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
    }

    private static func collect(
        _ candidate: Any,
        depth: Int,
        visited: inout Set<ObjectIdentifier>,
        nodes: inout [AccessibilityAuditNode]
    ) {
        guard depth <= 40, nodes.count < 5_000 else {
            return
        }
        guard let object = candidate as? NSObject else {
            return
        }
        let objectID = ObjectIdentifier(object)
        guard visited.insert(objectID).inserted else {
            return
        }

        let role = stringValue(
            object,
            selector: "accessibilityRole"
        )
        let subrole = stringValue(
            object,
            selector: "accessibilitySubrole"
        ).nilIfEmpty
        let roleDescription = stringValue(
            object,
            selector: "accessibilityRoleDescription"
        ).nilIfEmpty
        var name = firstNonEmptyString(
            object,
            selectors: [
                "accessibilityLabel",
                "accessibilityTitle",
                "accessibilityDescription",
                "accessibilityPlaceholderValue",
                "accessibilityHelp",
            ]
        )
        if name.isEmpty {
            name = titleUIElementName(object)
        }
        let identifier = stringValue(
            object,
            selector: "accessibilityIdentifier"
        ).nilIfEmpty
        let actionNames = stringArrayValue(
            object,
            selector: "accessibilityActionNames"
        )

        if !role.isEmpty, role != "AXUnknown" {
            nodes.append(
                AccessibilityAuditNode(
                    role: role,
                    subrole: subrole,
                    roleDescription: roleDescription,
                    name: name,
                    identifier: identifier,
                    actionNames: actionNames
                )
            )
        }

        let children = objectArrayValue(
            object,
            selector: "accessibilityChildrenInNavigationOrder"
        ) + objectArrayValue(
            object,
            selector: "accessibilityChildren"
        )
        for child in children {
            collect(
                child,
                depth: depth + 1,
                visited: &visited,
                nodes: &nodes
            )
        }
    }

    private static func firstNonEmptyString(
        _ object: NSObject,
        selectors: [String]
    ) -> String {
        for selector in selectors {
            let value = stringValue(object, selector: selector)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func titleUIElementName(
        _ object: NSObject
    ) -> String {
        guard
            let titleElement = value(
                object,
                selector: "accessibilityTitleUIElement"
            ) as? NSObject
        else {
            return ""
        }
        return firstNonEmptyString(
            titleElement,
            selectors: [
                "accessibilityLabel",
                "accessibilityTitle",
                "accessibilityDescription",
                "accessibilityValue",
            ]
        )
    }

    private static func stringValue(
        _ object: NSObject,
        selector: String
    ) -> String {
        value(object, selector: selector) as? String ?? ""
    }

    private static func stringArrayValue(
        _ object: NSObject,
        selector: String
    ) -> [String] {
        value(object, selector: selector) as? [String] ?? []
    }

    private static func objectArrayValue(
        _ object: NSObject,
        selector: String
    ) -> [Any] {
        value(object, selector: selector) as? [Any] ?? []
    }

    private static func value(
        _ object: NSObject,
        selector: String
    ) -> Any? {
        let selector = NSSelectorFromString(selector)
        guard object.responds(to: selector) else {
            return nil
        }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
