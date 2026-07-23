import Foundation

enum ManagedEndpointKind: Sendable, CaseIterable {
    case transcription
    case responses
    /// Account-scoped Codex model catalog (`GET …/codex/models`).
    case models

    var url: URL {
        switch self {
        case .transcription:
            return ManagedEndpointPolicy.transcriptionURL
        case .responses:
            return ManagedEndpointPolicy.responsesURL
        case .models:
            return ManagedEndpointPolicy.modelsURL
        }
    }
}

enum EndpointPolicyError: LocalizedError, Equatable {
    case invalidURL(String)
    case disallowedManagedEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return L10n.format("The configured endpoint is invalid: %@", value)
        case .disallowedManagedEndpoint:
            return L10n.text("VibeWhisper blocked a non-approved endpoint for the managed ChatGPT session.")
        }
    }
}

enum ManagedEndpointPolicy {
    static let transcriptionURL = makeURL("https://chatgpt.com/backend-api/transcribe")
    static let responsesURL = makeURL("https://chatgpt.com/backend-api/codex/responses")
    /// Codex account model catalog. Same origin as responses; query may only add `client_version`.
    static let modelsURL = makeURL("https://chatgpt.com/backend-api/codex/models")

    static func validatedURL(_ candidate: URL, for kind: ManagedEndpointKind) throws -> URL {
        let expected = kind.url
        guard
            let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == "chatgpt.com",
            components.port == nil || components.port == 443,
            components.user == nil,
            components.password == nil,
            components.path == expected.path,
            components.fragment == nil
        else {
            throw EndpointPolicyError.disallowedManagedEndpoint(candidate.absoluteString)
        }

        switch kind {
        case .transcription, .responses:
            guard components.query == nil else {
                throw EndpointPolicyError.disallowedManagedEndpoint(candidate.absoluteString)
            }
            return expected
        case .models:
            // Codex clients append `?client_version=…` only. Reject any other query shape.
            if let items = components.queryItems, !items.isEmpty {
                guard
                    items.count == 1,
                    items[0].name == "client_version",
                    let value = items[0].value,
                    !value.isEmpty,
                    value.allSatisfy({ $0.isASCII && !$0.isWhitespace })
                else {
                    throw EndpointPolicyError.disallowedManagedEndpoint(candidate.absoluteString)
                }
                return candidate
            }
            return expected
        }
    }

    /// Build the approved models catalog URL with an optional Codex `client_version` query.
    static func modelsListURL(clientVersion: String) throws -> URL {
        let trimmed = clientVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try validatedURL(modelsURL, for: .models)
        }
        var components = URLComponents(url: modelsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_version", value: trimmed),
        ]
        guard let url = components.url else {
            throw EndpointPolicyError.invalidURL(modelsURL.absoluteString)
        }
        return try validatedURL(url, for: .models)
    }

    static func validatedUserOwnedURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil
        else {
            throw EndpointPolicyError.invalidURL(value)
        }
        return url
    }

    private static func makeURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid built-in VibeWhisper endpoint: \(value)")
        }
        return url
    }
}

private final class RedirectRejectingSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum SecureHTTPClient {
    private static let delegate = RedirectRejectingSessionDelegate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }()

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    static func upload(
        for request: URLRequest,
        fromFile bodyFileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await session.upload(for: request, fromFile: bodyFileURL)
    }
}
