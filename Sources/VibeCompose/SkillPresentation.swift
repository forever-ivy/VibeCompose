import AppKit
import Foundation
import SwiftUI

/// Visual family for Skill identity chrome (accent, atmosphere). Shared by
/// Library, Switcher, Preview, Settings, and menus — not per-surface one-offs.
enum SkillPresentationFamily: String, Sendable, Equatable {
    case faithful
    case conversational
    case compose
    case structure
    case technical
    case transform
    case generic

    var accent: NSColor {
        switch self {
        case .faithful:
            return VibeComposePalette.brandBlue
        case .conversational:
            return VibeComposePalette.brandSpectrumCoral
        case .compose:
            return VibeComposePalette.brandSpectrumViolet
        case .structure:
            return VibeComposePalette.brandSpectrumAmber
        case .technical:
            return VibeComposePalette.brandSpectrumCyan
        case .transform:
            return VibeComposePalette.atmospherePeriwinkle
        case .generic:
            return VibeComposePalette.brandBlue
        }
    }

    /// Second stop for atmospheric banner gradients.
    var atmosphereSecondary: NSColor {
        switch self {
        case .faithful:
            return VibeComposePalette.atmosphereDeep
        case .conversational:
            return VibeComposePalette.brandSpectrumAmber
        case .compose:
            return VibeComposePalette.atmosphereIndigo
        case .structure:
            return VibeComposePalette.brandSpectrumCoral
        case .technical:
            return VibeComposePalette.brandSpectrumSky
        case .transform:
            return VibeComposePalette.atmosphereLavender
        case .generic:
            return VibeComposePalette.atmosphereIndigo
        }
    }
}

enum SkillShowcaseMode: String, Sendable, Equatable {
    /// Plain-text Say → Get transformation.
    case transform
    /// Markdown multi-section outline.
    case structure
    /// Message / letter-style compose sheet.
    case compose
}

/// Single source of truth for Skill identity symbols and visual family.
/// Surfaces may change size/weight, not the symbol name for a given Skill ID.
struct SkillPresentation: Sendable, Equatable {
    let family: SkillPresentationFamily
    let showcase: SkillShowcaseMode
    /// SF Symbol name — same string everywhere (Library, Switcher, Preview, menu).
    let symbolName: String

    var accent: NSColor { family.accent }
    var atmosphereSecondary: NSColor { family.atmosphereSecondary }

    /// Badge when the Skill requires selected text. Never replaces `symbolName`.
    static let selectionRequirementSymbol = "selection.pin.in.out"

    static func forSkill(_ skill: SkillDefinition) -> SkillPresentation {
        forSkillID(skill.id, outputFormat: skill.output.format)
    }

    static func forMenuEntry(_ entry: SkillMenuEntry) -> SkillPresentation {
        forSkillID(entry.skillID)
    }

