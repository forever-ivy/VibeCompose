import Foundation

struct AppConfig: Codable, Sendable, Equatable {
    var appLanguage: AppLanguage = .system
    var skillSwitcherHotkey: HotkeyBinding?
    /// Optional global shortcut that reopens the last dictation Preview and
    /// allows switching Skills to regenerate results for the same transcript.
    /// Default is nil — user enables it in Settings.
    var resultPreviewHotkey: HotkeyBinding?
    var transcription: TranscriptionConfig = .init()
    var injection: InjectionConfig = .init()
    var auth: AuthConfig = .init()
    var privacy: PrivacyConfig = .init()
    var visualFeedback: VisualFeedbackConfig = .init()
    var context: ContextConfig = .init()
    var styleCapsules: StyleCapsuleConfig = .init()
    var terminologyPacks: TerminologyPackConfig = .init()
    var communitySkills: CommunitySkillConfig = .init()
    var skillEcosystem: SkillEcosystemConfig = .init()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(
            AppLanguage.self,
            forKey: .appLanguage
        ) ?? .system
        if let decodedSkillSwitcherHotkey = try container.decodeIfPresent(
            HotkeyBinding.self,
            forKey: .skillSwitcherHotkey
        ) {
            skillSwitcherHotkey = try? decodedSkillSwitcherHotkey.validated()
        } else {
            skillSwitcherHotkey = nil
        }
        if let decodedResultPreviewHotkey = try container.decodeIfPresent(
            HotkeyBinding.self,
            forKey: .resultPreviewHotkey
        ) {
            resultPreviewHotkey = try? decodedResultPreviewHotkey.validated()
        } else {
            resultPreviewHotkey = nil
        }
        transcription = try container.decodeIfPresent(TranscriptionConfig.self, forKey: .transcription) ?? .init()
        injection = try container.decodeIfPresent(InjectionConfig.self, forKey: .injection) ?? .init()
        auth = try container.decodeIfPresent(AuthConfig.self, forKey: .auth) ?? .init()
        privacy = try container.decodeIfPresent(PrivacyConfig.self, forKey: .privacy) ?? .init()
        visualFeedback = try container.decodeIfPresent(
            VisualFeedbackConfig.self,
            forKey: .visualFeedback
        ) ?? .init()
        context = try container.decodeIfPresent(
            ContextConfig.self,
            forKey: .context
        ) ?? .init()
        styleCapsules =
            try container.decodeIfPresent(
                StyleCapsuleConfig.self,
                forKey: .styleCapsules
            ) ?? .init()
        terminologyPacks =
            try container.decodeIfPresent(
                TerminologyPackConfig.self,
                forKey: .terminologyPacks
            ) ?? .init()
        communitySkills =
            try container.decodeIfPresent(
                CommunitySkillConfig.self,
                forKey: .communitySkills
            ) ?? .init()
        skillEcosystem = try container.decodeIfPresent(
            SkillEcosystemConfig.self,
            forKey: .skillEcosystem
        ) ?? .init()
    }
}

struct PrivacyConfig: Codable, Sendable, Equatable {
    var historyEnabled: Bool = true
    var historyRetentionDays: Int = 30
    var historyRecordLimit: Int = 500
    var storeRawTranscripts: Bool = false
    var failedAudioRecoveryEnabled: Bool = true
    var failedAudioRetentionHours: Int = 24
    var failedAudioRecordLimit: Int = 10
    var diagnosticsEnabled: Bool = true
    var diagnosticsRetentionDays: Int = 14
    var diagnosticsRecordLimit: Int = 1_000
    var productMetricsEnabled: Bool = false
    var productMetricsRetentionDays: Int = 30
    var productMetricsRecordLimit: Int = 5_000
    var excludeSensitiveApps: Bool = true
    var additionalSensitiveAppBundleIdentifiers: [String] = []

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        historyEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? true
        historyRetentionDays = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 30,
            minimum: 1,
            maximum: 3_650
        )
        historyRecordLimit = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .historyRecordLimit) ?? 500,
            minimum: 10,
            maximum: 10_000
        )
        storeRawTranscripts = try container.decodeIfPresent(Bool.self, forKey: .storeRawTranscripts) ?? false
        failedAudioRecoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .failedAudioRecoveryEnabled) ?? true
        failedAudioRetentionHours = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .failedAudioRetentionHours) ?? 24,
            minimum: 1,
            maximum: 168
        )
        failedAudioRecordLimit = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .failedAudioRecordLimit) ?? 10,
            minimum: 1,
            maximum: 100
        )
        diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? true
        diagnosticsRetentionDays = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .diagnosticsRetentionDays) ?? 14,
            minimum: 1,
            maximum: 365
        )
        diagnosticsRecordLimit = Self.bounded(
            try container.decodeIfPresent(Int.self, forKey: .diagnosticsRecordLimit) ?? 1_000,
            minimum: 100,
            maximum: 20_000
        )
        productMetricsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .productMetricsEnabled
        ) ?? false
        productMetricsRetentionDays = Self.bounded(
            try container.decodeIfPresent(
                Int.self,
                forKey: .productMetricsRetentionDays
            ) ?? 30,
            minimum: 1,
            maximum: 365
        )
        productMetricsRecordLimit = Self.bounded(
            try container.decodeIfPresent(
                Int.self,
                forKey: .productMetricsRecordLimit
            ) ?? 5_000,
            minimum: 100,
            maximum: 50_000
        )
        excludeSensitiveApps = try container.decodeIfPresent(Bool.self, forKey: .excludeSensitiveApps) ?? true
        additionalSensitiveAppBundleIdentifiers = Self.normalizedBundleIdentifiers(
            try container.decodeIfPresent([String].self, forKey: .additionalSensitiveAppBundleIdentifiers) ?? []
        )
    }

    private static func bounded(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(maximum, max(minimum, value))
    }

    private static func normalizedBundleIdentifiers(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }
}

