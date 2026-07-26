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
            SkillRiskLevel = .low,
        skipPreviewWhenSafe: Bool = false
    ) -> OutputRoute {
        guard automaticPasteAllowed else {
            return .copyOnly
        }
        let isHighRisk =
            plan.skill.output.risk == .high
                || additionalRisk == .high
        // High-risk and selection replacement always stay in Preview —
        // they rewrite existing text and need an explicit human gate.
        if isHighRisk || hasSelectionContext {
            return .preview
        }
        switch plan.skill.output.delivery {
        case .automaticPasteWhenVerified:
            return .automatic
        case .previewThenPaste:
            // User preference: skip the review panel for ordinary insert-only
            // dictation. Validation fallbacks still force Preview upstream.
            return skipPreviewWhenSafe
                ? .automatic
                : .preview
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
    /// User wants a different Skill applied to the same source transcript.
    /// `editedSource` is the current editable field (may equal the original).
    case reprocess(skillInstallationID: UUID, editedSource: String)
    /// User opened Skill Switcher from Preview. Host should open the switcher
    /// without treating the session as cancelled.
    case changeSkill(editedSource: String)

    var action: PreviewAction? {
        switch self {
        case .replaceSelection:
            return .replaceSelection
        case .pasteToTarget:
            return .pasteToTarget
        case .copy:
            return .copy
        case .cancel, .reprocess, .changeSkill:
            return nil
        }
    }

    var finalText: String? {
        switch self {
        case let .replaceSelection(text),
             let .pasteToTarget(text),
             let .copy(text):
            return text
        case .cancel, .reprocess, .changeSkill:
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
    /// Installed skills the panel can switch to without leaving Preview.
    /// Empty means the Change Skill control is hidden.
    let skillChoices: [SkillMenuEntry]
    let currentSkillInstallationID: UUID?

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
            ResolvedSkillExecutionPlan? = nil,
        skillChoices: [SkillMenuEntry] = [],
        currentSkillInstallationID: UUID? = nil
    ) {
        let resolvedExecutionPlan =
            executionPlan
            ?? SkillResolver().resolve(
                manualSkillID: skillID,
                config: SkillsConfig(),
                launchAppContext: nil
            )
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
                && resolvedExecutionPlan
                    .skill
                    .usesSelectionAsPrimaryInput
        self.allowsPasteToTarget =
            allowsPasteToTarget
        self.executionPlan =
            resolvedExecutionPlan
        self.skillChoices = skillChoices
        self.currentSkillInstallationID =
            currentSkillInstallationID
            ?? resolvedExecutionPlan.installation.id
    }

    var comparisonSource: String {
        guard
            executionPlan.skill
                .usesSelectionAsPrimaryInput
        else {
            return originalTranscript
        }
        return selectedText ?? originalTranscript
    }

    var validationSourceText: String {
        executionPlan.skill
            .validationSourceText(
                transcript:
                    originalTranscript,
                selection: selectedText
            )
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
    /// Present Result Preview and wait for a terminal decision (apply / copy /
    /// cancel). Skill re-runs stay on this panel via `regenerate` — they must
    /// not dismiss the surface or open another window.
    func present(
        _ request: PreviewRequest,
        regenerate: @escaping @MainActor (
            _ skillInstallationID: UUID,
            _ editedSource: String
        ) async -> Result<PreviewRequest, any Error>
    ) async -> PreviewDecision

    func dismiss()

    /// Feed a voice refinement transcript into the open preview panel.
    /// The panel calls its `regenerate` closure with the transcript as
    /// `editedSource`, re-running the active skill on the new instruction.
    /// A no-op when no preview is currently presented.
    func injectVoiceRefinement(_ transcript: String) async
}

extension PreviewPresenting {
    /// Convenience for call sites that never offer in-panel skill switch
    /// (tests, skill-test preview without a session cache).
    func present(
        _ request: PreviewRequest
    ) async -> PreviewDecision {
        await present(request) { _, _ in
            .failure(PreviewRegenerateError.unavailable)
        }
    }

    /// Default no-op so mock/test conformers don't need to implement D4.
    func injectVoiceRefinement(_ transcript: String) async {}
}

enum PreviewRegenerateError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.text("Skill regeneration is unavailable.")
        }
    }
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
    private var window: NSPanel?
    private var hostingController:
        NSHostingController<AnyView>?
    private var continuation:
        CheckedContinuation<
            PreviewDecision,
            Never
        >?
    private var isFinishing = false
    /// Host app frontmost before Preview activated VibeCompose. Restored on
    /// dismiss so AppKit does not promote a still-open Settings window.
    private var priorExternalFrontmost: LaunchAppContext?
    private var regenerate:
        (
            @MainActor (
                _ skillInstallationID: UUID,
                _ editedSource: String
            ) async -> Result<PreviewRequest, any Error>
        )?
    /// Tracks the installation ID of the skill currently shown on the panel so
    /// `injectVoiceRefinement` can call `regenerate` without extra parameters.
    private var currentInstallationID: UUID?

    func present(
        _ request: PreviewRequest,
        regenerate: @escaping @MainActor (
            _ skillInstallationID: UUID,
            _ editedSource: String
        ) async -> Result<PreviewRequest, any Error>
    ) async -> PreviewDecision {
        finish(.cancel)
        self.regenerate = regenerate
        currentInstallationID = request.currentSkillInstallationID
        return await withCheckedContinuation {
            continuation in
            self.continuation =
                continuation
            install(
                request: request,
                createWindow: true
            )
        }
    }

    func dismiss() {
        finish(.cancel)
    }

    func injectVoiceRefinement(_ transcript: String) async {
        guard let installationID = currentInstallationID else { return }
        let trimmed = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }
        let result = await runRegenerate(
            skillInstallationID: installationID,
            editedSource: trimmed
        )
        if case let .success(newRequest) = result {
            // Keep currentInstallationID in sync with any skill switch that
            // may have been embedded inside the regeneration response.
            if let updated = newRequest.currentSkillInstallationID {
                currentInstallationID = updated
            }
            install(request: newRequest, createWindow: false)
        }
    }

    private func install(
        request: PreviewRequest,
        createWindow: Bool
    ) {
        let view = PreviewView(
            request: request,
            onDecision: { [weak self] decision in
                self?.finish(decision)
            },
            onRegenerate: { [weak self] installationID, edited in
                await self?.runRegenerate(
                    skillInstallationID: installationID,
                    editedSource: edited
                ) ?? .failure(PreviewRegenerateError.unavailable)
            }
        )
        .applyingVibeComposeBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let anyView = AnyView(view)

        if let hostingController {
            hostingController.rootView = anyView
            return
        }

        guard createWindow else { return }

        let controller = NSHostingController(rootView: anyView)
        // Movable floating glass panel built with the macOS 26 AppKit
        // NSGlassEffectView surface (same native glass the HUD uses).
        // Wider + taller so Result stays primary and Comparison can expand.
        let panel = PreviewPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PreviewLayout.width,
                height: PreviewLayout.height
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        // Glass draws its own soft elevation; avoid a second window shadow.
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
        ]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.identifier = NSUserInterfaceItemIdentifier(
            "VibeCompose.PreviewPanel"
        )
        panel.tabbingMode = .disallowed

        let surface = makePreviewSurface(
            cornerRadius: VibeComposeFloatingChrome.panelCornerRadius
        )
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        surface.contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(
                equalTo: surface.contentView.leadingAnchor
            ),
            controller.view.trailingAnchor.constraint(
                equalTo: surface.contentView.trailingAnchor
            ),
            controller.view.topAnchor.constraint(
                equalTo: surface.contentView.topAnchor
            ),
            controller.view.bottomAnchor.constraint(
                equalTo: surface.contentView.bottomAnchor
            ),
            surface.rootView.widthAnchor.constraint(
                equalToConstant: PreviewLayout.width
            ),
            surface.rootView.heightAnchor.constraint(
                equalToConstant: PreviewLayout.height
            ),
        ])
        panel.contentView = surface.rootView
        panel.delegate = self
        AccessibilityDisplayOptionsOverride
            .currentVisualAcceptance
            .applyAppearance(to: panel)
        self.window = panel
        self.hostingController = controller
        // Capture host + focused-window screen before activation so placement and
        // post-dismiss restore stay bound to the page that opened Preview.
        let presentationContext = TransientPanelPresentationContext.capture()
        Self.center(
            panel,
            on: presentationContext.screen
        )
        panel.alphaValue = 0
        if priorExternalFrontmost == nil {
            priorExternalFrontmost = presentationContext.restoreTarget
        }
        // Activate after capture: Chinese IME candidate windows need an active
        // process, while `.moveToActiveSpace` keeps the panel on the user's
        // current Space instead of jumping to a Settings/History Space.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = VibeComposeMotion.panelAppear
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func runRegenerate(
        skillInstallationID: UUID,
        editedSource: String
    ) async -> Result<PreviewRequest, any Error> {
        guard let regenerate else {
            return .failure(PreviewRegenerateError.unavailable)
        }
        return await regenerate(skillInstallationID, editedSource)
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
        self.hostingController = nil
        self.regenerate = nil
        self.currentInstallationID = nil
        let restoreTarget = priorExternalFrontmost
        priorExternalFrontmost = nil
        if closeWindow {
            window?.orderOut(nil)
            window?.close()
        }
        // After the panel leaves key status, hand focus back to the host app
        // that was frontmost before Preview. Without this, AppKit often keys a
        // still-open Settings window — which feels like a forced jump.
        LaunchAppContext.restoreFrontmostIfNeeded(restoreTarget)
        isFinishing = false
        continuation?.resume(
            returning: decision
        )
    }

    private static func center(
        _ panel: NSPanel,
        on screen: TransientPanelScreen?
    ) {
        guard let screen else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * 0.06
        )
        panel.setFrameOrigin(origin)
    }
}

