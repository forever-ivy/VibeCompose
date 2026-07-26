import Foundation
import Testing
@testable import VibeCompose

@Test
func inMemorySessionStoreRoundTripsSession() throws {
    let store = InMemoryChatGPTSessionStore()
    let session = ChatGPTSession(
        accessToken: "token-1",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000),
        cookies: [],
        userEmail: "user@example.com",
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    try store.save(session)

    #expect(try store.load() == session)
}

@Test
func sessionTokenIsUsableBeforeExpiry() {
    let session = ChatGPTSession(
        accessToken: "token-1",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000),
        cookies: [],
        userEmail: nil,
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    #expect(session.tokenIsUsable(now: Date(timeIntervalSince1970: 1_500)) == true)
    #expect(session.tokenIsUsable(now: Date(timeIntervalSince1970: 2_500)) == false)
}

@Test
func keychainSessionStoreMigratesAnExplicitPreRenameServiceOnce() throws {
    let suffix = UUID().uuidString
    let currentService = "app.vibecompose.mac.tests.ChatGPTSession.\(suffix)"
    let legacyService = "app.vibecompose.mac.tests.LegacyChatGPTSession.\(suffix)"
    let legacyStore = KeychainChatGPTSessionStore(
        service: legacyService,
        account: "migration-test"
    )
    let currentOnlyStore = KeychainChatGPTSessionStore(
        service: currentService,
        account: "migration-test"
    )
    let migratingStore = KeychainChatGPTSessionStore(
        service: currentService,
        account: "migration-test",
        legacyService: legacyService
    )
    let session = ChatGPTSession(
        accessToken: "migration-token",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 4_000),
        refreshToken: "migration-refresh",
        cookies: [],
        userEmail: "migration@example.com",
        updatedAt: Date(timeIntervalSince1970: 3_000)
    )
    defer {
        try? currentOnlyStore.delete()
        try? legacyStore.delete()
    }

    try currentOnlyStore.delete()
    try legacyStore.delete()
    try legacyStore.save(session)

    #expect(try currentOnlyStore.load() == nil)
    #expect(try migratingStore.load() == session)
    #expect(try currentOnlyStore.load() == session)
    #expect(try legacyStore.load() == session)

    try migratingStore.delete()
    #expect(try currentOnlyStore.load() == nil)
    #expect(try legacyStore.load() == nil)
}
