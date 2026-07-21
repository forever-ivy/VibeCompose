import AppKit
import Foundation
import SwiftUI

enum OutputRoute:
    Sendable,
    Equatable
{
    case automatic
    case preview
    case copyOnly
}

struct OutputRouter:
    Sendable
{
    func route(
        plan:
            ResolvedSkillExecutionPlan,
        automaticPasteAllowed: Bool,
        hasSelectionContext: Bool,
        additionalRisk:
            SkillRiskLevel = .low
    ) -> OutputRoute {
        guard automaticPasteAllowed else {
            return .copyOnly
        }
        if
            plan.skill.output.risk
                == .high
                || additionalRisk == .high
        {
            return .preview
        }
        switch plan.skill.output.delivery {
        case .automaticPasteWhenVerified:
            return hasSelectionContext
                ? .preview
                : .automatic
        case .previewThenPaste:
            return .preview
        case .copyOnly:
            return .copyOnly
        }
    }
}

enum PreviewAction:
    String,
    Sendable,
    Equatable
{
    case replaceSelection
    case pasteToTarget
    case copy
}

enum PreviewDecision:
    Sendable,
    Equatable
{
    case replaceSelection(text: String)
    case pasteToTarget(text: String)
    case copy(text: String)
    case cancel

    var action: PreviewAction? {
        switch self {
        case .replaceSelection:
            return .replaceSelection
        case .pasteToTarget:
            return .pasteToTarget
        case .copy:
            return .copy
        case .cancel:
            return nil
        }
    }

    var finalText: String? {
        switch self {
        case let .replaceSelection(text),
             let .pasteToTarget(text),
             let .copy(text):
            return text
        case .cancel:
            return nil
        }
    }
}

struct PreviewRequest:
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let skillID: String
    let skillVersion: String
    let skillName: String
    let originalTranscript: String
    let resultText: String
    let selectedText: String?
    let contextCapabilities:
        [SkillCapability]
    let initialValidationIssueCodes:
        [String]
    let fallbackMessage: String?
    let allowsSelectionReplacement:
        Bool
    let allowsPasteToTarget: Bool
    let executionPlan:
        ResolvedSkillExecutionPlan

    init(
        id: UUID = UUID(),
        skillID: String,
        skillVersion: String,
        skillName: String,
        originalTranscript: String,
        resultText: String,
        selectedText: String?,
        contextCapabilities:
            [SkillCapability],
        initialValidationIssueCodes:
            [String] = [],
        fallbackMessage: String? = nil,
        allowsSelectionReplacement:
            Bool,
        allowsPasteToTarget: Bool = true,
        executionPlan:
            ResolvedSkillExecutionPlan? = nil
    ) {
        self.id = id
        self.skillID = skillID
        self.skillVersion = skillVersion
        self.skillName = skillName
        self.originalTranscript =
            originalTranscript
        self.resultText = resultText
        self.selectedText = selectedText
        self.contextCapabilities =
            Self.normalizedCapabilities(
                [.voice] + contextCapabilities
            )
        self.initialValidationIssueCodes =
            Array(
                initialValidationIssueCodes
                    .prefix(20)
            )
        self.fallbackMessage =
            fallbackMessage?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        self.allowsSelectionReplacement =
            allowsSelectionReplacement
                && allowsPasteToTarget
        self.allowsPasteToTarget =
            allowsPasteToTarget
        self.executionPlan =
            executionPlan
            ?? SkillResolver().resolve(
                manualSkillID: skillID,
                config: SkillsConfig(),
                launchAppContext: nil
            )
    }

    var comparisonSource: String {
        selectedText
            ?? originalTranscript
    }

    var validationSourceText: String {
        guard
            let selectedText,
            !selectedText.isEmpty
        else {
            return originalTranscript
        }
        return originalTranscript
            + "\n"
            + selectedText
    }

    var sourceLabel: String {
        let sourceID =
            executionPlan.installation.sourceID
        if sourceID == "builtin" {
            return L10n.text("Built-in")
        }
        if sourceID.hasPrefix("registry:") {
            return L10n.text("Community")
        }
        if sourceID == "local.agent-skills" {
            return L10n.text("Local Agent Skill")
        }
        if sourceID == "local.legacy-v1" {
            return L10n.text("Legacy import")
        }
        return L10n.text("Imported")
    }

    var resolutionLabel: String {
        executionPlan.source.localizedLabel
    }

    var hasValidatorFallback: Bool {
        !initialValidationIssueCodes.isEmpty
            || fallbackMessage?.isEmpty == false
    }

    private static func normalizedCapabilities(
        _ values: [SkillCapability]
    ) -> [SkillCapability] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert($0.rawValue).inserted
        }
    }
}

