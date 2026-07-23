import Foundation
import Testing
@testable import OpenWhisper

@Test
func managedEndpointPolicyAcceptsOnlyExactBuiltInEndpoints() throws {
    #expect(
        try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.transcriptionURL,
            for: .transcription
        ) == ManagedEndpointPolicy.transcriptionURL
    )
    #expect(
        try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.responsesURL,
            for: .responses
        ) == ManagedEndpointPolicy.responsesURL
    )
}

@Test(
    arguments: [
        "http://chatgpt.com/backend-api/transcribe",
        "https://attacker.invalid/backend-api/transcribe",
        "https://chatgpt.com:444/backend-api/transcribe",
        "https://user@chatgpt.com/backend-api/transcribe",
        "https://chatgpt.com/backend-api/transcribe?next=https://attacker.invalid",
        "https://chatgpt.com/backend-api/codex/responses",
    ]
)
func managedTranscriptionEndpointRejectsNonAllowlistedURLs(_ value: String) {
    let candidate = URL(string: value)!
    #expect(throws: EndpointPolicyError.self) {
        try ManagedEndpointPolicy.validatedURL(candidate, for: .transcription)
    }
}

@Test
func legacyManagedEndpointConfigurationIsIgnoredAndNotReencoded() throws {
    let data = Data(
        """
        {
          "transcription": {
            "provider": "chatGPTManagedAuth",
            "chatGPTURL": "https://attacker.invalid/collect",
            "textPolish": {
              "chatGPTResponseURL": "https://attacker.invalid/responses"
            }
          }
        }
        """.utf8
    )

    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    let encoded = try JSONEncoder().encode(config)
    let encodedText = String(decoding: encoded, as: UTF8.self)

    #expect(config.transcription.provider == .chatGPTManagedAuth)
    #expect(encodedText.contains("attacker.invalid") == false)
    #expect(encodedText.contains("chatGPTURL") == false)
    #expect(encodedText.contains("chatGPTResponseURL") == false)
}

@Test
func userOwnedEndpointRequiresHTTPSAndNoUserInfo() throws {
    #expect(
        try ManagedEndpointPolicy.validatedUserOwnedURL(
            "https://api.example.com/v1/audio/transcriptions"
        ).absoluteString == "https://api.example.com/v1/audio/transcriptions"
    )
    #expect(throws: EndpointPolicyError.self) {
        try ManagedEndpointPolicy.validatedUserOwnedURL("http://api.example.com/transcribe")
    }
    #expect(throws: EndpointPolicyError.self) {
        try ManagedEndpointPolicy.validatedUserOwnedURL("https://token@api.example.com/transcribe")
    }
}
