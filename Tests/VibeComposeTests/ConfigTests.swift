import Carbon
import Foundation
import Testing
@testable import VibeCompose

@Test
func defaultConfigUsesChatGPTAccountDefaults() throws {
    let config = AppConfig()
    #expect(config.appLanguage == .system)
    #expect(
        config.transcription.dictationHotkey
            == .f5
    )
    #expect(config.skillSwitcherHotkey == nil)
    #expect(config.transcription.provider == .chatGPTManagedAuth)
    #expect(config.transcription.openAIFallbackEnabled == false)
    #expect(config.transcription.openAITranscriptionURL == "https://api.openai.com/v1/audio/transcriptions")
    #expect(config.transcription.openAIModel == "gpt-4o-mini-transcribe")
    #expect(config.transcription.hintTerms.isEmpty)
    #expect(config.transcription.speechCleanupEnabled == true)
    #expect(config.transcription.feedbackSoundsEnabled == true)
    #expect(config.transcription.voiceModes.defaultMode == .direct)
    #expect(config.transcription.voiceModes.applicationRules.isEmpty)
    #expect(config.injection.preserveClipboard == false)
    #expect(config.auth.preferredLoginSurface == .defaultBrowser)
    #expect(config.auth.allowEmbeddedFallback == false)
    #expect(config.auth.persistCapturedSession == true)
    #expect(config.skillEcosystem.remoteRegistryEnabled == false)
    #expect(
        config.visualFeedback.mode
            == .refinedHUD
    )
}

@Test
func configRoundTripPreservesAppLanguageAndSkillEcosystem() throws {
    var config = AppConfig()
    config.appLanguage = .english
    config.skillEcosystem.favoriteInstallationIDs = [UUID()]
    config.skillEcosystem.collections = [
        SkillCollection(
            name: "Writing",
            summary: "Portable writing Skills",
            category: "Productivity",
            items: []
        ),
    ]

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.appLanguage == .english)
    #expect(decoded.skillEcosystem == config.skillEcosystem)

    let legacy = try JSONDecoder().decode(
        AppConfig.self,
        from: Data("{}".utf8)
    )
    #expect(legacy.appLanguage == .system)
    #expect(!legacy.skillEcosystem.remoteRegistryEnabled)
}