@MainActor
protocol PreviewPresenting:
    AnyObject
{
    func present(
        _ request: PreviewRequest
    ) async -> PreviewDecision

    func dismiss()
}

@MainActor
protocol PreviewSnapshotCapturing:
    AnyObject
{
    func writePreviewSnapshot(
        to url: URL
    ) throws
}

@MainActor
protocol PreviewAccessibilityAuditing:
    AnyObject
{
    func writePreviewAccessibilityAudit(
        to url: URL
    ) throws
}

enum TextDiffKind:
    Sendable,
    Equatable
{
    case unchanged
    case added
    case removed
}

struct TextDiffSegment:
    Sendable,
    Equatable,
    Identifiable
{
    let id: Int
    let kind: TextDiffKind
    let text: String
}

struct TextDiff:
    Sendable,
    Equatable
{
    let segments:
        [TextDiffSegment]
    let addedCount: Int
    let removedCount: Int
}

enum TextDiffEngine {
    static let maximumTokenCount = 400

    static func diff(
        original: String,
        revised: String
    ) -> TextDiff {
        let usesLines =
            original.contains("\n")
                || revised.contains("\n")
        let usesCharacterTokens =
            !usesLines
                && (containsCJK(original)
                    || containsCJK(revised))
        let separator = usesLines
            ? "\n"
            : (usesCharacterTokens ? "" : " ")
        let originalTokens = tokens(
            original,
            usesLines: usesLines,
            usesCharacterTokens:
                usesCharacterTokens
        )
        let revisedTokens = tokens(
            revised,
            usesLines: usesLines,
            usesCharacterTokens:
                usesCharacterTokens
        )

        guard
            originalTokens.count
                <= maximumTokenCount,
            revisedTokens.count
                <= maximumTokenCount
        else {
            return TextDiff(
                segments: [
                    TextDiffSegment(
                        id: 0,
                        kind: .removed,
                        text: original
                    ),
                    TextDiffSegment(
                        id: 1,
                        kind: .added,
                        text: revised
                    ),
                ],
                addedCount:
                    revisedTokens.count,
                removedCount:
                    originalTokens.count
            )
        }

        let n = originalTokens.count
        let m = revisedTokens.count
        var lengths = Array(
            repeating: Array(
                repeating: 0,
                count: m + 1
            ),
            count: n + 1
        )

        if n > 0, m > 0 {
            for i in stride(
                from: n - 1,
                through: 0,
                by: -1
            ) {
                for j in stride(
                    from: m - 1,
                    through: 0,
                    by: -1
                ) {
                    if originalTokens[i]
                        == revisedTokens[j]
                    {
                        lengths[i][j] =
                            lengths[i + 1][j + 1]
                                + 1
                    } else {
                        lengths[i][j] = max(
                            lengths[i + 1][j],
                            lengths[i][j + 1]
                        )
                    }
                }
            }
        }

        var raw:
            [(TextDiffKind, String)] = []
        var i = 0
        var j = 0
        var addedCount = 0
        var removedCount = 0
        while i < n || j < m {
            if
                i < n,
                j < m,
                originalTokens[i]
                    == revisedTokens[j]
            {
                raw.append(
                    (
                        .unchanged,
                        originalTokens[i]
                    )
                )
                i += 1
                j += 1
            } else if
                j < m,
                i == n
                    || lengths[i][j + 1]
                        > lengths[i + 1][j]
            {
                raw.append(
                    (
                        .added,
                        revisedTokens[j]
                    )
                )
                addedCount += 1
                j += 1
            } else if i < n {
                raw.append(
                    (
                        .removed,
                        originalTokens[i]
                    )
                )
                removedCount += 1
                i += 1
            }
        }

        var merged:
            [(TextDiffKind, String)] = []
        for item in raw {
            if
                let last = merged.last,
                last.0 == item.0
            {
                merged[merged.count - 1].1 +=
                    separator + item.1
            } else {
                merged.append(item)
            }
        }

        return TextDiff(
            segments:
                merged.enumerated()
                    .map {
                        TextDiffSegment(
                            id: $0.offset,
                            kind:
                                $0.element.0,
                            text:
                                $0.element.1
                        )
                    },
            addedCount: addedCount,
            removedCount:
                removedCount
        )
    }