enum PreferredLoginSurface: String, Codable, Sendable, Equatable {
    case defaultBrowser
    case embedded
}

struct AuthConfig: Codable, Sendable, Equatable {
    var preferredLoginSurface: PreferredLoginSurface = .defaultBrowser
    var allowEmbeddedFallback: Bool = false
    var persistCapturedSession: Bool = true

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredLoginSurface = try container.decodeIfPresent(PreferredLoginSurface.self, forKey: .preferredLoginSurface) ?? .defaultBrowser
        allowEmbeddedFallback = try container.decodeIfPresent(Bool.self, forKey: .allowEmbeddedFallback) ?? false
        persistCapturedSession = try container.decodeIfPresent(Bool.self, forKey: .persistCapturedSession) ?? true
    }
}

enum TranscriptionProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case chatGPTManagedAuth
    case openAICompatible

    var id: String { rawValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "codexChatGPTBridge":
            self = .chatGPTManagedAuth
        case Self.chatGPTManagedAuth.rawValue:
            self = .chatGPTManagedAuth
        case Self.openAICompatible.rawValue:
            self = .openAICompatible
        default:
            self = .chatGPTManagedAuth
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .chatGPTManagedAuth:
            return L10n.text("ChatGPT Account")
        case .openAICompatible:
            return L10n.text("Import Your Own API")
        }
    }

    var caption: String {
        switch self {
        case .chatGPTManagedAuth:
            return L10n.text("Recommended. VibeCompose signs in to ChatGPT directly and keeps its own session on this Mac.")
        case .openAICompatible:
            return L10n.text("Dictation uses your OpenAI-compatible endpoint and API key. AI rewrite still uses ChatGPT Auth.")
        }
    }
}

/// Product-facing dictation path shown on Advanced settings.
enum DictationRouteStrategy: String, CaseIterable, Identifiable, Sendable, Equatable {
    case chatGPTAccount
    case importOwnAPI
    case compatibleFallback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPTAccount:
            return L10n.text("ChatGPT Account")
        case .importOwnAPI:
            return L10n.text("Import Your Own API")
        case .compatibleFallback:
            return L10n.text("Compatible Fallback")
        }
    }

    var caption: String {
        switch self {
        case .chatGPTAccount:
            return L10n.text("Recommended. Dictation uses your ChatGPT account on this Mac.")
        case .importOwnAPI:
            return L10n.text("Primary dictation path uses your own OpenAI-compatible API.")
        case .compatibleFallback:
            return L10n.text("ChatGPT first. If it fails, automatically retry with your API.")
        }
    }

    var systemImage: String {
        switch self {
        case .chatGPTAccount:
            return "person.crop.circle.badge.checkmark"
        case .importOwnAPI:
            return "key.horizontal"
        case .compatibleFallback:
            return "arrow.triangle.branch"
        }
    }

    static func resolve(
        provider: TranscriptionProvider,
        openAIFallbackEnabled: Bool
    ) -> Self {
        switch provider {
        case .openAICompatible:
            return .importOwnAPI
        case .chatGPTManagedAuth:
            return openAIFallbackEnabled ? .compatibleFallback : .chatGPTAccount
        }
    }
}

