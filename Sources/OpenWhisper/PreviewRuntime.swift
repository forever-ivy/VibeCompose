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

enum PreviewDecision:
    Sendable,
    Equatable
{
    case replaceSelection
    case pasteToTarget
    case copy
    case cancel
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
    let validationPassed: Bool
    let allowsSelectionReplacement:
        Bool

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
        validationPassed: Bool,
        allowsSelectionReplacement:
            Bool
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
            contextCapabilities
        self.validationPassed =
            validationPassed
        self.allowsSelectionReplacement =
            allowsSelectionReplacement
    }

    var comparisonSource: String {
        selectedText
            ?? originalTranscript
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
        let separator =
            usesLines ? "\n" : " "
        let originalTokens = tokens(
            original,
            usesLines: usesLines
        )
        let revisedTokens = tokens(
            revised,
            usesLines: usesLines
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
        usesLines: Bool
    ) -> [String] {
        if usesLines {
            return value.components(
                separatedBy: .newlines
            )
        }
        return value.split(
            whereSeparator:
                \.isWhitespace
        ).map(String.init)
    }
}

@MainActor
final class PreviewWindowController:
    NSObject,
    PreviewPresenting,
    PreviewSnapshotCapturing,
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
    enum ContentMode:
        String,
        CaseIterable,
        Identifiable
    {
        case diff = "Diff"
        case result = "Result"
        case source = "Source"

        var id: String { rawValue }
    }

    let request: PreviewRequest
    let onDecision:
        (PreviewDecision) -> Void

    @State private var mode:
        ContentMode = .diff

    private var diff: TextDiff {
        TextDiffEngine.diff(
            original:
                request
                    .comparisonSource,
            revised:
                request.resultText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Picker(
                    L10n.text(
                        "Preview content"
                    ),
                    selection: $mode
                ) {
                    ForEach(
                        ContentMode.allCases
                    ) { mode in
                        Text(
                            L10n.text(
                                mode.rawValue
                            )
                        ).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                content
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
            .padding(20)

            Divider()
            actions
        }
        .frame(
            minWidth: 640,
            minHeight: 440
        )
        .background(
            Color(
                nsColor:
                    .windowBackgroundColor
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(
                systemName:
                    "text.badge.checkmark"
            )
            .font(.system(size: 26))
            .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.skillName)
                    .font(
                        .system(
                            size: 20,
                            weight:
                                .semibold
                        )
                    )
                Text(
                    L10n.format(
                        "Skill %@ · version %@",
                        request.skillID,
                        request.skillVersion
                    )
                )
                .font(
                    .system(
                        size: 10,
                        design:
                            .monospaced
                    )
                )
                .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                request.validationPassed
                    ? L10n.text(
                        "Validated"
                    )
                    : L10n.text(
                        "Validation failed"
                    ),
                systemImage:
                    request
                        .validationPassed
                        ? "checkmark.shield.fill"
                        : "exclamationmark.shield.fill"
            )
            .font(
                .system(
                    size: 11,
                    weight: .medium
                )
            )
            .foregroundStyle(
                request.validationPassed
                    ? .green
                    : .orange
            )
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .diff:
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(
                        L10n.format(
                            "%ld additions · %ld removals",
                            diff.addedCount,
                            diff.removedCount
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    ForEach(diff.segments) {
                        segment in
                        Text(segment.text)
                            .font(
                                .system(
                                    size: 13,
                                    design:
                                        .monospaced
                                )
                            )
                            .foregroundStyle(
                                foreground(
                                    for:
                                        segment
                                            .kind
                                )
                            )
                            .strikethrough(
                                segment.kind
                                    == .removed
                            )
                            .padding(
                                .horizontal,
                                8
                            )
                            .padding(
                                .vertical,
                                4
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                alignment:
                                    .leading
                            )
                            .background(
                                background(
                                    for:
                                        segment
                                            .kind
                                )
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius:
                                        6
                                )
                            )
                    }
                }
                .textSelection(.enabled)
            }
        case .result:
            textEditor(
                request.resultText
            )
        case .source:
            textEditor(
                request
                    .comparisonSource
            )
        }
    }

    private func textEditor(
        _ value: String
    ) -> some View {
        ScrollView {
            Text(value)
                .font(
                    .system(
                        size: 13,
                        design:
                            .monospaced
                    )
                )
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
                .padding(12)
        }
        .background(
            Color(
                nsColor:
                    .textBackgroundColor
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if !request
                .contextCapabilities
                .isEmpty
            {
                Label(
                    L10n.text(
                        "Selected text only"
                    ),
                    systemImage:
                        "selection.pin.in.out"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(
                L10n.text("Cancel")
            ) {
                onDecision(.cancel)
            }
            .keyboardShortcut(
                .cancelAction
            )
            Button(
                L10n.text("Copy")
            ) {
                onDecision(.copy)
            }
            if request
                .allowsSelectionReplacement
            {
                Button(
                    L10n.text(
                        "Replace Selection"
                    )
                ) {
                    onDecision(
                        .replaceSelection
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .keyboardShortcut(
                    .defaultAction
                )
            } else {
                Button(
                    L10n.text(
                        "Paste to Target"
                    )
                ) {
                    onDecision(
                        .pasteToTarget
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .keyboardShortcut(
                    .defaultAction
                )
            }
        }
        .padding(16)
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
