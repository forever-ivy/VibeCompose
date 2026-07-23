import Foundation

enum ManagedEndpointKind: Sendable, CaseIterable {
    case transcription
    case responses

    var url: URL {
        switch self {
        case .transcription:
            return ManagedEndpointPolicy.transcriptionURL
        case .responses:
            return ManagedEndpointPolicy.responsesURL
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
            return L10n.text("OpenWhisper blocked a non-approved endpoint for the managed ChatGPT session.")
        }
    }
}

enum ManagedEndpointPolicy {
    static let transcriptionURL = makeURL("https://chatgpt.com/backend-api/transcribe")
    static let responsesURL = makeURL("https://chatgpt.com/backend-api/codex/responses")

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
            components.query == nil,
            components.fragment == nil
        else {
            throw EndpointPolicyError.disallowedManagedEndpoint(candidate.absoluteString)
        }

        return expected
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
            preconditionFailure("Invalid built-in OpenWhisper endpoint: \(value)")
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