/// Borderless floating panel that can become key (for TextEditor focus),
/// is draggable by its glass background, and dismisses on Esc.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if TransientPanelKeyRouting.inputMethodHasMarkedText(in: self) {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown,
           modifiers.isEmpty,
           event.keyCode == 53
        {
            // Esc → cancel via window close so the controller finishes cleanly.
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// TextEditor / search fields map Esc to `cancelOperation:`. Keep IME
    /// composition alive; only dismiss once marked text is gone.
    override func cancelOperation(_ sender: Any?) {
        guard TransientPanelKeyRouting.shouldDismissOnCancelOperation(
            hasMarkedText: TransientPanelKeyRouting.inputMethodHasMarkedText(
                in: self
            )
        ) else {
            return
        }
        close()
    }
}

// MARK: - Native macOS 26 glass surface for Preview

private struct PreviewSurfaceComponents {
    let rootView: NSView
    let contentView: NSView
}

/// Builds a panel shell with NSGlassEffectView on macOS 26 (same API as the
/// Compact HUD) and a hudWindow material fallback earlier.
@MainActor
private func makePreviewSurface(
    cornerRadius: CGFloat
) -> PreviewSurfaceComponents {
    let contentView = NSView()
    contentView.wantsLayer = false
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let root = NSView(frame: .zero)
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.clear.cgColor
    root.translatesAutoresizingMaskIntoConstraints = false

    let shell: NSView
    if #available(macOS 26, *) {
        // Near-opaque plate first so wallpaper cannot punch through; glass is
        // layered for the optical edge only (Spotlight / Applications pattern).
        let plate = NSView()
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.wantsLayer = true
        plate.layer?.backgroundColor =
            VibeComposeFloatingChrome.panelPlateNSColor.cgColor
        plate.layer?.cornerRadius = cornerRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.masksToBounds = true

        let glass = NSGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = VibeComposeFloatingChrome.panelGlassTintNSColor
        glass.contentView = contentView

        let stack = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.clear.cgColor
        stack.addSubview(plate)
        stack.addSubview(glass)
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            plate.topAnchor.constraint(equalTo: stack.topAnchor),
            plate.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            glass.topAnchor.constraint(equalTo: stack.topAnchor),
            glass.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
        ])
        shell = stack
    } else {
        let material = NSVisualEffectView()
        material.translatesAutoresizingMaskIntoConstraints = false
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        // Near-opaque plate under the classic material.
        let density = NSView()
        density.translatesAutoresizingMaskIntoConstraints = false
        density.wantsLayer = true
        density.layer?.backgroundColor =
            VibeComposeFloatingChrome.panelPlateNSColor.cgColor
        density.layer?.cornerRadius = cornerRadius
        density.layer?.cornerCurve = .continuous
        material.addSubview(density)
        material.addSubview(contentView)
        NSLayoutConstraint.activate([
            density.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            density.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            density.topAnchor.constraint(equalTo: material.topAnchor),
            density.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: material.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        // Soft elevation under the classic material shell.
        material.layer?.shadowColor = NSColor.black.cgColor
        material.layer?.shadowOpacity = Float(
            VibeComposeFloatingChrome.panelShadowOpacity
        )
        material.layer?.shadowRadius =
            VibeComposeFloatingChrome.panelShadowRadius
        material.layer?.shadowOffset = CGSize(
            width: 0,
            height: -VibeComposeFloatingChrome.panelShadowY / 2
        )
        shell = material
    }

    root.addSubview(shell)
    NSLayoutConstraint.activate([
        shell.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        shell.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        shell.topAnchor.constraint(equalTo: root.topAnchor),
        shell.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    return PreviewSurfaceComponents(
        rootView: root,
        contentView: contentView
    )
}

// MARK: - Layout

/// Floating Result Preview size — compact Spotlight-scale shell.
/// Skill-switch mode reuses the same frame so the panel never jumps.
private enum PreviewLayout {
    static let width: CGFloat = 560
    static let height: CGFloat = 480
    static let resultMinHeight: CGFloat = 148
    static let comparisonMinHeight: CGFloat = 72
    static let comparisonMaxHeight: CGFloat = 140
    static let modePickerWidth: CGFloat = 148
    /// Skill-switch grid: large square tiles, 3-across so most catalogs fit
    /// without vertical scrolling inside the fixed panel.
    static let skillGridColumns = 3
    static let skillCardSpacing: CGFloat = 10
}

// MARK: - Preview content

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
    let onDecision: (PreviewDecision) -> Void
    let onRegenerate: @MainActor (UUID, String) async -> Result<
        PreviewRequest,
        any Error
    >

    @State private var mode: ComparisonMode = .diff
    @State private var editedText: String
    @State private var activeRequest: PreviewRequest
    /// Comparison starts collapsed to keep Result primary; expand for Diff.
    @State private var comparisonExpanded = false
    /// Full-panel skill replacement mode (same frame / position as result).
    @State private var isChoosingSkill = false
    @State private var skillQuery = ""
    /// Keyboard-focused skill in the Change Skill grid (distinct from Current).
    @State private var highlightedSkillInstallationID: UUID?
    @State private var isRegenerating = false
    @State private var regeneratingSkillName: String?
    @State private var regenerateError: String?
    @State private var appeared = false
    @FocusState private var isResultFocused: Bool
    @FocusState private var isSkillSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    init(
        request: PreviewRequest,
        onDecision: @escaping (PreviewDecision) -> Void,
        onRegenerate: @escaping @MainActor (UUID, String) async -> Result<
            PreviewRequest,
            any Error
        >
    ) {
        self.request = request
        self.onDecision = onDecision
        self.onRegenerate = onRegenerate
        _activeRequest = State(initialValue: request)
        _editedText = State(initialValue: request.resultText)
    }

    private var diff: TextDiff {
        TextDiffEngine.diff(
            original: activeRequest.comparisonSource,
            revised: editedText
        )
    }

    private var validation: SkillValidationReport {
        SkillValidatorEngine().validate(
            output: editedText,
            originalText: activeRequest.validationSourceText,
            plan: activeRequest.executionPlan
        )
    }

    private var isEdited: Bool {
        editedText != activeRequest.resultText
    }

    private var isUnreviewedFallback: Bool {
        activeRequest.hasValidatorFallback && !isEdited
    }

    private var hasText: Bool {
        !editedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var canApply: Bool {
        hasText
            && validation.isValid
            && !isUnreviewedFallback
            && !isRegenerating
    }

    private var changeSummary: String {
        L10n.format(
            "%ld additions · %ld removals",
            diff.addedCount,
            diff.removedCount
        )
    }

    private var filteredSkills: [SkillMenuEntry] {
        let choices = activeRequest.skillChoices
        let query = skillQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if query.isEmpty {
            return choices
        }
        return SkillMenuSearch.results(in: choices, matching: query)
    }

    var body: some View {
        Group {
            if isChoosingSkill {
                skillReplacementPanel
                    .transition(.opacity)
            } else {
                resultPanel
                    .transition(.opacity)
            }
        }
        .animation(VibeComposeMotion.panelContent, value: isChoosingSkill)
        .frame(
            width: PreviewLayout.width,
            height: PreviewLayout.height
        )
        // Glass is applied by the AppKit NSGlassEffectView shell so the panel
        // is natively movable by its background. Content stays un-glassed.
        .background(Color.clear)
        .clipShape(
            RoundedRectangle(
                cornerRadius: VibeComposeFloatingChrome.panelCornerRadius,
                style: .continuous
            )
        )
        // Spotlight materialize: tiny scale + fade, not a bouncy card.
        .scaleEffect(
            appeared
                ? 1.0
                : (reduceMotion ? 1.0 : VibeComposeMotion.panelEntranceScale),
            anchor: .center
        )
        .opacity(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.0))
        .animation(VibeComposeMotion.panelSpring, value: appeared)
        .onAppear {
            appeared = true
            // Prefer focus on the editable result so the user can refine immediately.
            isResultFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isChoosingSkill
                ? L10n.text("Change Skill")
                : L10n.text("VibeCompose Preview")
        )
    }

    // MARK: - Result surface

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultHeader
            softDivider
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: VibeComposeMetrics.space14
                ) {
                    if let regenerateError {
                        regenerateErrorBanner(regenerateError)
                    } else if activeRequest.hasValidatorFallback, !isRegenerating {
                        fallbackNotice
                    }
                    if isRegenerating {
                        regeneratingResultBody
                    } else {
                        resultSection
                        comparisonSection
                    }
                }
                .padding(.horizontal, VibeComposeMetrics.space20)
                .padding(.vertical, VibeComposeMetrics.space14)
            }
            softDivider
            actions
        }
    }

    // MARK: - Full-panel skill replacement (same frame)

    private var skillReplacementPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            skillReplacementHeader
            softDivider
            skillSearchField
                .padding(.horizontal, VibeComposeMetrics.space20)
                .padding(.top, VibeComposeMetrics.space14)
                .padding(.bottom, VibeComposeMetrics.space10)

            if filteredSkills.isEmpty {
                VStack(spacing: VibeComposeMetrics.space8) {
                    Spacer(minLength: 0)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(L10n.text("No matching skills"))
                        .font(VibeComposeTypography.callout(.medium))
                        .foregroundStyle(
                            Color(nsColor: VibeComposePalette.floatingSecondaryText)
                        )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, VibeComposeMetrics.space20)
            } else {
                skillCardGrid
                    .padding(.horizontal, VibeComposeMetrics.space20)
                    .padding(.bottom, VibeComposeMetrics.space16)
            }
        }
        .onAppear {
            isSkillSearchFocused = true
        }
    }

    private var skillReplacementHeader: some View {
        HStack(alignment: .center, spacing: VibeComposeMetrics.space12) {
            headerIconButton(
                systemName: "chevron.left",
                tint: .secondary,
                help: L10n.text("Back")
            ) {
                exitSkillChooser()
            }
            .disabled(isRegenerating)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Change Skill"))
                    .font(VibeComposeTypography.title2())
                    .foregroundStyle(
                        Color(nsColor: VibeComposePalette.floatingPrimaryText)
                    )
                Text(
                    L10n.format(
                        "Current: %@",
                        activeRequest.skillName
                    )
                )
                .font(VibeComposeTypography.caption())
                .foregroundStyle(
                    Color(nsColor: VibeComposePalette.floatingSecondaryText)
                )
                .lineLimit(1)
            }

            Spacer(minLength: VibeComposeMetrics.space8)

            headerIconButton(
                systemName: "xmark",
                tint: .secondary,
                help: L10n.text("Cancel")
            ) {
                if isRegenerating { return }
                onDecision(.cancel)
            }
            .disabled(isRegenerating)
        }
        .padding(.horizontal, VibeComposeMetrics.space20)
        .padding(.vertical, VibeComposeMetrics.space14)
    }

    private var skillSearchField: some View {
        HStack(spacing: VibeComposeMetrics.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(
                L10n.text("Search Skills…"),
                text: $skillQuery
            )
            .textFieldStyle(.plain)
            .font(VibeComposeTypography.callout())
            .focused($isSkillSearchFocused)
            .disabled(isRegenerating)
            .onSubmit {
                commitHighlightedSkill()
            }
            if !skillQuery.isEmpty {
                Button {
                    skillQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Clear search"))
            }
        }
        .padding(.horizontal, VibeComposeMetrics.space12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .fill(
                Color(nsColor: VibeComposePalette.floatingContentSurface)
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var skillCardGrid: some View {
        let columns = Array(
            repeating: GridItem(
                .flexible(),
                spacing: PreviewLayout.skillCardSpacing
            ),
            count: PreviewLayout.skillGridColumns
        )
        // Prefer fitting the catalog in the fixed panel: measure remaining
        // height loosely and let each tile become a square box. Scroll only
        // when there are more skills than one screen of large cards.
        return GeometryReader { geo in
            let spacing = PreviewLayout.skillCardSpacing
            let columnsCount = CGFloat(PreviewLayout.skillGridColumns)
            let cardSide = max(
                96,
                floor(
                    (geo.size.width - spacing * (columnsCount - 1))
                        / columnsCount
                )
            )
            let rows = ceil(
                Double(filteredSkills.count) / Double(PreviewLayout.skillGridColumns)
            )
            let contentHeight =
                CGFloat(rows) * cardSide
                + CGFloat(max(rows - 1, 0)) * spacing
            let needsScroll = contentHeight > geo.size.height + 1

            Group {
                if needsScroll {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(filteredSkills) { entry in
                                skillCard(entry, side: cardSide)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(filteredSkills) { entry in
                            skillCard(entry, side: cardSide)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .focusable(!isRegenerating)
            .vibeComposeSuppressFocusRing()
            .onMoveCommand { direction in
                moveSkillHighlight(direction)
            }
            .onExitCommand {
                exitSkillChooser()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            ensureSkillHighlight()
        }
        .onChange(of: skillQuery) { _ in
            ensureSkillHighlight()
        }
    }

    private func ensureSkillHighlight() {
        let ids = filteredSkills.map(\.installationID)
        if let highlightedSkillInstallationID,
           ids.contains(highlightedSkillInstallationID)
        {
            return
        }
        // Prefer first non-current skill so Return always has an actionable target.
        highlightedSkillInstallationID =
            filteredSkills.first(where: {
                $0.installationID != activeRequest.currentSkillInstallationID
            })?.installationID
            ?? filteredSkills.first?.installationID
    }

    private func moveSkillHighlight(_ direction: MoveCommandDirection) {
        let skills = filteredSkills
        guard !skills.isEmpty else { return }
        let columns = PreviewLayout.skillGridColumns
        let currentIndex =
            skills.firstIndex(where: {
                $0.installationID == highlightedSkillInstallationID
            }) ?? 0
        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = max(0, currentIndex - 1)
        case .right:
            nextIndex = min(skills.count - 1, currentIndex + 1)
        case .up:
            nextIndex = max(0, currentIndex - columns)
        case .down:
            nextIndex = min(skills.count - 1, currentIndex + columns)
        @unknown default:
            return
        }
        highlightedSkillInstallationID = skills[nextIndex].installationID
    }

    private func commitHighlightedSkill() {
        guard !isRegenerating else { return }
        guard
            let highlightedSkillInstallationID,
            let entry = filteredSkills.first(where: {
                $0.installationID == highlightedSkillInstallationID
            }),
            entry.installationID != activeRequest.currentSkillInstallationID
        else {
            return
        }
        Task { @MainActor in
            await pickSkill(entry)
        }
    }

    private func skillCard(
        _ entry: SkillMenuEntry,
        side: CGFloat
    ) -> some View {
        let isCurrent =
            entry.installationID == activeRequest.currentSkillInstallationID
        let isHighlighted =
            entry.installationID == highlightedSkillInstallationID
        let presentation = entry.presentation
        let accent = Color(nsColor: presentation.accent)
        return Button {
            Task { @MainActor in
                await pickSkill(entry)
            }
        } label: {
            VStack(spacing: VibeComposeMetrics.space10) {
                SkillIdentityIcon(
                    entry: entry,
                    size: 44,
                    symbolSize: 18,
                    isEmphasized: isCurrent || isHighlighted
                )

                VStack(spacing: 3) {
                    Text(entry.displayName)
                        .font(
                            VibeComposeTypography.callout(
                                isCurrent || isHighlighted ? .semibold : .medium
                            )
                        )
                        .foregroundStyle(
                            Color(nsColor: VibeComposePalette.floatingPrimaryText)
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if isCurrent {
                        Text(L10n.text("Current"))
                            .font(VibeComposeTypography.micro(.semibold))
                            .foregroundStyle(accent)
                    } else if !entry.summary.isEmpty {
                        Text(entry.summary)
                            .font(VibeComposeTypography.micro())
                            .foregroundStyle(
                                Color(
                                    nsColor: VibeComposePalette
                                        .floatingSecondaryText
                                )
                            )
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(VibeComposeMetrics.space12)
            .frame(width: side, height: side, alignment: .top)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusL,
                    style: .continuous
                )
            )
            .background {
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusL,
                    style: .continuous
                )
                .fill(
                    Color(nsColor: VibeComposePalette.floatingContentSurface)
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusL,
                    style: .continuous
                )
                .stroke(
                    isCurrent
                        ? accent.opacity(0.55)
                        : (
                            isHighlighted
                                ? accent.opacity(0.85)
                                : Color.primary.opacity(0.10)
                        ),
                    lineWidth: isCurrent || isHighlighted ? 1.5 : 0.5
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || isRegenerating)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(
            isCurrent
                ? L10n.text("Current skill")
                : L10n.text("Regenerate with this skill")
        )
        .accessibilityAddTraits(
            (isCurrent || isHighlighted) ? .isSelected : []
        )
    }

    private func enterSkillChooser() {
        skillQuery = ""
        isResultFocused = false
        ensureSkillHighlight()
        withAnimation(VibeComposeMotion.panelContent) {
            isChoosingSkill = true
        }
    }

    private func exitSkillChooser() {
        skillQuery = ""
        isSkillSearchFocused = false
        highlightedSkillInstallationID = nil
        withAnimation(VibeComposeMotion.panelContent) {
            isChoosingSkill = false
        }
        isResultFocused = true
    }

    private var softDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.5)
    }

    // MARK: - Result header

    private var resultHeader: some View {
        let presentation = SkillPresentation.forSkillID(
            activeRequest.skillID
        )
        return HStack(alignment: .center, spacing: VibeComposeMetrics.space12) {
            VibeComposeIconWell(
                systemName: presentation.symbolName,
                size: VibeComposeMetrics.iconWellSize,
                symbolSize: 14,
                tint: Color(nsColor: presentation.accent)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(activeRequest.skillName)
                    .font(VibeComposeTypography.title2())
                    .foregroundStyle(
                        Color(nsColor: VibeComposePalette.floatingPrimaryText)
                    )
                    .lineLimit(1)
                Text(
                    L10n.format(
                        "%@ · %@",
                        activeRequest.sourceLabel,
                        activeRequest.resolutionLabel
                    )
                )
                .font(VibeComposeTypography.caption())
                .foregroundStyle(
                    Color(nsColor: VibeComposePalette.floatingSecondaryText)
                )
                .lineLimit(1)
            }

            Spacer(minLength: VibeComposeMetrics.space8)

            generationBadge

            if !activeRequest.skillChoices.isEmpty {
                headerIconButton(
                    systemName: "arrow.triangle.2.circlepath",
                    tint: Color(nsColor: VibeComposePalette.brandBlue),
                    help: L10n.text("Change Skill")
                ) {
                    enterSkillChooser()
                }
                .disabled(isRegenerating)
            }

            headerIconButton(
                systemName: "xmark",
                tint: .secondary,
                help: L10n.text("Cancel")
            ) {
                onDecision(.cancel)
            }
        }
        .padding(.horizontal, VibeComposeMetrics.space20)
        .padding(.vertical, VibeComposeMetrics.space14)
    }

    @MainActor
    private func pickSkill(_ entry: SkillMenuEntry) async {
        guard !isRegenerating else { return }
        if entry.installationID == activeRequest.currentSkillInstallationID {
            exitSkillChooser()
            return
        }
        isResultFocused = false
        isSkillSearchFocused = false
        regenerateError = nil
        regeneratingSkillName = entry.displayName
        // Apple-style: leave the chooser and show a quiet loading state on
        // the result panel (the parent surface), not a modal overlay.
        withAnimation(VibeComposeMotion.panelContent) {
            isChoosingSkill = false
            isRegenerating = true
        }
        let result = await onRegenerate(
            entry.installationID,
            editedText
        )
        isRegenerating = false
        regeneratingSkillName = nil
        switch result {
        case .success(let next):
            applyRegenerated(next)
        case .failure(let error):
            regenerateError = error.localizedDescription
            // Stay on the result panel with the error banner; user can
            // reopen Change Skill to try again.
            NSSound.beep()
            isResultFocused = true
        }
    }

    private func applyRegenerated(_ next: PreviewRequest) {
        activeRequest = next
        editedText = next.resultText
        comparisonExpanded = false
        mode = .diff
        skillQuery = ""
        regenerateError = nil
        isChoosingSkill = false
        isResultFocused = true
    }

    private var generationBadge: some View {
        Text(editStateLabel)
            .font(VibeComposeTypography.micro(.semibold))
            .foregroundStyle(editStateForeground)
            .padding(.horizontal, VibeComposeMetrics.space8)
            .padding(.vertical, VibeComposeMetrics.space4)
            .background(
                Capsule(style: .continuous)
                    .fill(editStateForeground.opacity(0.12))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(editStateForeground.opacity(0.16), lineWidth: 0.5)
            }
    }

    private var editStateLabel: String {
        if isRegenerating {
            return L10n.text("Regenerating…")
        }
        if isEdited {
            return L10n.text("Edited by you")
        }
        if activeRequest.hasValidatorFallback {
            return L10n.text("Fallback transcript")
        }
        return L10n.text("AI generated")
    }

    private var editStateForeground: Color {
        if isRegenerating {
            return Color(nsColor: VibeComposePalette.brandBlue)
        }
        if activeRequest.hasValidatorFallback && !isEdited {
            return Color(nsColor: VibeComposePalette.amber)
        }
        if isEdited {
            return Color(nsColor: VibeComposePalette.brandBlue)
        }
        return .secondary
    }

    private func headerIconButton(
        systemName: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            Color(
                                nsColor: VibeComposePalette.floatingContentSurfaceQuiet
                            )
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Regenerating (inline on result panel)

    /// Quiet, Apple-style loading: same Result chrome, content replaced by a
    /// centered ProgressView + short caption. No modal card, blur, or halo.
    private var regeneratingResultBody: some View {
        VStack(spacing: VibeComposeMetrics.space14) {
            Spacer(minLength: VibeComposeMetrics.space28)
            ProgressView()
                .controlSize(.small)
            Text(L10n.text("Regenerating…"))
                .font(VibeComposeTypography.callout(.medium))
                .foregroundStyle(
                    Color(nsColor: VibeComposePalette.floatingPrimaryText)
                )
            Text(
                L10n.format(
                    "Applying %@",
                    regeneratingSkillName ?? activeRequest.skillName
                )
            )
            .font(VibeComposeTypography.caption())
            .foregroundStyle(
                Color(nsColor: VibeComposePalette.floatingSecondaryText)
            )
            .lineLimit(1)
            Spacer(minLength: VibeComposeMetrics.space28)
        }
        .frame(maxWidth: .infinity, minHeight: PreviewLayout.resultMinHeight + 80)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("Regenerating…"))
        .accessibilityValue(
            L10n.format(
                "Applying %@",
                regeneratingSkillName ?? activeRequest.skillName
            )
        )
    }

    private func regenerateErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: VibeComposeMetrics.space10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
                .padding(.top, 1)
            Text(message)
                .font(VibeComposeTypography.caption())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                regenerateError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Dismiss"))
        }
        .padding(VibeComposeMetrics.space12)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .fill(Color(nsColor: VibeComposePalette.amber).opacity(0.10))
        )
    }

    // MARK: - Notices

    private var fallbackNotice: some View {
        HStack(alignment: .top, spacing: VibeComposeMetrics.space10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
                .padding(.top, 1)
            Text(
                L10n.text(
                    "Skill checks failed — review the transcript, then paste or copy."
                )
            )
            .font(VibeComposeTypography.caption())
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(VibeComposeMetrics.space12)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .fill(Color(nsColor: VibeComposePalette.amber).opacity(0.10))
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.amber).opacity(0.18),
                lineWidth: 0.5
            )
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Result (primary)

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space8) {
            HStack(alignment: .center, spacing: VibeComposeMetrics.space8) {
                Text(L10n.text("Result"))
                    .font(VibeComposeTypography.caption(.semibold))
                    .foregroundStyle(
                        Color(nsColor: VibeComposePalette.floatingSecondaryText)
                    )
                    .textCase(.uppercase)
                    .tracking(0.4)

                Spacer(minLength: 0)

                if isEdited, !isRegenerating {
                    Button(L10n.text("Reset")) {
                        editedText = activeRequest.resultText
                    }
                    .buttonStyle(.plain)
                    .font(VibeComposeTypography.micro(.semibold))
                    .foregroundStyle(
                        Color(nsColor: VibeComposePalette.brandBlue)
                    )
                }

                Text(
                    L10n.format("%ld characters", editedText.count)
                )
                .font(VibeComposeTypography.micro())
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }

            TextEditor(text: $editedText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(
                    Color(nsColor: VibeComposePalette.floatingPrimaryText)
                )
                .scrollContentBackground(.hidden)
                .focused($isResultFocused)
                .frame(
                    minHeight: PreviewLayout.resultMinHeight,
                    idealHeight: 188
                )
                .padding(VibeComposeMetrics.space12)
                .background(
                    RoundedRectangle(
                        cornerRadius: VibeComposeMetrics.radiusL,
                        style: .continuous
                    )
                    .fill(
                        Color(
                            nsColor: VibeComposePalette.floatingContentSurface
                        )
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: VibeComposeMetrics.radiusL,
                        style: .continuous
                    )
                    .stroke(
                        isResultFocused
                            ? Color(nsColor: VibeComposePalette.brandBlue)
                                .opacity(0.55)
                            : Color.primary.opacity(0.12),
                        lineWidth: isResultFocused ? 1.0 : 0.5
                    )
                }
                .animation(
                    VibeComposeMotion.panelContent,
                    value: isResultFocused
                )
                .accessibilityLabel(L10n.text("Result"))
                .disabled(isRegenerating)

            if !validation.isValid {
                Text(
                    L10n.format(
                        "Fix before paste: %@",
                        validation.issues
                            .map(\.code.rawValue)
                            .joined(separator: ", ")
                    )
                )
                .font(VibeComposeTypography.micro())
                .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
            }
        }
    }

    // MARK: - Comparison (secondary, collapsible)

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space8) {
            HStack(spacing: VibeComposeMetrics.space8) {
                Button {
                    withAnimation(VibeComposeMotion.panelContent) {
                        comparisonExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName: comparisonExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                        Text(L10n.text("Comparison"))
                            .font(VibeComposeTypography.caption(.semibold))
                            .foregroundStyle(
                                Color(
                                    nsColor: VibeComposePalette
                                        .floatingSecondaryText
                                )
                            )
                            .textCase(.uppercase)
                            .tracking(0.4)

                        Text(changeSummary)
                            .font(VibeComposeTypography.micro())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.format(
                        "%@ — %@",
                        L10n.text("Comparison"),
                        changeSummary
                    )
                )

                Spacer(minLength: 0)

                if comparisonExpanded {
                    Picker(
                        L10n.text("Preview content"),
                        selection: $mode
                    ) {
                        ForEach(ComparisonMode.allCases) { mode in
                            Text(L10n.text(mode.rawValue)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: PreviewLayout.modePickerWidth)
                }
            }

            if comparisonExpanded {
                Group {
                    switch mode {
                    case .diff:
                        diffView
                    case .source:
                        readOnlyText(activeRequest.comparisonSource)
                    }
                }
                .frame(
                    minHeight: PreviewLayout.comparisonMinHeight,
                    maxHeight: PreviewLayout.comparisonMaxHeight
                )
                .transition(.opacity)
            }
        }
    }

    private var diffView: some View {
        ScrollView {
            Text(diffAttributed)
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(VibeComposeMetrics.space12)
        }
        .background(surfaceBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(changeSummary)
    }

    private var diffAttributed: AttributedString {
        var result = AttributedString()
        for (index, segment) in diff.segments.enumerated() {
            // Non-color channel (+/− prefix) so Diff is not color-only.
            let marker: String
            switch segment.kind {
            case .unchanged:
                marker = ""
            case .added:
                marker = "+ "
            case .removed:
                marker = "− "
            }
            var piece = AttributedString(marker + segment.text)
            switch segment.kind {
            case .unchanged:
                piece.foregroundColor = .primary
            case .added:
                piece.foregroundColor = Color(
                    nsColor: VibeComposePalette.success
                )
                piece.backgroundColor = Color(
                    nsColor: VibeComposePalette.success
                ).opacity(0.12)
            case .removed:
                piece.foregroundColor = Color(
                    nsColor: VibeComposePalette.error
                )
                piece.strikethroughStyle = .single
                piece.backgroundColor = Color(
                    nsColor: VibeComposePalette.error
                ).opacity(0.10)
            }
            result.append(piece)
            if index < diff.segments.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        return result
    }

    private func readOnlyText(_ value: String) -> some View {
        ScrollView {
            Text(value)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(VibeComposeMetrics.space12)
        }
        .background(surfaceBackground)
    }

    private var surfaceBackground: some View {
        RoundedRectangle(
            cornerRadius: VibeComposeMetrics.radiusL,
            style: .continuous
        )
        .fill(
            Color(nsColor: VibeComposePalette.floatingContentSurface)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusL,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: VibeComposeMetrics.space10) {
            Button(L10n.text("Cancel")) {
                onDecision(.cancel)
            }
            .buttonStyle(.plain)
            .font(VibeComposeTypography.callout(.medium))
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, VibeComposeMetrics.space10)
            .padding(.vertical, VibeComposeMetrics.space6)
            .disabled(isRegenerating)

            Button(L10n.text("Copy")) {
                onDecision(.copy(text: editedText))
            }
            .buttonStyle(.plain)
            .font(VibeComposeTypography.callout(.medium))
            .foregroundStyle(.primary)
            .disabled(!hasText || isRegenerating)
            .padding(.horizontal, VibeComposeMetrics.space12)
            .padding(.vertical, VibeComposeMetrics.space6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color(
                            nsColor: VibeComposePalette.floatingContentSurfaceQuiet
                        )
                        .opacity(hasText && !isRegenerating ? 1.0 : 0.55)
                    )
            )

            Spacer(minLength: 0)

            primaryAction
        }
        .padding(.horizontal, VibeComposeMetrics.space20)
        .padding(.vertical, VibeComposeMetrics.space14)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if activeRequest.allowsSelectionReplacement {
            Button(L10n.text("Replace Selection")) {
                onDecision(.replaceSelection(text: editedText))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        } else if activeRequest.allowsPasteToTarget {
            Button(L10n.text("Paste to Target")) {
                onDecision(.pasteToTarget(text: editedText))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }
}