/// Curated model IDs for Advanced pickers (plus free-form custom).
enum ProductModelCatalog {
    static let dictationPresets: [String] = [
        "gpt-4o-mini-transcribe",
        "gpt-4o-transcribe",
        "whisper-1",
    ]

    static let rewritePresets: [String] = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.2",
        "gpt-5",
        "gpt-4.1",
        "gpt-4o",
    ]

    static let customModelTag = "__custom__"

    static func selectionTag(
        for model: String,
        presets: [String]
    ) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if presets.contains(trimmed) {
            return trimmed
        }
        return customModelTag
    }
}

enum TextPolishMode: String, Codable, Sendable, Equatable, CaseIterable {
    case automaticWhenKeyAvailable
    case disabled
    case always
}

enum TranscriptPunctuationPreference: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case automatic
    case fullWidth
    case halfWidth
    case preserve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return L10n.text("Automatic")
        case .fullWidth:
            return L10n.text("Chinese full-width")
        case .halfWidth:
            return L10n.text("ASCII half-width")
        case .preserve:
            return L10n.text("Preserve punctuation")
        }
    }
}

enum TextPolishProviderID: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case chatGPTAuth
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPTAuth:
            return L10n.text("ChatGPT Auth")
        case .openAICompatible:
            return L10n.text("Own API")
        }
    }
}

struct TextPolishConfig: Codable, Sendable, Equatable {
    var mode: TextPolishMode = .automaticWhenKeyAvailable
    /// Prefer ChatGPT Auth Responses when true (and a session is ready).
    var chatGPTAuthEnabled: Bool = true
    /// Prefer the user-owned OpenAI-compatible chat endpoint when true.
    /// Mutually exclusive with `chatGPTAuthEnabled` in the Advanced UI.
    var openAICompatibleEnabled: Bool = false
    /// When ChatGPT Auth is primary, retry polish via Own API on recoverable failure.
    var openAIFallbackEnabled: Bool = false
    var chatGPTResponseModel: String = "gpt-5.5"
    var openAICompatibleURL: String = "https://api.openai.com/v1/chat/completions"
    var openAICompatibleModel: String = "gpt-4o"
    var temperature: Double = 0.2
    var maxOutputTokens: Int = 1_200
    var glossaryBudgetCharacters: Int = 1_200
    var showCostEstimates: Bool = true

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(TextPolishMode.self, forKey: .mode) ?? .automaticWhenKeyAvailable
        chatGPTAuthEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatGPTAuthEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .allowChatGPTAuthFallback)
            ?? true
        openAICompatibleEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .openAICompatibleEnabled
        ) ?? false
        openAIFallbackEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .openAIFallbackEnabled
        ) ?? false
        // If both flags decode true from a hand-edited config, prefer ChatGPT Auth.
        if openAICompatibleEnabled && chatGPTAuthEnabled {
            openAICompatibleEnabled = false
        }
        if openAICompatibleEnabled {
            openAIFallbackEnabled = false
        }
        chatGPTResponseModel = try container.decodeIfPresent(String.self, forKey: .chatGPTResponseModel)
            ?? "gpt-5.5"
        openAICompatibleURL = try container.decodeIfPresent(
            String.self,
            forKey: .openAICompatibleURL
        ) ?? "https://api.openai.com/v1/chat/completions"
        openAICompatibleModel = try container.decodeIfPresent(
            String.self,
            forKey: .openAICompatibleModel
        ) ?? "gpt-4o"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.2
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 1_200
        glossaryBudgetCharacters = try container.decodeIfPresent(Int.self, forKey: .glossaryBudgetCharacters) ?? 1_200
        showCostEstimates = try container.decodeIfPresent(Bool.self, forKey: .showCostEstimates) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case chatGPTAuthEnabled
        case openAICompatibleEnabled
        case openAIFallbackEnabled
        case chatGPTResponseModel
        case openAICompatibleURL
        case openAICompatibleModel
        case temperature
        case maxOutputTokens
        case glossaryBudgetCharacters
        case showCostEstimates
        case allowChatGPTAuthFallback
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(chatGPTAuthEnabled, forKey: .chatGPTAuthEnabled)
        try container.encode(openAICompatibleEnabled, forKey: .openAICompatibleEnabled)
        try container.encode(openAIFallbackEnabled, forKey: .openAIFallbackEnabled)
        try container.encode(chatGPTResponseModel, forKey: .chatGPTResponseModel)
        try container.encode(openAICompatibleURL, forKey: .openAICompatibleURL)
        try container.encode(openAICompatibleModel, forKey: .openAICompatibleModel)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encode(glossaryBudgetCharacters, forKey: .glossaryBudgetCharacters)
        try container.encode(showCostEstimates, forKey: .showCostEstimates)
    }
}

