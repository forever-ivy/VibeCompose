import Foundation

enum DictationMode: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case direct
    case reply
    case email
    case agentPlan
    case codePrompt
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct:
            return L10n.text("Direct")
        case .reply:
            return L10n.text("Reply")
        case .email:
            return L10n.text("Email")
        case .agentPlan:
            return L10n.text("Backend Prompt")
        case .codePrompt:
            return L10n.text("Code Prompt")
        case .translate:
            return L10n.text("Translate")
        }
    }

    var caption: String {
        switch self {
        case .direct:
            return L10n.text(
                "Keep the speaker's wording and order, remove filler and superseded corrections, and avoid unnecessary restructuring."
            )
        case .reply:
            return L10n.text(
                "Create a concise, natural conversational reply without adding facts or a preamble."
            )
        case .email:
            return L10n.text(
                "Shape the dictation into a clear, complete email while preserving names, dates, requests, constraints, and the intended next step."
            )
        case .agentPlan:
            return L10n.text(
                "Turn spoken intent into an implementation-ready backend task with goals, constraints, steps, edge cases, and acceptance criteria."
            )
        case .codePrompt:
            return L10n.text(
                "Create an implementation-ready coding prompt while preserving paths, commands, symbols, versions, and quoted literals."
            )
        case .translate:
            return L10n.text(
                "Translate into the language named in the dictation; when none is named, translate Chinese to English and other input to Simplified Chinese."
            )
        }
    }

    var promptInstruction: String {
        switch self {
        case .direct:
            return "Voice Mode: Direct. Return faithful cleaned dictation in the speaker's language. Preserve wording, order, tone, simplified/traditional Chinese form, and level of detail. Remove only filler, false starts, and superseded self-corrections. Do not translate. Do not add facts, headings, bullets, greetings, conclusions, or structural rewrites unless the speaker explicitly requests them."
        case .reply:
            return "Voice Mode: Reply. Turn the spoken intent into one concise, natural conversational reply in the speaker's language and tone. Preserve every stated fact, request, commitment, and qualifier. Add a greeting or sign-off only when spoken or requested. Do not translate unless the speaker asks. Do not add a subject line, preamble, explanation, or unsupported facts."
        case .email:
            return "Voice Mode: Email. Produce a polished email body in the speaker's language with a clear purpose, readable paragraphs, an explicit request or next step when stated, and complete sentences. Preserve every named person, date, attachment, request, constraint, and follow-up. Add a greeting, sign-off, or subject line only when the speaker provides or requests it. Do not invent attachment status, availability, deadlines, or commitments. Do not translate unless the speaker asks."
        case .agentPlan:
            return "Skill: Backend Prompt Composer. Produce an implementation-ready Markdown task in the speaker's language. If the transcript is predominantly Chinese, write the entire task in Chinese and use Chinese section headings in this order: 目标, 约束, 实现步骤, 边界情况, 验收标准. If the transcript is predominantly another language, write the entire task in that language and use equivalent local headings (English: Goal, Constraints, Implementation Steps, Edge Cases, Acceptance Criteria). Keep requirements atomic and testable. Write ‘Not provided’ / ‘未提供’ instead of inventing repository state, architecture, files, APIs, tests, or product decisions. Never translate away from the speaker's language unless they explicitly request another language."
        case .codePrompt:
            return "Voice Mode: Code Prompt. Produce an implementation-ready coding request in the speaker's language. If the transcript is predominantly Chinese, write the entire request in Chinese and prefer Chinese headings such as 目标, 上下文, 需求, 约束, 验收. If the transcript is predominantly another language, write the entire request in that language (English headings may be Objective, Context, Requirements, Constraints, Verification). Preserve all spoken paths, commands, flags, APIs, symbols, versions, identifiers, error messages, and quoted literals exactly. Do not invent repository state, affected files, test results, or tool access. Never translate away from the speaker's language unless they explicitly request another language."
        case .translate:
            return "Voice Mode: Translate. Treat an explicitly named target language as an instruction, not source content. If none is named, translate predominantly Chinese input to English and other input to Simplified Chinese. Preserve meaning, tone, paragraph structure, names, numbers, Markdown, and technical literals; do not translate code or identifiers unless explicitly requested. Output only the translation with no labels or explanation."
        }
    }
}

enum VoiceModeRuleError: LocalizedError, Equatable {
    case invalidBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidBundleIdentifier:
            return L10n.text(
                "Enter a valid bundle identifier such as com.apple.Notes."
            )
        }
    }
}