@Test
func configMigratesLegacyHotkeyAndWritesOnlyTheNewBinding() throws {
    let json = """
    {
      "transcription": {
        "hotkeyKeyCode": 96
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        AppConfig.self,
        from: json
    )
    let encoded = try JSONEncoder().encode(decoded)
    let encodedJSON =
        String(data: encoded, encoding: .utf8) ?? ""

    #expect(
        decoded.transcription.dictationHotkey
            == .f5
    )
    #expect(encodedJSON.contains("dictationHotkey"))
    #expect(!encodedJSON.contains("hotkeyKeyCode"))
}

@Test
func configRoundTripPreservesModifiedDictationHotkey() throws {
    var config = AppConfig()
    config.transcription.dictationHotkey =
        HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(
                controlKey | optionKey
            )
        )

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(
        AppConfig.self,
        from: data
    )

    #expect(
        decoded.transcription.dictationHotkey
            == config.transcription.dictationHotkey
    )
}

@Test
func configRoundTripPreservesOptionalSkillSwitcherHotkey() throws {
    var config = AppConfig()
    config.skillSwitcherHotkey = .skillSwitcher

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(
        AppConfig.self,
        from: data
    )

    #expect(decoded.skillSwitcherHotkey == .skillSwitcher)
    try VibeComposeShortcutSetValidator.validate(
        dictation: decoded.transcription.dictationHotkey,
        skillSwitcher: decoded.skillSwitcherHotkey
    )
}

@Test
func configRoundTripPreservesVoiceModesAndApplicationRules() throws {
    var config = AppConfig()
    config.transcription.voiceModes = VoiceModeConfig(
        defaultMode: .codePrompt,
        applicationRules: [
            try AppModeRule.validated(
                appName: "Mail",
                bundleIdentifier: "com.apple.mail",
                mode: .email
            ),
            try AppModeRule.validated(
                appName: "Codex",
                bundleIdentifier: "com.openai.codex",
                mode: .codePrompt,
                isEnabled: false
            ),
        ]
    )

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.transcription.voiceModes == config.transcription.voiceModes)
}

@Test
func configDoesNotEncodeRemovedProviderFallbackMatrix() throws {
    let data = try JSONEncoder().encode(AppConfig())
    let json = String(data: data, encoding: .utf8) ?? ""

    #expect(json.contains("apiFallback") == false)
    #expect(json.contains("dictationProviders") == false)
    #expect(json.contains("polishProviders") == false)
    #expect(json.contains("keychainService") == false)
    #expect(json.contains("deepseek") == false)
    #expect(json.contains("kimi") == false)
    #expect(json.contains("gemini") == false)
    #expect(json.contains("anthropic") == false)
    #expect(json.contains("apiKey") == false)
    #expect(json.contains("openAIAuthTokenEnv") == false)
    #expect(json.contains("OPENAI_API_KEY") == false)
    #expect(json.contains("sk-") == false)
}

@Test
func legacyRecoveryEnvironmentFieldDecodesAndIsDroppedOnEncode() throws {
    let json = """
    {
      "transcription": {
        "provider": "openAICompatible",
        "openAIAuthTokenEnv": "PRIVATE_API_KEY",
        "openAITranscriptionURL": "https://api.example.com/v1/audio/transcriptions",
        "openAIModel": "example-transcriber"
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let encoded = try JSONEncoder().encode(decoded)
    let encodedJSON = String(data: encoded, encoding: .utf8) ?? ""

    #expect(decoded.transcription.provider == .openAICompatible)
    #expect(decoded.transcription.openAIFallbackEnabled == false)
    #expect(
        decoded.transcription.openAITranscriptionURL
            == "https://api.example.com/v1/audio/transcriptions"
    )
    #expect(decoded.transcription.openAIModel == "example-transcriber")
    #expect(encodedJSON.contains("openAIAuthTokenEnv") == false)
    #expect(encodedJSON.contains("PRIVATE_API_KEY") == false)
}

@Test
func openAIFallbackEnabledRoundTripsThroughConfig() throws {
    var config = AppConfig()
    config.transcription.provider = .chatGPTManagedAuth
    config.transcription.openAIFallbackEnabled = true
    config.transcription.openAIModel = "gpt-4o-transcribe"

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    let encodedJSON = String(data: data, encoding: .utf8) ?? ""

    #expect(decoded.transcription.openAIFallbackEnabled == true)
    #expect(decoded.transcription.provider == .chatGPTManagedAuth)
    #expect(decoded.transcription.openAIModel == "gpt-4o-transcribe")
    #expect(encodedJSON.contains("openAIFallbackEnabled"))
    #expect(
        DictationRouteStrategy.resolve(
            provider: decoded.transcription.provider,
            openAIFallbackEnabled: decoded.transcription.openAIFallbackEnabled
        ) == .compatibleFallback
    )
    #expect(
        DictationRouteStrategy.resolve(
            provider: .openAICompatible,
            openAIFallbackEnabled: false
        ) == .importOwnAPI
    )
    #expect(
        DictationRouteStrategy.resolve(
            provider: .chatGPTManagedAuth,
            openAIFallbackEnabled: false
        ) == .chatGPTAccount
    )
}