    private static func tokens(
        _ value: String,
        usesLines: Bool,
        usesCharacterTokens: Bool
    ) -> [String] {
        if usesLines {
            return value.components(
                separatedBy: .newlines
            )
        }
        if usesCharacterTokens {
            return value.map(String.init)
        }
        return value.split(
            whereSeparator:
                \.isWhitespace
        ).map(String.init)
    }

    private static func containsCJK(
        _ value: String
    ) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FDF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0x3100...0x312F,
                 0x31A0...0x31BF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xAC00...0xD7AF,
                 0xF900...0xFAFF,
                 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
final class PreviewWindowController:
    NSObject,
    PreviewPresenting,
    PreviewSnapshotCapturing,
    PreviewAccessibilityAuditing,
    NSWindowDelegate
{
    private var window: NSWindow?
    private var continuation:
        CheckedContinuation<
            PreviewDecision,
            Never
        >?
    private var isFinishing = false

    func present(
        _ request: PreviewRequest
    ) async -> PreviewDecision {
        finish(.cancel)
        return await withCheckedContinuation {
            continuation in
            self.continuation =
                continuation
            let view = PreviewView(
                request: request
            ) { [weak self] decision in
                self?.finish(decision)
            }
            .applyingOpenWhisperBrandTint()
            .applyingAccessibilityDisplayOptionsOverride(
                .currentVisualAcceptance
            )
            let controller =
                NSHostingController(
                    rootView: view
                )
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: 760,
                    height: 560
                ),
                styleMask: [
                    .titled,
                    .closable,
                    .resizable,
                    .miniaturizable,
                ],
                backing: .buffered,
                defer: false
            )
            window.title =
                L10n.text(
                    "OpenWhisper Preview"
                )
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier(
                "OpenWhisper.PreviewWindow"
            )
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.contentViewController =
                controller
            window.delegate = self
            window.setFrameAutosaveName(
                "OpenWhisper.PreviewWindow"
            )
            window.minSize = NSSize(
                width: 640,
                height: 440
            )
            window.center()
            AccessibilityDisplayOptionsOverride
                .currentVisualAcceptance
                .applyAppearance(to: window)
            self.window = window
            NSApplication.shared.activate(
                ignoringOtherApps: true
            )
            window.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        finish(.cancel)
    }

    func writePreviewSnapshot(
        to url: URL
    ) throws {
        try ProductSurfaceSnapshot.write(
            window: window,
            to: url
        )
    }

    func writePreviewAccessibilityAudit(
        to url: URL
    ) throws {
        try AccessibilityAudit.write(
            window: window,
            surface: "preview",
            to: url
        )
    }

    func windowWillClose(
        _ notification: Notification
    ) {
        guard !isFinishing else {
            return
        }
        finish(
            .cancel,
            closeWindow: false
        )
    }

    private func finish(
        _ decision:
            PreviewDecision,
        closeWindow: Bool = true
    ) {
        guard
            continuation != nil
                || window != nil
        else {
            return
        }
        isFinishing = true
        let continuation =
            self.continuation
        self.continuation = nil
        let window = self.window
        self.window = nil
        if closeWindow {
            window?.orderOut(nil)
            window?.close()
        }
        isFinishing = false
        continuation?.resume(
            returning: decision
        )
    }
}