    static func forSkillID(
        _ id: String,
        outputFormat: SkillOutputFormat = .plainText
    ) -> SkillPresentation {
        switch id {
        case SkillRegistry.directSkillID:
            return .init(
                family: .faithful,
                showcase: .transform,
                symbolName: "text.cursor"
            )
        case SkillRegistry.replySkillID:
            return .init(
                family: .conversational,
                showcase: .transform,
                symbolName: "arrowshape.turn.up.left.fill"
            )
        case SkillRegistry.emailSkillID:
            return .init(
                family: .compose,
                showcase: .compose,
                symbolName: "envelope.fill"
            )
        case SkillRegistry.codePromptSkillID:
            return .init(
                family: .technical,
                showcase: .transform,
                symbolName: "chevron.left.forwardslash.chevron.right"
            )
        case SkillRegistry.translateSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "character.bubble.fill"
            )
        case SkillRegistry.contextRewriteSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "text.badge.checkmark"
            )
        case SkillRegistry.bugReportSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "ladybug.fill"
            )
        case SkillRegistry.commitMessageSkillID:
            return .init(
                family: .technical,
                showcase: .transform,
                symbolName: "point.topleft.down.curvedto.point.bottomright.up.fill"
            )
        case SkillRegistry.meetingActionItemsSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "checklist"
            )
        case SkillRegistry.productBriefSkillID:
            return .init(
                family: .compose,
                showcase: .structure,
                symbolName: "doc.text.fill"
            )
        case SkillRegistry.customerSupportReplySkillID:
            return .init(
                family: .conversational,
                showcase: .compose,
                symbolName: "bubble.left.and.bubble.right.fill"
            )
        case SkillRegistry.contextSummarizeSkillID:
            return .init(
                family: .transform,
                showcase: .structure,
                symbolName: "text.redaction"
            )
        case SkillRegistry.standupUpdateSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "person.3.sequence.fill"
            )
        case SkillRegistry.changelogEntrySkillID:
            return .init(
                family: .technical,
                showcase: .structure,
                symbolName: "list.bullet.rectangle"
            )
        case SkillRegistry.betterQuestionSkillID:
            return .init(
                family: .conversational,
                showcase: .compose,
                symbolName: "questionmark.bubble.fill"
            )
        case SkillRegistry.codeReviewCommentSkillID:
            return .init(
                family: .technical,
                showcase: .compose,
                symbolName: "text.bubble.fill"
            )
        case SkillRegistry.socialPostSkillID:
            return .init(
                family: .compose,
                showcase: .compose,
                symbolName: "square.and.arrow.up"
            )
        case SkillRegistry.frontendPromptSkillID:
            return .init(
                family: .technical,
                showcase: .structure,
                symbolName: "rectangle.3.group.fill"
            )
        case SkillRegistry.clipboardRewriteSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "doc.on.clipboard.fill"
            )
        case SkillRegistry.paragraphPolishSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "text.alignleft"
            )
        case SkillRegistry.incidentReportSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "exclamationmark.triangle.fill"
            )
        default:
            let showcase: SkillShowcaseMode =
                outputFormat == .markdown ? .structure : .transform
            return .init(
                family: .generic,
                showcase: showcase,
                symbolName: "wand.and.stars"
            )
        }
    }

    /// Template-sized NSImage for AppKit menus and legacy controls.
    func menuImage(pointSize: CGFloat = 13) -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        ) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        return image.withSymbolConfiguration(config) ?? image
    }
}

extension SkillDefinition {
    /// Brand-forward SF Symbol for this Skill (same as every other surface).
    var vibeComposeSymbol: String {
        SkillPresentation.forSkill(self).symbolName
    }

    var presentation: SkillPresentation {
        SkillPresentation.forSkill(self)
    }
}

extension SkillMenuEntry {
    var presentation: SkillPresentation {
        SkillPresentation.forMenuEntry(self)
    }

    var symbolName: String {
        presentation.symbolName
    }
}

/// Shared Skill identity well: primary SF Symbol + optional selection badge.
/// All list/grid Skill icons should use this (or `VibeComposeIconWell` with
/// `presentation.symbolName`) so symbol names stay consistent.
struct SkillIdentityIcon: View {
    let presentation: SkillPresentation
    var requiresSelection: Bool = false
    var size: CGFloat = 28
    var symbolSize: CGFloat = 12
    var isEmphasized: Bool = false

    init(
        presentation: SkillPresentation,
        requiresSelection: Bool = false,
        size: CGFloat = 28,
        symbolSize: CGFloat = 12,
        isEmphasized: Bool = false
    ) {
        self.presentation = presentation
        self.requiresSelection = requiresSelection
        self.size = size
        self.symbolSize = symbolSize
        self.isEmphasized = isEmphasized
    }