struct AppModeRule: Codable, Sendable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case appName
        case bundleIdentifier
        case mode
        case isEnabled
    }

    var id: UUID
    var appName: String?
    var bundleIdentifier: String
    var mode: DictationMode
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        appName: String?,
        bundleIdentifier: String,
        mode: DictationMode,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.appName = Self.normalizedAppName(appName)
        self.bundleIdentifier = Self.normalizedBundleIdentifier(
            bundleIdentifier
        )
        self.mode = mode
        self.isEnabled = isEnabled
    }

    static func validated(
        id: UUID = UUID(),
        appName: String?,
        bundleIdentifier: String,
        mode: DictationMode,
        isEnabled: Bool = true
    ) throws -> AppModeRule {
        let normalized = normalizedBundleIdentifier(bundleIdentifier)
        guard isValidBundleIdentifier(normalized) else {
            throw VoiceModeRuleError.invalidBundleIdentifier
        }
        return AppModeRule(
            id: id,
            appName: appName,
            bundleIdentifier: normalized,
            mode: mode,
            isEnabled: isEnabled
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appName = Self.normalizedAppName(
            try? container.decodeIfPresent(String.self, forKey: .appName)
        )
        bundleIdentifier = Self.normalizedBundleIdentifier(
            (try? container.decodeIfPresent(
                String.self,
                forKey: .bundleIdentifier
            )) ?? ""
        )
        mode = Self.decodeMode(from: container)
        isEnabled = (try? container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        )) ?? true
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id))
            ?? StableIdentifier.uuid(
                namespace: "VibeWhisper.AppModeRule",
                components: [bundleIdentifier]
            )
    }

    static func normalizedBundleIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let normalized = normalizedBundleIdentifier(value)
        guard
            !normalized.isEmpty,
            normalized.count <= 255,
            normalized.contains("."),
            !normalized.hasPrefix("."),
            !normalized.hasSuffix("."),
            !normalized.contains("..")
        else {
            return false
        }

        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._")
        )
        return normalized.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func normalizedAppName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized.isEmpty ? nil : String(normalized.prefix(120))
    }

    private static func decodeMode(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> DictationMode {
        guard
            let rawValue = try? container.decodeIfPresent(
                String.self,
                forKey: .mode
            ),
            let mode = DictationMode(rawValue: rawValue)
        else {
            return .direct
        }
        return mode
    }
}

struct VoiceModeConfig: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case defaultMode
        case applicationRules
    }

    static let maximumApplicationRuleCount = 100

    var defaultMode: DictationMode = .direct
    var applicationRules: [AppModeRule] = []

    init() {}

    init(
        defaultMode: DictationMode,
        applicationRules: [AppModeRule]
    ) {
        self.defaultMode = defaultMode
        self.applicationRules = Self.normalizedRules(applicationRules)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if
            let rawValue = try? container.decodeIfPresent(
                String.self,
                forKey: .defaultMode
            ),
            let mode = DictationMode(rawValue: rawValue)
        {
            defaultMode = mode
        } else {
            defaultMode = .direct
        }
        applicationRules = Self.normalizedRules(
            (try? container.decodeIfPresent(
                [AppModeRule].self,
                forKey: .applicationRules
            )) ?? []
        )
    }

    var requiresTextPolish: Bool {
        defaultMode != .direct
            || applicationRules.contains {
                $0.isEnabled && $0.mode != .direct
            }
    }

    mutating func upsert(_ rule: AppModeRule) {
        guard AppModeRule.isValidBundleIdentifier(rule.bundleIdentifier) else {
            return
        }
        applicationRules.removeAll {
            $0.id != rule.id
                && $0.bundleIdentifier == rule.bundleIdentifier
        }
        if let index = applicationRules.firstIndex(where: {
            $0.id == rule.id
        }) {
            applicationRules[index] = rule
        } else {
            applicationRules.append(rule)
        }
        applicationRules = Self.normalizedRules(applicationRules)
    }

    mutating func remove(id: UUID) {
        applicationRules.removeAll { $0.id == id }
    }

    func resolvedMode(
        for launchAppContext: LaunchAppContext?
    ) -> DictationMode {
        guard
            let bundleIdentifier = launchAppContext?.bundleIdentifier
                .map(AppModeRule.normalizedBundleIdentifier),
            !bundleIdentifier.isEmpty
        else {
            return defaultMode
        }

        return applicationRules.first {
            $0.isEnabled && $0.bundleIdentifier == bundleIdentifier
        }?.mode ?? defaultMode
    }

    func runtimeConfiguration(
        for launchAppContext: LaunchAppContext?
    ) -> VoiceModeConfig {
        VoiceModeConfig(
            defaultMode: resolvedMode(for: launchAppContext),
            applicationRules: []
        )
    }

    private static func normalizedRules(
        _ rules: [AppModeRule]
    ) -> [AppModeRule] {
        var seenIDs = Set<UUID>()
        var seenBundleIdentifiers = Set<String>()
        return rules.compactMap { rule in
            let normalizedBundleIdentifier =
                AppModeRule.normalizedBundleIdentifier(
                    rule.bundleIdentifier
                )
            guard
                AppModeRule.isValidBundleIdentifier(
                    normalizedBundleIdentifier
                ),
                seenIDs.insert(rule.id).inserted,
                seenBundleIdentifiers.insert(
                    normalizedBundleIdentifier
                ).inserted
            else {
                return nil
            }

            return AppModeRule(
                id: rule.id,
                appName: rule.appName,
                bundleIdentifier: normalizedBundleIdentifier,
                mode: rule.mode,
                isEnabled: rule.isEnabled
            )
        }
        .prefix(maximumApplicationRuleCount)
        .map { $0 }
    }
}

extension TranscriptionConfig {
    func resolvingVoiceMode(
        for launchAppContext: LaunchAppContext?,
        registry:
            SkillRegistry = .builtIn
    ) -> TranscriptionConfig {
        var resolved = self
        let plan = SkillResolver(
            registry: registry
        ).resolve(
            config: skills,
            launchAppContext:
                launchAppContext
        )
        resolved.skills =
            skills.runtimeConfiguration(
                for: plan
            )
        resolved.resolvedSkillPlan = plan
        return resolved
    }
}