private struct PreviewView: View {
    enum ComparisonMode:
        String,
        CaseIterable,
        Identifiable
    {
        case diff = "Diff"
        case source = "Source"

        var id: String { rawValue }
    }

    let request: PreviewRequest
    let onDecision:
        (PreviewDecision) -> Void

    @State private var mode:
        ComparisonMode = .diff
    @State private var editedText: String

    init(
        request: PreviewRequest,
        onDecision:
            @escaping (PreviewDecision) -> Void
    ) {
        self.request = request
        self.onDecision = onDecision
        _editedText = State(
            initialValue: request.resultText
        )
    }

    private var diff: TextDiff {
        TextDiffEngine.diff(
            original: request.comparisonSource,
            revised: editedText
        )
    }

    private var validation:
        SkillValidationReport
    {
        SkillValidatorEngine().validate(
            output: editedText,
            originalText:
                request.validationSourceText,
            plan: request.executionPlan
        )
    }

    private var isEdited: Bool {
        editedText != request.resultText
    }

    private var isUnreviewedFallback: Bool {
        request.hasValidatorFallback
            && !isEdited
    }

    private var hasText: Bool {
        !editedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var canApply: Bool {
        hasText
            && validation.isValid
            && !isUnreviewedFallback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    if request.hasValidatorFallback {
                        fallbackNotice
                    }
                    runSummary
                    comparison
                    editableResult
                    validationStatus
                }
                .padding(20)
            }
            Divider()
            actions
        }
        .frame(
            minWidth: 680,
            minHeight: 560
        )
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.skillName)
                    .font(.system(size: 20, weight: .semibold))
                Text(
                    L10n.format(
                        "%@ · %@ · %@",
                        request.sourceLabel,
                        request.resolutionLabel,
                        request.skillVersion
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                editStateLabel,
                systemImage: isEdited
                    ? "pencil.line"
                    : (request.hasValidatorFallback
                        ? "arrow.uturn.backward.circle"
                        : "sparkles")
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
                request.hasValidatorFallback && !isEdited
                    ? .orange
                    : .secondary
            )
        }
        .padding(20)
    }

    private var editStateLabel: String {
        if isEdited {
            return L10n.text("Edited by you")
        }
        if request.hasValidatorFallback {
            return L10n.text("Fallback transcript")
        }
        return L10n.text("AI generated")
    }

    private var fallbackNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                L10n.text(
                    "Skill output did not pass its checks."
                ),
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12, weight: .semibold))
            Text(
                L10n.text(
                    "Showing the original normalized transcript instead. Review and edit it, or copy it without changing the target."
                )
            )
            .font(.system(size: 11))
            if !request.initialValidationIssueCodes.isEmpty {
                Text(
                    L10n.format(
                        "Reason: %@",
                        request.initialValidationIssueCodes
                            .joined(separator: ", ")
                    )
                )
                .font(.system(size: 10, design: .monospaced))
            }
            if let fallbackMessage = request.fallbackMessage,
               !fallbackMessage.isEmpty
            {
                Text(fallbackMessage)
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(.orange)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var runSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Label(
                contextSummary,
                systemImage: "checkmark.shield"
            )
            Label(
                validationSummary,
                systemImage: validation.isValid
                    && !isUnreviewedFallback
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(
                validation.isValid
                    && !isUnreviewedFallback
                    ? .green
                    : .orange
            )
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
    }

    private var contextSummary: String {
        let labels = request.contextCapabilities
            .map(capabilityLabel)
            .joined(separator: " + ")
        return L10n.format(
            "Used: %@",
            labels
        )
    }

    private var validationSummary: String {
        if isUnreviewedFallback {
            return L10n.text(
                "Validator: fallback needs review"
            )
        }
        if validation.isValid {
            return L10n.text("Validator: passed")
        }
        return L10n.format(
            "Validator: %@",
            validation.issues
                .map { $0.code.rawValue }
                .joined(separator: ", ")
        )
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Changes"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker(
                    L10n.text("Preview content"),
                    selection: $mode
                ) {
                    ForEach(ComparisonMode.allCases) { mode in
                        Text(L10n.text(mode.rawValue))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Group {
                switch mode {
                case .diff:
                    diffView
                case .source:
                    readOnlyText(request.comparisonSource)
                }
            }
            .frame(minHeight: 120, maxHeight: 200)
        }
    }

    private var diffView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    L10n.format(
                        "%ld additions · %ld removals",
                        diff.addedCount,
                        diff.removedCount
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                ForEach(diff.segments) { segment in
                    Text(segment.text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(foreground(for: segment.kind))
                        .strikethrough(segment.kind == .removed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(background(for: segment.kind))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityLabel(
                            diffAccessibilityLabel(segment)
                        )
                }
            }
            .padding(10)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var editableResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Editable result"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(
                    L10n.format(
                        "%ld characters",
                        editedText.count
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            TextEditor(text: $editedText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 130, idealHeight: 170)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color(nsColor: .separatorColor)
                                .opacity(0.6),
                            lineWidth: 0.5
                        )
                }
                .accessibilityLabel(
                    L10n.text("Editable result")
                )
        }
    }

    @ViewBuilder
    private var validationStatus: some View {
        if !validation.isValid {
            Label(
                L10n.format(
                    "Fix these checks before replacing or pasting: %@",
                    validation.issues
                        .map { $0.code.rawValue }
                        .joined(separator: ", ")
                ),
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.orange)
        } else if isUnreviewedFallback {
            Text(
                L10n.text(
                    "This is a fallback transcript. Copy it, or edit it into a valid Skill result before applying."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.orange)
        }
    }

    private func readOnlyText(
        _ value: String
    ) -> some View {
        ScrollView {
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(L10n.text("Reset to generated result")) {
                editedText = request.resultText
            }
            .disabled(!isEdited)
            Spacer()
            Button(L10n.text("Cancel")) {
                onDecision(.cancel)
            }
            .keyboardShortcut(.cancelAction)
            Button(L10n.text("Copy")) {
                onDecision(.copy(text: editedText))
            }
            .disabled(!hasText)
            if request.allowsSelectionReplacement {
                Button(L10n.text("Replace Selection")) {
                    onDecision(
                        .replaceSelection(
                            text: editedText
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            } else if request.allowsPasteToTarget {
                Button(L10n.text("Paste to Target")) {
                    onDecision(
                        .pasteToTarget(
                            text: editedText
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(16)
    }

    private func capabilityLabel(
        _ capability: SkillCapability
    ) -> String {
        switch capability {
        case .voice:
            return L10n.text("Voice")
        case .selection:
            return L10n.text("Selected text")
        case .focusedParagraph:
            return L10n.text("Focused paragraph")
        case .conversationWindow:
            return L10n.text("Conversation window")
        case .clipboard:
            return L10n.text("Clipboard")
        case .styleCapsule:
            return L10n.text("Style Capsule")
        case .externalAction:
            return L10n.text("Unsupported action")
        }
    }

    private func diffAccessibilityLabel(
        _ segment: TextDiffSegment
    ) -> String {
        let status: String
        switch segment.kind {
        case .unchanged:
            status = L10n.text("Unchanged")
        case .added:
            status = L10n.text("Added")
        case .removed:
            status = L10n.text("Removed")
        }
        return "\(status): \(segment.text)"
    }

    private func foreground(
        for kind: TextDiffKind
    ) -> Color {
        switch kind {
        case .unchanged:
            return .primary
        case .added:
            return .green
        case .removed:
            return .red
        }
    }

    private func background(
        for kind: TextDiffKind
    ) -> Color {
        switch kind {
        case .unchanged:
            return Color.clear
        case .added:
            return Color.green.opacity(
                0.10
            )
        case .removed:
            return Color.red.opacity(
                0.10
            )
        }
    }
}
