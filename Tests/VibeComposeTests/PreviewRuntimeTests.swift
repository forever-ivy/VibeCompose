import Foundation
import Testing
@testable import VibeCompose

@Test
func outputRouterEnforcesSkillDeliveryAndRetryBoundaries() {
    let resolver = SkillResolver()
    let config = SkillsConfig()

    let direct = resolver.resolve(
        manualSkillID:
            SkillRegistry.directSkillID,
        config: config,
        launchAppContext: nil
    )
    let email = resolver.resolve(
        manualSkillID:
            SkillRegistry.emailSkillID,
        config: config,
        launchAppContext: nil
    )
    let contextRewrite =
        resolver.resolve(
            manualSkillID:
                SkillRegistry
                    .contextRewriteSkillID,
            config: config,
            launchAppContext: nil
        )
    let router = OutputRouter()

    #expect(
        router.route(
            plan: direct,
            automaticPasteAllowed: true,
            hasSelectionContext: false
        ) == .automatic
    )
    #expect(
        router.route(
            plan: direct,
            automaticPasteAllowed: true,
            hasSelectionContext: true
        ) == .preview
    )
    #expect(
        router.route(
            plan: email,
            automaticPasteAllowed: true,
            hasSelectionContext: false
        ) == .preview
    )
    #expect(
        router.route(
            plan: contextRewrite,
            automaticPasteAllowed: false,
            hasSelectionContext: true
        ) == .copyOnly
    )
    // User preference: skip Preview for ordinary insert-only Skill results.
    #expect(
        router.route(
            plan: email,
            automaticPasteAllowed: true,
            hasSelectionContext: false,
            skipPreviewWhenSafe: true
        ) == .automatic
    )
    // Selection rewrite still forces Preview even when the skip is enabled.
    #expect(
        router.route(
            plan: contextRewrite,
            automaticPasteAllowed: true,
            hasSelectionContext: true,
            skipPreviewWhenSafe: true
        ) == .preview
    )
    // High-risk still forces Preview.
    #expect(
        router.route(
            plan: email,
            automaticPasteAllowed: true,
            hasSelectionContext: false,
            additionalRisk: .high,
            skipPreviewWhenSafe: true
        ) == .preview
    )
}

@Test
func textDiffEngineReportsAddedRemovedAndUnchangedSegments() {
    let diff = TextDiffEngine.diff(
        original:
            "keep old value",
        revised:
            "keep new value"
    )

    #expect(diff.addedCount == 1)
    #expect(diff.removedCount == 1)
    #expect(
        diff.segments.contains {
            $0.kind == .unchanged
                && $0.text.contains(
                    "keep"
                )
        }
    )
    #expect(
        diff.segments.contains {
            $0.kind == .removed
                && $0.text == "old"
        }
    )
    #expect(
        diff.segments.contains {
            $0.kind == .added
                && $0.text == "new"
        }
    )
}

@Test
func previewRequestUsesSelectionAsDiffSourceWhenAvailable() {
    let request = PreviewRequest(
        skillID:
            SkillRegistry
                .contextRewriteSkillID,
        skillVersion: "1.1.0",
        skillName: "Context Rewrite",
        originalTranscript:
            "shorten this",
        resultText: "New text",
        selectedText: "Old text",
        contextCapabilities: [
            .selection,
        ],
        allowsSelectionReplacement:
            true
    )

    #expect(
        request.comparisonSource
            == "Old text"
    )
    #expect(request.allowsSelectionReplacement)
}

@Test
func optionalSelectionIsSupportingPreviewContext() {
    let request = PreviewRequest(
        skillID:
            SkillRegistry
                .commitMessageSkillID,
        skillVersion: "1.1.0",
        skillName: "Commit Message",
        originalTranscript:
            "Describe the authentication fix.",
        resultText:
            "Fix authentication retry",
        selectedText:
            "Supporting diff context",
        contextCapabilities: [
            .selection,
        ],
        allowsSelectionReplacement: true
    )

    #expect(
        request.comparisonSource
            == "Describe the authentication fix."
    )
    #expect(
        request.validationSourceText
            == "Describe the authentication fix."
    )
    #expect(!request.allowsSelectionReplacement)
}

@Test
func textDiffEngineUsesCharacterGranularityForCJKText() {
    let diff = TextDiffEngine.diff(
        original: "请保留发布日期。",
        revised: "请保留版本号。"
    )

    #expect(diff.addedCount == 3)
    #expect(diff.removedCount == 4)
    #expect(
        diff.segments.contains {
            $0.kind == .unchanged
                && $0.text.contains("请保留")
        }
    )
    #expect(
        diff.segments.contains {
            $0.kind == .added
                && $0.text == "版本号"
        }
    )
}

@Test
func previewDecisionCarriesTheFinalEditedText() {
    let decision = PreviewDecision
        .replaceSelection(
            text: "Edited result"
        )

    #expect(decision.action == .replaceSelection)
    #expect(decision.finalText == "Edited result")
    #expect(PreviewDecision.cancel.finalText == nil)
    #expect(
        PreviewDecision.changeSkill(
            editedSource: "draft"
        ).finalText == nil
    )
    #expect(
        PreviewDecision.changeSkill(
            editedSource: "draft"
        ).action == nil
    )
}