struct TranscriptionConfig: Codable, Sendable, Equatable {
    var provider: TranscriptionProvider = .chatGPTManagedAuth
    /// When true and `provider == .chatGPTManagedAuth`, a failed ChatGPT
    /// transcription may retry via the configured OpenAI-compatible endpoint.
    var openAIFallbackEnabled: Bool = false
    var dictationHotkey: HotkeyBinding = .f5
    var openAITranscriptionURL: String = "https://api.openai.com/v1/audio/transcriptions"
    var openAIModel: String = "gpt-4o-mini-transcribe"
    var sampleRateHz: Int = 24_000
    var maxDurationSeconds: Int = 120
    var hintTerms: [String] = []
    var speechCleanupEnabled: Bool = true
    var feedbackSoundsEnabled: Bool = true
    var punctuationPreference: TranscriptPunctuationPreference = .automatic
    var skills: SkillsConfig = .init()
    var terminology: TerminologyConfig = .init()
    var textPolish: TextPolishConfig = .init()
    var resolvedSkillPlan:
        ResolvedSkillExecutionPlan?
    var skillPromptContext =
        SkillPromptContext()
    var resolvedTerminologyEntries:
        [TerminologyEntry]?
    var resolvedTerminologyPackIDs:
        [String] = []
    var resolvedTerminologyRisk:
        SkillRiskLevel = .low
    var resolvedStyleCapsuleID:
        String?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedProvider = try container.decodeIfPresent(TranscriptionProvider.self, forKey: .provider) {
            provider = decodedProvider
        } else {
            provider = .chatGPTManagedAuth
        }
        openAIFallbackEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .openAIFallbackEnabled
        ) ?? false
        if let decodedBinding = try container.decodeIfPresent(
            HotkeyBinding.self,
            forKey: .dictationHotkey
        ) {
            dictationHotkey =
                (try? decodedBinding.validated()) ?? .f5
        } else {
            let legacyContainer = try decoder.container(
                keyedBy: LegacyCodingKeys.self
            )
            let legacyKeyCode = try legacyContainer.decodeIfPresent(
                UInt32.self,
                forKey: .hotkeyKeyCode
            )
            let migrated = HotkeyBinding(
                keyCode: legacyKeyCode
                    ?? HotkeyBinding.f5.keyCode
            )
            dictationHotkey =
                (try? migrated.validated()) ?? .f5
        }
        openAITranscriptionURL = try container.decodeIfPresent(String.self, forKey: .openAITranscriptionURL) ?? "https://api.openai.com/v1/audio/transcriptions"
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-4o-mini-transcribe"
        sampleRateHz = try container.decodeIfPresent(Int.self, forKey: .sampleRateHz) ?? 24_000
        maxDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .maxDurationSeconds) ?? 120
        hintTerms = try container.decodeIfPresent([String].self, forKey: .hintTerms) ?? []
        speechCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .speechCleanupEnabled) ?? true
        feedbackSoundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .feedbackSoundsEnabled) ?? true
        punctuationPreference = try container.decodeIfPresent(
            TranscriptPunctuationPreference.self,
            forKey: .punctuationPreference
        ) ?? .automatic
        if let decodedSkills =
            try container.decodeIfPresent(
                SkillsConfig.self,
                forKey: .skills
            )
        {
            skills = decodedSkills
        } else {
            skills = SkillsConfig(
                migrating:
                    try container
                        .decodeIfPresent(
                            VoiceModeConfig.self,
                            forKey: .voiceModes
                        ) ?? .init()
            )
        }
        terminology = try container.decodeIfPresent(TerminologyConfig.self, forKey: .terminology) ?? .init()
        textPolish = try container.decodeIfPresent(TextPolishConfig.self, forKey: .textPolish) ?? .init()
        resolvedSkillPlan = nil
        skillPromptContext =
            SkillPromptContext()
        resolvedTerminologyEntries = nil
        resolvedTerminologyPackIDs = []
        resolvedTerminologyRisk = .low
        resolvedStyleCapsuleID = nil
    }

    var voiceModes: VoiceModeConfig {
        get {
            skills.legacyVoiceModes
        }
        set {
            skills.applyLegacyVoiceModes(
                newValue
            )
        }
    }

    var hotkeyKeyCode: UInt32 {
        get {
            dictationHotkey.keyCode
        }
        set {
            dictationHotkey = HotkeyBinding(
                keyCode: newValue,
                modifiers: dictationHotkey.modifiers
            )
        }
    }

    private enum LegacyCodingKeys:
        String,
        CodingKey
    {
        case hotkeyKeyCode
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case provider
        case openAIFallbackEnabled
        case dictationHotkey
        case openAITranscriptionURL
        case openAIModel
        case sampleRateHz
        case maxDurationSeconds
        case hintTerms
        case speechCleanupEnabled
        case feedbackSoundsEnabled
        case punctuationPreference
        case skills
        case voiceModes
        case terminology
        case textPolish
    }

    func encode(to encoder: any Encoder)
        throws
    {
        var container =
            encoder.container(
                keyedBy: CodingKeys.self
            )
        try container.encode(
            provider,
            forKey: .provider
        )
        try container.encode(
            openAIFallbackEnabled,
            forKey: .openAIFallbackEnabled
        )
        try container.encode(
            dictationHotkey,
            forKey: .dictationHotkey
        )
        try container.encode(
            openAITranscriptionURL,
            forKey:
                .openAITranscriptionURL
        )
        try container.encode(
            openAIModel,
            forKey: .openAIModel
        )
        try container.encode(
            sampleRateHz,
            forKey: .sampleRateHz
        )
        try container.encode(
            maxDurationSeconds,
            forKey:
                .maxDurationSeconds
        )
        try container.encode(
            hintTerms,
            forKey: .hintTerms
        )
        try container.encode(
            speechCleanupEnabled,
            forKey:
                .speechCleanupEnabled
        )
        try container.encode(
            feedbackSoundsEnabled,
            forKey:
                .feedbackSoundsEnabled
        )
        try container.encode(
            punctuationPreference,
            forKey:
                .punctuationPreference
        )
        try container.encode(
            skills,
            forKey: .skills
        )
        try container.encode(
            terminology,
            forKey: .terminology
        )
        try container.encode(
            textPolish,
            forKey: .textPolish
        )
    }

    var activeDictionaryEntries: [TerminologyEntry] {
        if let resolvedTerminologyEntries {
            return resolvedTerminologyEntries
                .filter(\.isEnabled)
        }
        guard terminology.enabled else {
            return []
        }

        return terminology.entries.filter {
            $0.isEnabled && ($0.type == .term || $0.type == .correction)
        }
    }

    var promptHintTerms: [String] {
        hintTerms + activeDictionaryEntries
            .filter { $0.type == .term }
            .map(\.original)
    }
}

