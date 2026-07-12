import Foundation
import Testing
@testable import OpenWhisper

@Test
func defaultConfigUsesChatGPTAccountDefaults() throws {
    let config = AppConfig()
    #expect(config.transcription.hotkeyKeyCode == 96)
    #expect(config.transcription.provider == .chatGPTManagedAuth)
    #expect(config.transcription.openAITranscriptionURL == "https://api.openai.com/v1/audio/transcriptions")
    #expect(config.transcription.openAIModel == "gpt-4o-mini-transcribe")
    #expect(config.transcription.openAIAuthTokenEnv == "OPENAI_API_KEY")
    #expect(config.transcription.hintTerms.isEmpty)
    #expect(config.transcription.speechCleanupEnabled == true)
    #expect(config.transcription.feedbackSoundsEnabled == true)
    #expect(config.injection.preserveClipboard == false)
    #expect(config.auth.preferredLoginSurface == .defaultBrowser)
    #expect(config.auth.allowEmbeddedFallback == false)
    #expect(config.auth.persistCapturedSession == true)
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
    #expect(json.contains("sk-") == false)
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
              "keychainService": "openwhisper-groq-api-key",
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
              "keychainService": "openwhisper-deepseek-api-key",
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
        "OpenWhisper",
        "review",
    ]

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.transcription.hintTerms == [
        "budget v2.xlsx",
        "OpenWhisper",
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
            canonical: "OpenWhisper",
            aliases: ["Chat Type"]
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
    #expect(decoded.transcription.terminology.entries[0].canonical == "OpenWhisper")
    #expect(decoded.transcription.terminology.entries[0].aliases == ["Chat Type"])
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
              "original": "OpenWhisper",
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
    #expect(entries.allSatisfy { $0["caseSensitive"] == nil })
    #expect(entries.allSatisfy { ($0["type"] as? String) != "suggestion" })
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
        "hintTerms": ["OpenWhisper"]
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
func configStoreUsesOnlyOpenWhisperApplicationSupportPath() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ConfigStore(
        fileManager: FileManager.default,
        homeDirectoryURL: root
    )

    #expect(store.directoryURL.path == root.appendingPathComponent("Library/Application Support/OpenWhisper", isDirectory: true).path)
}

@Test
func configStoreDoesNotImportPreOpenWhisperLegacyConfig() throws {
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
