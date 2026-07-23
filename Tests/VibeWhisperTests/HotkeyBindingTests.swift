import Carbon
import Foundation
import Testing
@testable import VibeWhisper

@Test
func hotkeyBindingDisplaysStableFunctionAndModifiedKeyNames() {
    #expect(HotkeyBinding.f5.displayName == "F5")

    let controlOptionD = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey)
    )
    #expect(controlOptionD.displayName == "⌃⌥D")
}

@Test
func hotkeyBindingRejectsUnsafeAndInternalConflicts() {
    #expect(
        throws:
            HotkeyBindingValidationError
                .modifierRequired
    ) {
        _ = try HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_D)
        ).validated()
    }
    #expect(
        throws:
            HotkeyBindingValidationError
                .escapeReserved
    ) {
        _ = try HotkeyBinding(
            keyCode: UInt32(kVK_Escape)
        ).validated()
    }
    #expect(
        throws:
            HotkeyBindingValidationError
                .systemShortcutReserved
    ) {
        _ = try HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey)
        ).validated()
    }
    #expect(
        throws:
            HotkeyBindingValidationError
                .quickAddConflict
    ) {
        _ = try HotkeyBinding.quickAdd.validated()
    }
}

@Test
func skillSwitcherShortcutMustRemainDistinctFromDictation() throws {
    try VibeWhisperShortcutSetValidator.validate(
        dictation: .f5,
        skillSwitcher: .skillSwitcher
    )

    #expect(
        throws:
            VibeWhisperShortcutConflictError
                .dictationAndSkillSwitcherMatch
    ) {
        try VibeWhisperShortcutSetValidator.validate(
            dictation: .skillSwitcher,
            skillSwitcher: .skillSwitcher
        )
    }
}

@MainActor
private final class FakeHotkeyToken {
    let binding: HotkeyBinding

    init(binding: HotkeyBinding) {
        self.binding = binding
    }
}

private enum FakeHotkeyError:
    Error,
    Equatable
{
    case conflict
    case persistence
}

@MainActor
@Test
func hotkeyRegistrationFallsBackToF5WithoutTerminating() {
    let requested = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey)
    )
    var attempts: [HotkeyBinding] = []
    let service = HotkeyRegistrationService {
        binding,
        _ in
        attempts.append(binding)
        if binding == requested {
            throw FakeHotkeyError.conflict
        }
        return FakeHotkeyToken(binding: binding)
    }

    let outcome = service.start(
        preferred: requested,
        onPress: {}
    )

    #expect(
        outcome.activeBinding == .f5
    )
    #expect(service.activeBinding == .f5)
    #expect(attempts == [requested, .f5])
}

@MainActor
@Test
func hotkeyRegistrationKeepsOldBindingWhenPersistenceFails() throws {
    let replacement = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey)
    )
    var attempts: [HotkeyBinding] = []
    let service = HotkeyRegistrationService {
        binding,
        _ in
        attempts.append(binding)
        return FakeHotkeyToken(binding: binding)
    }
    _ = service.start(
        preferred: .f5,
        onPress: {}
    )

    #expect(throws: FakeHotkeyError.persistence) {
        try service.replace(
            with: replacement,
            onPress: {}
        ) {
            throw FakeHotkeyError.persistence
        }
    }

    #expect(service.activeBinding == .f5)
    #expect(attempts == [.f5, replacement])

    try service.replace(
        with: replacement,
        onPress: {}
    ) {}
    #expect(service.activeBinding == replacement)
}

@MainActor
@Test
func hotkeyRegistrationSuspendsDuringRecorderCaptureAndResumesTheSameBinding()
    throws
{
    var liveTokens: [FakeHotkeyToken] = []
    let service = HotkeyRegistrationService {
        binding,
        _ in
        let token = FakeHotkeyToken(
            binding: binding
        )
        liveTokens.append(token)
        return token
    }

    _ = service.start(
        preferred: .f5,
        onPress: {}
    )
    #expect(service.isSuspended == false)

    service.suspend()
    #expect(service.activeBinding == .f5)
    #expect(service.isSuspended == true)

    try service.resume()
    #expect(service.activeBinding == .f5)
    #expect(service.isSuspended == false)
    #expect(
        liveTokens.map(\.binding)
            == [.f5, .f5]
    )
}
