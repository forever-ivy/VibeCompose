import Carbon
import Foundation
import Testing

@testable import VibeCompose

@Suite("AppConfig 3-way merge")
struct AppConfigMergeTests {
    private static let f6 = HotkeyBinding(
        keyCode: UInt32(kVK_F6)
    )

    @Test
    func cleanLocalTakesRemoteEntirely() {
        let base = AppConfig()
        var remote = base
        remote.skillEcosystem.favoriteInstallationIDs = [
            UUID(),
        ]
        remote.visualFeedback.mode = .aiActivityGlow

        let merged = AppConfig.merging(
            base: base,
            local: base,
            remote: remote
        )
        #expect(merged == remote)
    }

    @Test
    func dirtyLocalPreservesWhileAdoptingRemoteElsewhere() {
        let base = AppConfig()
        var local = base
        local.visualFeedback.mode = .hidden

        var remote = base
        let installationID = UUID()
        remote.skillEcosystem.favoriteInstallationIDs = [
            installationID,
        ]
        remote.skillEcosystem.recordRecent(
            installationID: installationID
        )

        let merged = AppConfig.merging(
            base: base,
            local: local,
            remote: remote
        )
        #expect(merged.visualFeedback.mode == .hidden)
        #expect(
            merged.skillEcosystem.favoriteInstallationIDs
                == [installationID]
        )
        #expect(
            merged.skillEcosystem.recentInstallationIDs
                .contains(installationID)
        )
    }

    @Test
    func dirtyHotkeyDoesNotClobberRemoteSkillDefault() {
        let base = AppConfig()
        var local = base
        local.transcription.dictationHotkey = Self.f6

        var remote = base
        let skillID = "skill.test"
        let installationID = UUID()
        remote.transcription.skills.defaultSkillID = skillID
        remote.transcription.skills
            .defaultSkillInstallationID = installationID

        let merged = AppConfig.merging(
            base: base,
            local: local,
            remote: remote
        )
        #expect(merged.transcription.dictationHotkey == Self.f6)
        #expect(
            merged.transcription.skills.defaultSkillID
                == skillID
        )
        #expect(
            merged.transcription.skills
                .defaultSkillInstallationID
                == installationID
        )
    }

    @Test
    func remoteTerminologyPlusLocalVisualFeedback() {
        let base = AppConfig()
        var local = base
        local.visualFeedback.showStatusText = false

        var remote = base
        remote.transcription.terminology.enabled = true
        remote.transcription.terminology.entries = [
            TerminologyEntry(
                type: .term,
                original: "foo",
                replacement: nil,
                aliases: [],
                isEnabled: true,
                source: "test",
                usageCount: 0,
                createdAt: "2026-01-01T00:00:00Z"
            ),
        ]

        let merged = AppConfig.merging(
            base: base,
            local: local,
            remote: remote
        )
        #expect(merged.visualFeedback.showStatusText == false)
        #expect(
            merged.transcription.terminology.entries.count
                == 1
        )
        #expect(
            merged.transcription.terminology.entries[0]
                .original == "foo"
        )
    }

    @Test
    func identityWhenAllEqual() {
        let config = AppConfig()
        let merged = AppConfig.merging(
            base: config,
            local: config,
            remote: config
        )
        #expect(merged == config)
    }

    @Test
    func localEqualsRemoteReturnsLocal() {
        let base = AppConfig()
        var next = base
        next.privacy.historyEnabled = false
        let merged = AppConfig.merging(
            base: base,
            local: next,
            remote: next
        )
        #expect(merged == next)
    }
}
