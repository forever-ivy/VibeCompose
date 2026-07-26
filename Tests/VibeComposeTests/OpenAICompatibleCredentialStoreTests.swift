import Foundation
import Testing
@testable import VibeCompose

@Test
func recoveryCredentialStoreTrimsSavesLoadsAndDeletes() throws {
    let store = InMemoryOpenAICompatibleCredentialStore()

    #expect(try store.hasAPIKey() == false)
    #expect(try store.loadAPIKey() == nil)

    try store.saveAPIKey(" \n keychain-secret \t")

    #expect(try store.hasAPIKey())
    #expect(try store.loadAPIKey() == "keychain-secret")

    try store.deleteAPIKey()

    #expect(try store.hasAPIKey() == false)
    #expect(try store.loadAPIKey() == nil)
}

@Test
func recoveryCredentialStoreRejectsEmptyKeys() {
    let store = InMemoryOpenAICompatibleCredentialStore()

    #expect(throws: OpenAICompatibleCredentialStoreError.emptyAPIKey) {
        try store.saveAPIKey(" \n\t ")
    }
}

@Test
func recoveryCredentialStoreRejectsOversizedKeys() {
    let store = InMemoryOpenAICompatibleCredentialStore()
    let oversized = String(repeating: "x", count: 8 * 1024 + 1)

    #expect(throws: OpenAICompatibleCredentialStoreError.apiKeyTooLong) {
        try store.saveAPIKey(oversized)
    }
}

@Test
func recoveryCredentialAvailabilityValidatesStoredMaterial() {
    let store = InMemoryOpenAICompatibleCredentialStore(apiKey: "   ")

    #expect(throws: OpenAICompatibleCredentialStoreError.emptyAPIKey) {
        try store.hasAPIKey()
    }
}

@Test
func keychainRecoveryCredentialStoreRoundTripsInIsolatedService() throws {
    let store = KeychainOpenAICompatibleCredentialStore(
        service:
            "app.vibecompose.mac.tests.OpenAICompatibleAPIKey.\(UUID().uuidString)",
        account: "unit-test"
    )
    defer {
        try? store.deleteAPIKey()
    }

    try store.deleteAPIKey()
    #expect(try store.hasAPIKey() == false)

    try store.saveAPIKey("  isolated-keychain-secret  ")

    #expect(try store.hasAPIKey())
    #expect(try store.loadAPIKey() == "isolated-keychain-secret")

    try store.deleteAPIKey()
    #expect(try store.loadAPIKey() == nil)
}

@Test
func keychainRecoveryCredentialStoreMigratesAnExplicitPreRenameServiceOnce() throws {
    let suffix = UUID().uuidString
    let currentService =
        "app.vibecompose.mac.tests.OpenAICompatibleAPIKey.\(suffix)"
    let legacyService =
        "app.vibecompose.mac.tests.LegacyOpenAICompatibleAPIKey.\(suffix)"
    let legacyStore = KeychainOpenAICompatibleCredentialStore(
        service: legacyService,
        account: "migration-test"
    )
    let currentOnlyStore = KeychainOpenAICompatibleCredentialStore(
        service: currentService,
        account: "migration-test"
    )
    let migratingStore = KeychainOpenAICompatibleCredentialStore(
        service: currentService,
        account: "migration-test",
        legacyService: legacyService
    )
    defer {
        try? currentOnlyStore.deleteAPIKey()
        try? legacyStore.deleteAPIKey()
    }

    try currentOnlyStore.deleteAPIKey()
    try legacyStore.deleteAPIKey()
    try legacyStore.saveAPIKey("legacy-secret")

    #expect(try currentOnlyStore.loadAPIKey() == nil)
    #expect(try migratingStore.loadAPIKey() == "legacy-secret")
    #expect(try currentOnlyStore.loadAPIKey() == "legacy-secret")
    #expect(try legacyStore.loadAPIKey() == "legacy-secret")

    try migratingStore.deleteAPIKey()
    #expect(try currentOnlyStore.loadAPIKey() == nil)
    #expect(try legacyStore.loadAPIKey() == nil)
}
