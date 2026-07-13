import Foundation
import Testing
@testable import OpenWhisper

@Test
func voiceModeDefaultsToDirectWithoutApplicationRules() {
    let config = VoiceModeConfig()

    #expect(config.defaultMode == .direct)
    #expect(config.applicationRules.isEmpty)
    #expect(config.resolvedMode(for: nil) == .direct)
}

@Test
func applicationVoiceModeRuleNormalizesAndMatchesBundleIdentifier() throws {
    let rule = try AppModeRule.validated(
        appName: "  Notes  ",
        bundleIdentifier: " COM.APPLE.Notes ",
        mode: .email
    )
    let config = VoiceModeConfig(
        defaultMode: .direct,
        applicationRules: [rule]
    )
    let context = LaunchAppContext(
        bundleIdentifier: "com.apple.notes",
        localizedName: "Notes",
        processIdentifier: 42
    )

    #expect(rule.appName == "Notes")
    #expect(rule.bundleIdentifier == "com.apple.notes")
    #expect(config.resolvedMode(for: context) == .email)
}

@Test
func disabledOrUnknownApplicationRuleFallsBackToDefaultMode() throws {
    let disabled = try AppModeRule.validated(
        appName: "Codex",
        bundleIdentifier: "com.openai.codex",
        mode: .agentPlan,
        isEnabled: false
    )
    let config = VoiceModeConfig(
        defaultMode: .reply,
        applicationRules: [disabled]
    )

    #expect(
        config.resolvedMode(
            for: LaunchAppContext(
                bundleIdentifier: "com.openai.codex",
                localizedName: "Codex",
                processIdentifier: 7
            )
        ) == .reply
    )
    #expect(
        config.resolvedMode(
            for: LaunchAppContext(
                bundleIdentifier: "com.apple.mail",
                localizedName: "Mail",
                processIdentifier: 8
            )
        ) == .reply
    )
}

@Test
func voiceModeRuleRejectsMalformedBundleIdentifier() {
    #expect(throws: VoiceModeRuleError.invalidBundleIdentifier) {
        _ = try AppModeRule.validated(
            appName: "Invalid",
            bundleIdentifier: "../not a bundle",
            mode: .reply
        )
    }
}

@Test
func voiceModeConfigDropsInvalidAndDuplicateDecodedRules() throws {
    let json = """
    {
      "defaultMode": "agentPlan",
      "applicationRules": [
        {
          "appName": "Notes",
          "bundleIdentifier": "COM.APPLE.NOTES",
          "mode": "email",
          "isEnabled": true
        },
        {
          "appName": "Duplicate Notes",
          "bundleIdentifier": "com.apple.notes",
          "mode": "reply",
          "isEnabled": true
        },
        {
          "appName": "Invalid",
          "bundleIdentifier": "../escape",
          "mode": "translate",
          "isEnabled": true
        }
      ]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        VoiceModeConfig.self,
        from: json
    )

    #expect(decoded.defaultMode == .agentPlan)
    #expect(decoded.applicationRules.count == 1)
    #expect(
        decoded.applicationRules.first?.bundleIdentifier
            == "com.apple.notes"
    )
    #expect(decoded.applicationRules.first?.mode == .email)
}

@Test
func resolvedTranscriptionConfigFreezesModeAndRemovesRuleList() throws {
    var transcription = TranscriptionConfig()
    transcription.voiceModes = VoiceModeConfig(
        defaultMode: .direct,
        applicationRules: [
            try AppModeRule.validated(
                appName: "Codex",
                bundleIdentifier: "com.openai.codex",
                mode: .codePrompt
            ),
        ]
    )

    let resolved = transcription.resolvingVoiceMode(
        for: LaunchAppContext(
            bundleIdentifier: "COM.OPENAI.CODEX",
            localizedName: "Codex",
            processIdentifier: 9
        )
    )

    #expect(resolved.voiceModes.defaultMode == .codePrompt)
    #expect(resolved.voiceModes.applicationRules.isEmpty)
    #expect(transcription.voiceModes.defaultMode == .direct)
    #expect(transcription.voiceModes.applicationRules.count == 1)
}

@Test
func unlicensedRuntimeForcesDirectAndStripsApplicationRules() throws {
    var transcription = TranscriptionConfig()
    transcription.voiceModes = VoiceModeConfig(
        defaultMode: .email,
        applicationRules: [
            try AppModeRule.validated(
                appName: "Codex",
                bundleIdentifier: "com.openai.codex",
                mode: .agentPlan
            ),
        ]
    )

    let resolved = transcription.resolvingVoiceMode(
        for: LaunchAppContext(
            bundleIdentifier: "com.openai.codex",
            localizedName: "Codex",
            processIdentifier: 9
        ),
        voiceModesAllowed: false
    )

    #expect(resolved.voiceModes.defaultMode == .direct)
    #expect(resolved.voiceModes.applicationRules.isEmpty)
    #expect(transcription.voiceModes.defaultMode == .email)
}

@Test
func voiceModeConfigUpsertKeepsOneRulePerBundleIdentifier() throws {
    var config = VoiceModeConfig()
    config.upsert(
        try AppModeRule.validated(
            appName: "Notes",
            bundleIdentifier: "com.apple.notes",
            mode: .email
        )
    )
    config.upsert(
        try AppModeRule.validated(
            appName: "Notes",
            bundleIdentifier: "COM.APPLE.NOTES",
            mode: .reply
        )
    )

    #expect(config.applicationRules.count == 1)
    #expect(config.applicationRules.first?.mode == .reply)
}

@Test
func voiceModeConfigReportsWhenAnyEnabledModeNeedsTextPolish() throws {
    var config = VoiceModeConfig()
    #expect(config.requiresTextPolish == false)

    config = VoiceModeConfig(
        defaultMode: .email,
        applicationRules: []
    )
    #expect(config.requiresTextPolish)

    config = VoiceModeConfig(
        defaultMode: .direct,
        applicationRules: [
            try AppModeRule.validated(
                appName: "Codex",
                bundleIdentifier: "com.openai.codex",
                mode: .codePrompt
            ),
        ]
    )
    #expect(config.requiresTextPolish)

    config.applicationRules[0].isEnabled = false
    #expect(config.requiresTextPolish == false)
}

@Test
func unknownVoiceModesFallBackWithoutBreakingConfigDecoding() throws {
    let json = """
    {
      "defaultMode": "future-mode",
      "applicationRules": [
        {
          "appName": "Notes",
          "bundleIdentifier": "com.apple.notes",
          "mode": "future-mode",
          "isEnabled": true
        }
      ]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        VoiceModeConfig.self,
        from: json
    )

    #expect(decoded.defaultMode == .direct)
    #expect(decoded.applicationRules.first?.mode == .direct)
}

@Test
func duplicateVoiceModeRuleIdentifiersAreDroppedDuringDecoding() throws {
    let duplicateID = UUID()
    let json = """
    {
      "defaultMode": "direct",
      "applicationRules": [
        {
          "id": "\(duplicateID.uuidString)",
          "appName": "Notes",
          "bundleIdentifier": "com.apple.notes",
          "mode": "email",
          "isEnabled": true
        },
        {
          "id": "\(duplicateID.uuidString)",
          "appName": "Mail",
          "bundleIdentifier": "com.apple.mail",
          "mode": "email",
          "isEnabled": true
        }
      ]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        VoiceModeConfig.self,
        from: json
    )

    #expect(decoded.applicationRules.count == 1)
    #expect(
        decoded.applicationRules.first?.bundleIdentifier
            == "com.apple.notes"
    )
}
