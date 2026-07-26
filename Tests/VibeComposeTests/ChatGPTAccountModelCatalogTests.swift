import Foundation
import Testing
@testable import VibeCompose

@Test
func accountModelCatalogParsesCodexModelsResponse() {
    let json = """
    {
      "models": [
        {
          "slug": "gpt-5.4",
          "display_name": "GPT-5.4",
          "visibility": "list",
          "is_default": true,
          "supported_in_api": true
        },
        {
          "slug": "gpt-5.5",
          "display_name": "GPT-5.5",
          "visibility": "list",
          "is_default": false
        },
        {
          "slug": "internal-hidden",
          "visibility": "hidden"
        }
      ]
    }
    """.data(using: .utf8)!

    let models = ChatGPTAccountModelCatalog.parseModels(from: json)
    #expect(models.map(\.slug) == ["gpt-5.4", "gpt-5.5"])
    #expect(models.first?.isDefault == true)
    #expect(!models.contains(where: { $0.slug == "internal-hidden" }))
}

@Test
func accountModelCatalogFallsBackToAllWhenEveryModelIsHidden() {
    let json = """
    {
      "models": [
        { "slug": "only-hidden", "visibility": "hidden" }
      ]
    }
    """.data(using: .utf8)!

    let models = ChatGPTAccountModelCatalog.parseModels(from: json)
    #expect(models.map(\.slug) == ["only-hidden"])
}

@Test
func accountModelCatalogParsesOpenAIStyleDataList() {
    let json = """
    {
      "data": [
        { "id": "gpt-4.1" },
        { "id": "gpt-4o" },
        { "id": "whisper-1" }
      ]
    }
    """.data(using: .utf8)!

    let models = ChatGPTAccountModelCatalog.parseModels(from: json)
    #expect(models.map(\.slug) == ["gpt-4.1", "gpt-4o", "whisper-1"])
}

@Test
func accountModelCatalogDoesNotDropRealModelsOutsidePresets() {
    let preferred = ProductModelCatalog.rewritePresets
    let extra = ["gpt-5.4", "o3", "my-custom-account-model"]
    let merged = ChatGPTAccountModelCatalog.mergePreservingOrder(
        preferred: preferred,
        extra: extra
    )
    for id in extra {
        #expect(merged.contains(id))
    }
    #expect(merged.first == preferred.first)
}

@Test
func accountModelCatalogResolveUsesLiveModelsNotOnlyPresets() async throws {
    let payload = """
    {
      "models": [
        { "slug": "gpt-5.4", "visibility": "list", "is_default": true },
        { "slug": "o3", "visibility": "list" },
        { "slug": "gpt-4.1", "visibility": "list" }
      ]
    }
    """.data(using: .utf8)!

    let catalog = ChatGPTAccountModelCatalog(
        dataLoader: { request in
            #expect(request.url?.path == "/backend-api/codex/models")
            #expect(request.url?.host == "chatgpt.com")
            #expect(request.url?.query?.contains("client_version=1.0.0") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (payload, response)
        },
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let snapshot = await catalog.resolveForPicker(
        accessToken: "test-token",
        forceRefresh: true
    )
    #expect(snapshot.usedFallbackPresets == false)
    #expect(snapshot.pickerSlugs == ["gpt-5.4", "o3", "gpt-4.1"])
    #expect(snapshot.defaultSlug == "gpt-5.4")
    #expect(snapshot.message == nil)
}

@Test
func accountModelCatalogFallsBackWithExplicitMessageOnHTTPError() async {
    let catalog = ChatGPTAccountModelCatalog(
        dataLoader: { request in
            let body = #"{"error":{"message":"model catalog unavailable"}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        },
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let snapshot = await catalog.resolveForPicker(
        accessToken: "test-token",
        forceRefresh: true
    )
    #expect(snapshot.usedFallbackPresets)
    #expect(snapshot.pickerSlugs == ProductModelCatalog.rewritePresets)
    #expect(snapshot.message?.contains("model catalog unavailable") == true)
}

@Test
func accountModelCatalogAttachesChatGPTAccountIDWhenPresentInJWT() async {
    // Minimal JWT: header.payload.sig with chatgpt_account_id claim.
    // {"https://api.openai.com/auth":{"chatgpt_account_id":"acct_test_123"}}
    let payloadJSON =
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_test_123"}}"#
    let payloadB64 = Data(payloadJSON.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    let token = "aaa.\(payloadB64).bbb"

    let catalog = ChatGPTAccountModelCatalog(
        dataLoader: { request in
            #expect(
                request.value(forHTTPHeaderField: "ChatGPT-Account-ID")
                    == "acct_test_123"
            )
            let body = #"{"models":[{"slug":"gpt-5.5","visibility":"list"}]}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        }
    )

    let snapshot = await catalog.resolveForPicker(
        accessToken: token,
        forceRefresh: true
    )
    #expect(snapshot.usedFallbackPresets == false)
    #expect(snapshot.pickerSlugs == ["gpt-5.5"])
}

@Test
func accountModelCatalogDefaultClientVersionIsCodexCompatible() {
    #expect(ChatGPTAccountModelCatalog.codexModelsClientVersion == "1.0.0")
}

@Test
func accountModelCatalogRequiresSignIn() async {
    let catalog = ChatGPTAccountModelCatalog(
        dataLoader: { _ in
            Issue.record("Network must not run without a token.")
            throw URLError(.notConnectedToInternet)
        }
    )

    let snapshot = await catalog.resolveForPicker(
        accessToken: nil,
        forceRefresh: true
    )
    #expect(snapshot.usedFallbackPresets)
    #expect(snapshot.pickerSlugs == ProductModelCatalog.rewritePresets)
    #expect(snapshot.message?.isEmpty == false)
}

@Test
func modelsListURLAllowsClientVersionOnly() throws {
    let url = try ManagedEndpointPolicy.modelsListURL(clientVersion: "0.1.0")
    #expect(url.host == "chatgpt.com")
    #expect(url.path == "/backend-api/codex/models")
    #expect(url.query == "client_version=0.1.0")

    #expect(
        try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.modelsURL,
            for: .models
        ) == ManagedEndpointPolicy.modelsURL
    )

    #expect(throws: EndpointPolicyError.self) {
        try ManagedEndpointPolicy.validatedURL(
            URL(string: "https://chatgpt.com/backend-api/codex/models?next=https://evil.example")!,
            for: .models
        )
    }
}

@Test
func providerFailureSurfacesModelRejectionDetail() {
    let failure = ProviderRequestFailure(
        route: .textPolish,
        category: .requestRejected,
        statusCode: 400,
        detail: "The model `gpt-5.5` does not exist or you do not have access to it."
    )
    let description = failure.errorDescription ?? ""
    #expect(description.contains("rejected the selected model"))
    #expect(description.contains("gpt-5.5"))
}