    init(
        skillID: String,
        requiresSelection: Bool = false,
        outputFormat: SkillOutputFormat = .plainText,
        size: CGFloat = 28,
        symbolSize: CGFloat = 12,
        isEmphasized: Bool = false
    ) {
        self.presentation = SkillPresentation.forSkillID(
            skillID,
            outputFormat: outputFormat
        )
        self.requiresSelection = requiresSelection
        self.size = size
        self.symbolSize = symbolSize
        self.isEmphasized = isEmphasized
    }

    init(
        entry: SkillMenuEntry,
        size: CGFloat = 28,
        symbolSize: CGFloat = 12,
        isEmphasized: Bool = false
    ) {
        self.presentation = entry.presentation
        self.requiresSelection = entry.requiresSelection
        self.size = size
        self.symbolSize = symbolSize
        self.isEmphasized = isEmphasized
    }

    private var accent: Color {
        Color(nsColor: presentation.accent)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: size, height: size)
                .background(
                    accent.opacity(isEmphasized ? 0.20 : 0.12),
                    in: RoundedRectangle(
                        cornerRadius: size * 0.28,
                        style: .continuous
                    )
                )

            if requiresSelection {
                Image(systemName: SkillPresentation.selectionRequirementSymbol)
                    .font(.system(size: max(8, symbolSize * 0.55), weight: .bold))
                    .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
                    .padding(2)
                    .background(
                        Circle()
                            .fill(Color(nsColor: VibeComposePalette.elevatedSurface))
                    )
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Browse taxonomy

/// Product taxonomy for Skill browsing surfaces (Library grid, Switcher
/// palette). Case order is the display order and mirrors the built-in
/// catalog's package grouping; community-installed Skills come last.
enum SkillCategory:
    String,
    CaseIterable,
    Identifiable,
    Sendable,
    Equatable
{
    case dictation
    case rewrite
    case developer
    case documents
    case communication
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            return L10n.text("Dictation")
        case .rewrite:
            return L10n.text("Rewrite")
        case .developer:
            return L10n.text("Developer")
        case .documents:
            return L10n.text("Documents")
        case .communication:
            return L10n.text("Communication")
        case .community:
            return L10n.text("Community")
        }
    }

    static func forSkillID(_ id: String) -> SkillCategory {
        switch id {
        case SkillRegistry.directSkillID,
             SkillRegistry.replySkillID,
             SkillRegistry.emailSkillID,
             SkillRegistry.translateSkillID:
            return .dictation
        case SkillRegistry.contextRewriteSkillID,
             SkillRegistry.contextSummarizeSkillID,
             SkillRegistry.clipboardRewriteSkillID,
             SkillRegistry.paragraphPolishSkillID:
            return .rewrite
        case SkillRegistry.codePromptSkillID,
             SkillRegistry.frontendPromptSkillID,
             SkillRegistry.commitMessageSkillID,
             SkillRegistry.changelogEntrySkillID,
             SkillRegistry.codeReviewCommentSkillID:
            return .developer
        case SkillRegistry.bugReportSkillID,
             SkillRegistry.incidentReportSkillID,
             SkillRegistry.meetingActionItemsSkillID,
             SkillRegistry.standupUpdateSkillID,
             SkillRegistry.productBriefSkillID:
            return .documents
        case SkillRegistry.betterQuestionSkillID,
             SkillRegistry.customerSupportReplySkillID,
             SkillRegistry.socialPostSkillID:
            return .communication
        default:
            return .community
        }
    }

    /// Splits `entries` into non-empty (category, entries) groups in display
    /// order, preserving the incoming order inside each group. Shared by the
    /// Library grid and the Switcher palette so both surfaces group the same
    /// way.
    static func grouped<Entry>(
        _ entries: [Entry],
        skillID: (Entry) -> String
    ) -> [(category: SkillCategory, entries: [Entry])] {
        let buckets = Dictionary(grouping: entries) {
            forSkillID(skillID($0))
        }
        return allCases.compactMap { category in
            guard
                let grouped = buckets[category],
                !grouped.isEmpty
            else {
                return nil
            }
            return (category, grouped)
        }
    }
}