@Test
func textPolishOwnAPIConfigRoundTrips() throws {
    var config = AppConfig()
    config.transcription.textPolish.openAICompatibleEnabled = true
    config.transcription.textPolish.chatGPTAuthEnabled = false
    config.transcription.textPolish.openAIFallbackEnabled = false
    config.transcription.textPolish.openAICompatibleURL =
        "https://api.example.com/v1/chat/completions"
    config.transcription.textPolish.openAICompatibleModel = "gpt-4o"

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(decoded.transcription.textPolish.openAICompatibleEnabled)
    #expect(decoded.transcription.textPolish.openAIFallbackEnabled == false)
    #expect(decoded.transcription.textPolish.chatGPTAuthEnabled == false)
    #expect(
        decoded.transcription.textPolish.openAICompatibleURL
            == "https://api.example.com/v1/chat/completions"
    )
    #expect(decoded.transcription.textPolish.openAICompatibleModel == "gpt-4o")

    let json = String(data: data, encoding: .utf8) ?? ""
    #expect(json.contains("openAICompatibleEnabled"))
    #expect(json.contains("openAICompatibleURL"))
    #expect(json.contains("openAICompatibleModel"))
    #expect(json.contains("apiKey") == false)
}


@Test
func legacyProviderFallbackMatrixDecodesAndIsDroppedOnEncode() throws {
    let json = """
    {
      "transcription": {
        "apiFallback": {
          "mode": "automaticKeyFallback",
          "dictationProviders": [
            {
              "id": "groq-whisper",
              "title": "Groq Whisper",
              "model": "whisper-large-v3",
              "baseURL": "https://api.groq.com/openai/v1/audio/transcriptions",
              "keychainService": "vibecompose-groq-api-key",
              "documentationURL": "https://console.groq.com/docs/speech-to-text",
              "isEnabled": true
            }
          ],
          "polishProviders": [
            {
              "id": "deepseek-polish",
              "title": "DeepSeek",
              "model": "deepseek-v4-pro",
              "baseURL": "https://api.deepseek.com",
              "keychainService": "vibecompose-deepseek-api-key",
              "documentationURL": "https://api-docs.deepseek.com/api/list-models",
              "isEnabled": true
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let encoded = try JSONEncoder().encode(decoded)
    let encodedJSON = String(data: encoded, encoding: .utf8) ?? ""

    #expect(decoded.transcription.provider == .chatGPTManagedAuth)
    #expect(encodedJSON.contains("apiFallback") == false)
    #expect(encodedJSON.contains("deepseek") == false)
    #expect(encodedJSON.contains("groq") == false)
}

@Test
func defaultConfigEncodesTerminologyDefaults() throws {
    let data = try JSONEncoder().encode(AppConfig())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let transcription = try #require(object["transcription"] as? [String: Any])
    let terminology = try #require(transcription["terminology"] as? [String: Any])

    #expect(terminology["enabled"] as? Bool == true)
    #expect((terminology["entries"] as? [Any])?.isEmpty == true)
    #expect(terminology["importedEntries"] == nil)
    #expect(terminology["lastImportedSource"] == nil)
    #expect(terminology["lastImportedAt"] == nil)
}

@Test
func configRoundTripPreservesHiddenHintTerms() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = AppConfig()
    config.transcription.hintTerms = [
        "budget v2.xlsx",
        "VibeCompose",
        "review",
    ]

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.transcription.hintTerms == [
        "budget v2.xlsx",
        "VibeCompose",
        "review",
    ])
}

@Test
func configRoundTripPreservesSpeechCleanupSetting() throws {
    var config = AppConfig()
    config.transcription.speechCleanupEnabled = false

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.transcription.speechCleanupEnabled == false)
}

@Test
func legacyConfigWithoutSpeechCleanupSettingDefaultsToEnabled() throws {
    let json = """
    {
      "transcription": {
        "hotkeyKeyCode": 96
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

    #expect(decoded.transcription.speechCleanupEnabled == true)
}

@Test
func configRoundTripPreservesFeedbackSoundSetting() throws {
    var config = AppConfig()
    config.transcription.feedbackSoundsEnabled = false

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.transcription.feedbackSoundsEnabled == false)
}

@Test
func legacyConfigWithoutFeedbackSoundSettingDefaultsToEnabled() throws {
    let json = """
    {
      "transcription": {
        "hotkeyKeyCode": 96
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

    #expect(decoded.transcription.feedbackSoundsEnabled == true)
}

@Test
func configRoundTripPreservesTerminologyEntries() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = AppConfig()
    config.transcription.terminology.entries = [
        TerminologyEntry(
            canonical: "VibeCompose",
            aliases: ["VibeCompose"]
        ),
        TerminologyEntry(
            canonical: "OpenAI Compatible",
            aliases: ["Open AI Compatible"]
        ),
    ]
    config.transcription.terminology.lastImportedSource = "/Users/test/terms.csv"
    config.transcription.terminology.lastImportedAt = "2026-04-19T10:00:00Z"

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.transcription.terminology.enabled == true)
    #expect(decoded.transcription.terminology.entries.count == 2)
    #expect(decoded.transcription.terminology.entries[0].canonical == "VibeCompose")
    #expect(decoded.transcription.terminology.entries[0].aliases == ["VibeCompose"])
    #expect(decoded.transcription.terminology.lastImportedSource == "/Users/test/terms.csv")
    #expect(decoded.transcription.terminology.lastImportedAt == "2026-04-19T10:00:00Z")
}

@Test
func legacyImportedTerminologyEntriesMigrateIntoUserDictionaryEntries() throws {
    let json = """
    {
      "transcription": {
        "terminology": {
          "enabled": true,
          "importedEntries": [
            {
              "canonical": "ExampleSDK",
              "aliases": ["Example SDK", "AcmeWhisper"],
              "caseSensitive": true,
              "source": "dictionary-import"
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let migrated = try #require(decoded.transcription.terminology.entries.first)

    #expect(migrated.type == .term)
    #expect(migrated.original == "ExampleSDK")
    #expect(migrated.aliases == ["Example SDK", "AcmeWhisper"])
    #expect(migrated.isEnabled == true)
    #expect(migrated.source == "dictionary-import")
}

@Test
func legacyTerminologyEntriesReceiveAndPersistStableIdentifiers() throws {
    let json = """
    {
      "type": "term",
      "original": "VibeCompose",
      "aliases": [],
      "isEnabled": true,
      "source": "legacy-import",
      "usageCount": 0,
      "createdAt": "2026-07-13T00:00:00Z"
    }
    """.data(using: .utf8)!

    let migrated = try JSONDecoder().decode(TerminologyEntry.self, from: json)
    let independentlyMigrated = try JSONDecoder().decode(TerminologyEntry.self, from: json)
    let reencoded = try JSONEncoder().encode(migrated)
    let reloaded = try JSONDecoder().decode(TerminologyEntry.self, from: reencoded)

    #expect(independentlyMigrated.id == migrated.id)
    #expect(reloaded.id == migrated.id)
    #expect(reloaded.original == "VibeCompose")
}

@Test
func terminologyImportMetadataIsPreserved() throws {
    let json = """
    {
      "transcription": {
        "terminology": {
          "enabled": true,
          "lastImportedSource": "/Users/test/terms.csv",
          "lastImportedAt": "2026-04-19T10:00:00Z",
          "entries": [
            {
              "type": "term",
              "original": "VibeCompose",
              "aliases": [],
              "isEnabled": true,
              "source": "dictionary-import",
              "usageCount": 0,
              "createdAt": "2026-04-19T10:00:00Z"
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let migrated = try #require(decoded.transcription.terminology.entries.first)

    #expect(decoded.transcription.terminology.lastImportedSource == "/Users/test/terms.csv")
    #expect(decoded.transcription.terminology.lastImportedAt == "2026-04-19T10:00:00Z")
    #expect(migrated.source == "dictionary-import")
}

@Test
func configRoundTripPreservesUserDictionaryEntryFields() throws {
    var config = AppConfig()
    config.transcription.punctuationPreference = .halfWidth
    config.transcription.terminology.entries = [
        TerminologyEntry(
            type: .correction,
            original: "opencloud",
            replacement: "OpenClaw",
            aliases: [],
            isEnabled: true,
            source: "user",
            usageCount: 3,
            createdAt: "2026-05-07T10:00:00Z"
        ),
        TerminologyEntry(
            type: .term,
            original: "ExampleSDK",
            replacement: nil,
            aliases: [],
            isEnabled: true,
            source: "user",
            usageCount: 4,
            createdAt: "2026-05-07T10:01:00Z"
        ),
    ]

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let transcription = try #require(object["transcription"] as? [String: Any])
    let terminology = try #require(transcription["terminology"] as? [String: Any])
    let entries = try #require(terminology["entries"] as? [[String: Any]])

    #expect(decoded.transcription.terminology.entries == config.transcription.terminology.entries)
    #expect(decoded.transcription.punctuationPreference == .halfWidth)
    #expect(entries.allSatisfy { $0["caseSensitive"] == nil })
    #expect(entries.allSatisfy { ($0["type"] as? String) != "suggestion" })
}

@Test
func legacyConfigDefaultsToAutomaticPunctuation() throws {
    let data = Data(#"{"transcription":{"hintTerms":["VibeCompose"]}}"#.utf8)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.transcription.punctuationPreference == .automatic)
}

@Test
func legacySuggestionDictionaryEntryDecodesAsTerm() throws {
    let json = """
    {
      "type": "suggestion",
      "original": "ExampleSDK",
      "replacement": null,
      "aliases": [],
      "isEnabled": false,
      "source": "auto-suggestion",
      "usageCount": 4,
      "createdAt": "2026-05-07T10:01:00Z"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(TerminologyEntry.self, from: json)
    let encoded = try JSONEncoder().encode(decoded)
    let encodedJSON = String(data: encoded, encoding: .utf8) ?? ""

    #expect(decoded.type == .term)
    #expect(decoded.original == "ExampleSDK")
    #expect(decoded.source == "legacy-import")
    #expect(encodedJSON.contains("suggestion") == false)
}

@Test
func legacyCaseSensitiveDictionaryEntryDecodesButIsIgnored() throws {
    let json = """
    {
      "type": "correction",
      "original": "opencloud",
      "replacement": "OpenClaw",
      "aliases": [],
      "caseSensitive": true,
      "isEnabled": true,
      "source": "user",
      "usageCount": 0,
      "createdAt": "2026-05-07T10:00:00Z"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(TerminologyEntry.self, from: json)

    #expect(decoded.original == "opencloud")
    #expect(decoded.replacement == "OpenClaw")
}

@Test
func legacyCleanupConfigStillDecodesWithoutCrash() throws {
    let json = """
    {
      "cleanup": {
        "enabled": true,
        "endpoint": "https://example.com/v1/chat/completions",
        "model": "legacy-cleanup-model",
        "systemPrompt": "Legacy prompt",
        "authTokenEnv": "LEGACY_KEY",
        "authHeaderPrefix": "Bearer"
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    #expect(decoded.transcription.provider == .chatGPTManagedAuth)
    #expect(decoded.transcription.hintTerms.isEmpty)
    #expect(decoded.injection.preserveClipboard == false)
}

@Test
func legacyConfigWithoutTerminologyReencodesWithTerminologyDefaults() throws {
    let json = """
    {
      "transcription": {
        "hintTerms": ["VibeCompose"]
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let reencoded = try JSONEncoder().encode(decoded)
    let object = try #require(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
    let transcription = try #require(object["transcription"] as? [String: Any])
    let terminology = try #require(transcription["terminology"] as? [String: Any])

    #expect(terminology["enabled"] as? Bool == true)
    #expect(terminology["importedEntries"] == nil)
}

@Test
func configStoreUsesOnlyVibeComposeApplicationSupportPath() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ConfigStore(
        fileManager: FileManager.default,
        homeDirectoryURL: root
    )

    #expect(store.directoryURL.path == root.appendingPathComponent("Library/Application Support/VibeCompose", isDirectory: true).path)
}

@Test
func configStoreMigratesLegacyProviderChoicesToPublicAlphaChatGPTRoute() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ConfigStore(
        fileManager: .default,
        homeDirectoryURL: root
    )
    var legacy = AppConfig()
    legacy.transcription.provider = .openAICompatible
    legacy.transcription.openAIFallbackEnabled = true
    legacy.transcription.textPolish.chatGPTAuthEnabled = false
    legacy.transcription.textPolish.openAICompatibleEnabled = true
    legacy.transcription.textPolish.openAIFallbackEnabled = true
    try store.save(legacy)

    let loaded = try store.load()

    #expect(loaded.transcription.provider == .chatGPTManagedAuth)
    #expect(!loaded.transcription.openAIFallbackEnabled)
    #expect(loaded.transcription.textPolish.chatGPTAuthEnabled)
    #expect(!loaded.transcription.textPolish.openAICompatibleEnabled)
    #expect(!loaded.transcription.textPolish.openAIFallbackEnabled)
}

@Test
func configStoreDoesNotImportPreVibeComposeLegacyConfig() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    let firstLegacyComponent = ["Voice", "Dex"].joined()
    let legacyDirectory = root.appendingPathComponent("Library/Application Support/\(firstLegacyComponent)", isDirectory: true)
    try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    let legacyConfigURL = legacyDirectory.appendingPathComponent("config.json")
    try Data("""
    {
      "transcription": {
        "hintTerms": ["legacy-term"]
      }
    }
    """.utf8).write(to: legacyConfigURL)

    let store = ConfigStore(
        fileManager: fileManager,
        homeDirectoryURL: root
    )
    let loaded = try store.load()

    #expect(loaded.transcription.hintTerms.isEmpty)
    #expect(fileManager.fileExists(atPath: store.configURL.path))
    let storedData = try Data(contentsOf: store.configURL)
    let stored = try JSONDecoder().decode(AppConfig.self, from: storedData)
    #expect(stored.transcription.hintTerms.isEmpty)
}

@Test
func configStoreLoadDoesNotRewriteCanonicalConfig() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    let store = ConfigStore(
        fileManager: fileManager,
        homeDirectoryURL: root
    )
    // First load may create defaults; second settles decoder-applied defaults
    // into the encoder's canonical form.
    _ = try store.load()
    _ = try store.load()
    let settledData = try Data(contentsOf: store.configURL)
    let settledAttrs = try fileManager.attributesOfItem(atPath: store.configURL.path)
    let settledMod = settledAttrs[.modificationDate] as? Date

    // Brief pause so mtime would change if a rewrite occurred.
    Thread.sleep(forTimeInterval: 0.05)
    _ = try store.load()
    let thirdData = try Data(contentsOf: store.configURL)
    let thirdAttrs = try fileManager.attributesOfItem(atPath: store.configURL.path)
    let thirdMod = thirdAttrs[.modificationDate] as? Date

    #expect(settledData == thirdData)
    #expect(settledMod == thirdMod)
}

@Test
func configStoreLoadRewritesNonCanonicalConfig() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    let store = ConfigStore(
        fileManager: fileManager,
        homeDirectoryURL: root
    )
    try fileManager.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
    // Compact JSON without pretty-print / sorted keys is non-canonical.
    try Data(#"{"transcription":{"hintTerms":["alpha"]}}"#.utf8)
        .write(to: store.configURL)

    let loaded = try store.load()
    #expect(loaded.transcription.hintTerms == ["alpha"])
    let storedData = try Data(contentsOf: store.configURL)
    // Canonical form is pretty-printed with sorted keys — not identical to compact input.
    #expect(storedData != Data(#"{"transcription":{"hintTerms":["alpha"]}}"#.utf8))
    let stored = try JSONDecoder().decode(AppConfig.self, from: storedData)
    #expect(stored.transcription.hintTerms == ["alpha"])
}
