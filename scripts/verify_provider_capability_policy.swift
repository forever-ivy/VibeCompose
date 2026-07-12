#!/usr/bin/env swift

import CryptoKit
import Foundation

private struct Payload: Codable {
    let schemaVersion: Int
    let revision: Int
    let incidentID: String
    let issuedAt: String
    let expiresAt: String
    let minimumBuild: Int?
    let maximumBuild: Int?
    let disabledCapabilities: [String]
}

private struct Envelope: Codable {
    let payload: String
    let signature: String
}

private enum VerificationError: Error, LocalizedError {
    case usage
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: verify_provider_capability_policy.swift --policy FILE --public-key BASE64 [--build NUMBER]"
        case .invalid(let detail):
            return detail
        }
    }
}

private func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
}

do {
    var policyURL: URL?
    var publicKeyData: Data?
    var build: Int?
    var arguments = Array(CommandLine.arguments.dropFirst())

    while !arguments.isEmpty {
        let option = arguments.removeFirst()
        switch option {
        case "--policy":
            guard !arguments.isEmpty else { throw VerificationError.usage }
            policyURL = URL(fileURLWithPath: arguments.removeFirst())
        case "--public-key":
            guard !arguments.isEmpty else { throw VerificationError.usage }
            publicKeyData = Data(base64Encoded: arguments.removeFirst())
        case "--build":
            guard !arguments.isEmpty else { throw VerificationError.usage }
            build = Int(arguments.removeFirst())
        default:
            throw VerificationError.usage
        }
    }

    guard
        let policyURL,
        let publicKeyData,
        publicKeyData.count == 32
    else {
        throw VerificationError.usage
    }
    let values = try policyURL.resourceValues(forKeys: [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
    ])
    guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        (values.fileSize ?? Int.max) <= 64 * 1024
    else {
        throw VerificationError.invalid(
            "Policy must be a regular non-symlink file no larger than 64 KB."
        )
    }

    let envelopeData = try Data(contentsOf: policyURL)
    let envelope = try JSONDecoder().decode(Envelope.self, from: envelopeData)
    guard
        let payloadData = Data(base64Encoded: envelope.payload),
        let signatureData = Data(base64Encoded: envelope.signature)
    else {
        throw VerificationError.invalid("Policy envelope contains invalid base64.")
    }
    let publicKey = try Curve25519.Signing.PublicKey(
        rawRepresentation: publicKeyData
    )
    guard publicKey.isValidSignature(signatureData, for: payloadData) else {
        throw VerificationError.invalid("Policy signature verification failed.")
    }

    let payload = try JSONDecoder().decode(Payload.self, from: payloadData)
    guard payload.schemaVersion == 1, payload.revision > 0 else {
        throw VerificationError.invalid(
            "Policy schema version or revision is invalid."
        )
    }
    let supportedCapabilities = Set([
        "managedTranscription",
        "chatGPTTextPolish",
    ])
    guard
        Set(payload.disabledCapabilities).count
            == payload.disabledCapabilities.count,
        payload.disabledCapabilities.allSatisfy(
            supportedCapabilities.contains
        )
    else {
        throw VerificationError.invalid(
            "Policy contains duplicate or unsupported capabilities."
        )
    }
    guard
        let issuedAt = parseDate(payload.issuedAt),
        let expiresAt = parseDate(payload.expiresAt),
        issuedAt <= Date().addingTimeInterval(5 * 60),
        expiresAt > Date(),
        expiresAt > issuedAt,
        expiresAt.timeIntervalSince(issuedAt) <= 31 * 24 * 60 * 60
    else {
        throw VerificationError.invalid(
            "Policy timestamps are invalid, expired, or exceed 31 days."
        )
    }
    if let build {
        if let minimumBuild = payload.minimumBuild, build < minimumBuild {
            throw VerificationError.invalid(
                "Policy does not cover release build \(build)."
            )
        }
        if let maximumBuild = payload.maximumBuild, build > maximumBuild {
            throw VerificationError.invalid(
                "Policy does not cover release build \(build)."
            )
        }
    }

    print("Provider capability policy verified.")
    print("Revision: \(payload.revision)")
    print("Incident: \(payload.incidentID)")
    print(
        "Disabled: \(payload.disabledCapabilities.isEmpty ? "none" : payload.disabledCapabilities.joined(separator: ", "))"
    )
    print("Expires: \(payload.expiresAt)")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
