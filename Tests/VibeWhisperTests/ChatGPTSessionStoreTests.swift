import Foundation
import Testing
@testable import VibeWhisper

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