struct TerminologyConfig: Codable, Sendable, Equatable {
    var enabled: Bool = true
    var entries: [TerminologyEntry] = []
    var lastImportedSource: String?
    var lastImportedAt: String?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let decodedEntries = try container.decodeIfPresent([TerminologyEntry].self, forKey: .entries) ?? []
        let legacyImportedEntries = try container.decodeIfPresent([TerminologyEntry].self, forKey: .importedEntries) ?? []
        entries = decodedEntries.isEmpty ? legacyImportedEntries : decodedEntries
        lastImportedSource = Self.normalizedImportedSource(
            try container.decodeIfPresent(String.self, forKey: .lastImportedSource)
        )
        lastImportedAt = try container.decodeIfPresent(String.self, forKey: .lastImportedAt)
    }

    private static func normalizedImportedSource(_ source: String?) -> String? {
        guard let source else {
            return nil
        }

        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(lastImportedSource, forKey: .lastImportedSource)
        try container.encodeIfPresent(lastImportedAt, forKey: .lastImportedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case entries
        case importedEntries
        case lastImportedSource
        case lastImportedAt
    }
}

enum TerminologyEntryType: String, Codable, Sendable, Equatable, CaseIterable {
    case term
    case correction

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.correction.rawValue:
            self = .correction
        case Self.term.rawValue, "suggestion":
            self = .term
        default:
            self = .term
        }
    }
}

