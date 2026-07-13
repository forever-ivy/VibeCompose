import Foundation
import Testing
@testable import OpenWhisper

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
        skillVersion: "1.0.0",
        skillName: "Context Rewrite",
        originalTranscript:
            "shorten this",
        resultText: "New text",
        selectedText: "Old text",
        contextCapabilities: [
            .selection,
        ],
        validationPassed: true,
        allowsSelectionReplacement:
            true
    )

    #expect(
        request.comparisonSource
            == "Old text"
    )
}
