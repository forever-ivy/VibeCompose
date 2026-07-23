import Foundation

enum OpenAICompatibleConnectionTestError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case missingModel
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L10n.text(
                "Save an OpenAI-Compatible API key in Keychain before testing."
            )
        case .invalidEndpoint(let message):
            return message
        case .missingModel:
            return L10n.text(
                "Enter an OpenAI-Compatible transcription model before testing."
            )
        case .invalidResponse:
            return L10n.text(
                "The OpenAI-Compatible endpoint did not return an HTTP response."
            )
        case .requestFailed(let statusCode, let message):
            return L10n.format(
                "OpenAI-Compatible connection test failed (HTTP %d): %@",
                statusCode,
                message
            )
        }
    }
}

struct OpenAICompatibleConnectionTester: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (
        Data,
        URLResponse
    )

    let credentialStore: any OpenAICompatibleCredentialPersisting
    let dataLoader: DataLoader

    init(
        credentialStore: any OpenAICompatibleCredentialPersisting,
        dataLoader: @escaping DataLoader = { request in
            try await SecureHTTPClient.data(for: request)
        }
    ) {
        self.credentialStore = credentialStore
        self.dataLoader = dataLoader
    }

    func test(config: TranscriptionConfig) async throws {
        guard let apiKey = try credentialStore.loadAPIKey() else {
            throw OpenAICompatibleConnectionTestError.missingAPIKey
        }
        let model = config.openAIModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw OpenAICompatibleConnectionTestError.missingModel
        }

        let endpoint: URL
        do {
            endpoint = try ManagedEndpointPolicy.validatedUserOwnedURL(
                config.openAITranscriptionURL
            )
        } catch {
            throw OpenAICompatibleConnectionTestError.invalidEndpoint(
                error.localizedDescription
            )
        }

        let boundary = "VibeWhisper-Connection-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            boundary: boundary,
            model: model,
            waveData: Self.syntheticSilenceWave()
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            String(body.count),
            forHTTPHeaderField: "Content-Length"
        )
        request.setValue(
            ProductIdentity.userAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.httpBody = body

        let (responseData, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleConnectionTestError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleConnectionTestError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.providerMessage(
                    from: responseData,
                    apiKey: apiKey
                )
                    ?? HTTPURLResponse.localizedString(
                        forStatusCode: httpResponse.statusCode
                    )
            )
        }
    }

    private static func makeMultipartBody(
        boundary: String,
        model: String,
        waveData: Data
    ) -> Data {
        var body = Data()
        body.append(
            Data(
                (
                    "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
                        + "\(model)\r\n"
                        + "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"file\"; filename=\"vibewhisper-connection-test.wav\"\r\n"
                        + "Content-Type: audio/wav\r\n\r\n"
                ).utf8
            )
        )
        body.append(waveData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private static func syntheticSilenceWave() -> Data {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = Int(sampleRate / 10)
        let audioData = Data(repeating: 0, count: sampleCount * 2)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var wave = Data("RIFF".utf8)
        wave.appendLittleEndian(UInt32(36 + audioData.count))
        wave.append(Data("WAVEfmt ".utf8))
        wave.appendLittleEndian(UInt32(16))
        wave.appendLittleEndian(UInt16(1))
        wave.appendLittleEndian(channels)
        wave.appendLittleEndian(sampleRate)
        wave.appendLittleEndian(byteRate)
        wave.appendLittleEndian(blockAlign)
        wave.appendLittleEndian(bitsPerSample)
        wave.append(Data("data".utf8))
        wave.appendLittleEndian(UInt32(audioData.count))
        wave.append(audioData)
        return wave
    }

    private static func providerMessage(
        from data: Data,
        apiKey: String
    ) -> String? {
        guard
            data.count <= 64 * 1024,
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return nil
        }
        let rawMessage: String?
        if
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            rawMessage = message
        } else {
            rawMessage = object["message"] as? String
        }
        guard let rawMessage else {
            return nil
        }

        var sanitized = rawMessage.replacingOccurrences(
            of: apiKey,
            with: "[REDACTED]"
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)\bbearer\s+[^\s"']+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)\b(?:sk|token|key)-[A-Za-z0-9._-]{8,}\b"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
        sanitized = sanitized
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            return nil
        }
        return String(sanitized.prefix(400))
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