struct TerminologyEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var type: TerminologyEntryType
    var original: String
    var replacement: String?
    var aliases: [String]
    var isEnabled: Bool
    var source: String
    var usageCount: Int
    var createdAt: String

    var canonical: String {
        switch type {
        case .term:
            return original
        case .correction:
            return replacement?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? replacement!
                : original
        }
    }

    init(
        id: UUID = UUID(),
        type: TerminologyEntryType,
        original: String,
        replacement: String?,
        aliases: [String],
        isEnabled: Bool,
        source: String,
        usageCount: Int,
        createdAt: String
    ) {
        self.id = id
        self.type = type
        self.original = original
        self.replacement = replacement
        self.aliases = aliases
        self.isEnabled = isEnabled
        self.source = source
        self.usageCount = usageCount
        self.createdAt = createdAt
    }

    init(
        canonical: String,
        aliases: [String],
        source: String = "dictionary-import"
    ) {
        self.init(
            type: .term,
            original: canonical,
            replacement: nil,
            aliases: aliases,
            isEnabled: true,
            source: source,
            usageCount: 0,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type) ?? TerminologyEntryType.term.rawValue
        type = rawType == TerminologyEntryType.correction.rawValue ? .correction : .term
        original = try container.decodeIfPresent(String.self, forKey: .original)
            ?? container.decodeIfPresent(String.self, forKey: .canonical)
            ?? ""
        replacement = try container.decodeIfPresent(String.self, forKey: .replacement)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        let decodedSource = try container.decodeIfPresent(String.self, forKey: .source) ?? "dictionary-import"
        source = Self.normalizedSource(rawType: rawType, source: decodedSource)
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? ISO8601DateFormatter().string(from: Date())
        id = decodedID ?? StableIdentifier.uuid(
            namespace: "VibeCompose.TerminologyEntry",
            components: [
                type.rawValue,
                original,
                replacement,
                aliases.joined(separator: "\u{1F}"),
                source,
            ]
        )
    }

    private static func normalizedSource(rawType: String, source: String) -> String {
        if rawType == "suggestion", source == "auto-suggestion" {
            return "legacy-import"
        }

        return source
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(original, forKey: .original)
        try container.encodeIfPresent(replacement, forKey: .replacement)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(source, forKey: .source)
        try container.encode(usageCount, forKey: .usageCount)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case original
        case replacement
        case aliases
        case isEnabled
        case source
        case usageCount
        case createdAt
        case canonical
    }
}

struct InjectionConfig: Codable, Sendable, Equatable {
    var preserveClipboard: Bool = false
    var restoreDelayMilliseconds: UInt64 = 350
    /// When true, low/medium-risk Skill results that would normally open the
    /// Preview panel paste (or copy) straight to the target instead — so long
    /// as Accessibility paste is allowed, there is no selection replacement,
    /// and local validation did not fall back. High-risk Skills, selection
    /// rewrites, and failed validation still force Preview.
    var skipResultPreviewWhenSafe: Bool = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preserveClipboard = try container.decodeIfPresent(Bool.self, forKey: .preserveClipboard) ?? false
        restoreDelayMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .restoreDelayMilliseconds) ?? 350
        skipResultPreviewWhenSafe = try container.decodeIfPresent(
            Bool.self,
            forKey: .skipResultPreviewWhenSafe
        ) ?? false
    }
}

enum ConfigError: LocalizedError {
    case invalidPromptOutput

    var errorDescription: String? {
        switch self {
        case .invalidPromptOutput:
            return L10n.text("Transcription prompt returned empty text.")
        }
    }
}

struct ConfigStore {
    let fileManager: FileManager
    let homeDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
    }

    var directoryURL: URL {
        ProductIdentity.applicationSupportURL(homeDirectoryURL: homeDirectoryURL)
    }

    var configURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    func load() throws -> AppConfig {
        try ProductDataMigration(
            fileManager: fileManager,
            currentDirectoryURL: directoryURL,
            legacyDirectoryURL:
                LegacyProductIdentity.applicationSupportURL(
                    homeDirectoryURL: homeDirectoryURL
                )
        ).migrateIfNeeded()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: configURL.path) else {
            let config = AppConfig()
            try save(config)
            return config
        }

        let data = try Data(contentsOf: configURL)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        let config = LegacyProductIdentity
            .canonicalizingBuiltInSkillReferences(in: decoded)
        // Normalize/migrate missing keys by re-encoding, but skip the write when
        // the on-disk document is already canonical. Unconditional rewrite made
        // every launch touch config.json (mtime, backup noise, SSD wear).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let normalized = try encoder.encode(config)
        if normalized != data {
            try save(config)
        }
        return config
    }

    func save(_ config: AppConfig) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: configURL.path
        )
    }
}
