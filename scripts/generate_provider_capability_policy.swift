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

private enum GeneratorError: Error, LocalizedError {
    case usage(String)
    case invalidValue(String)
    case unsafePrivateKey(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail), .invalidValue(let detail),
             .unsafePrivateKey(let detail):
            return detail
        }
    }
}

private let supportedCapabilities = Set([
    "managedTranscription",
    "chatGPTTextPolish",
])

private func usage() -> Never {
    fputs(
        """
        Usage:
          VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE=/secure/key \
          scripts/generate_provider_capability_policy.swift \
            --revision 1 \
            --incident-id OW-INC-2026-001 \
            --expires-at 2026-07-14T12:00:00Z \
            --disable managedTranscription \
            [--disable chatGPTTextPolish] \
            [--minimum-build 1] [--maximum-build 10] \
            [--output dist/provider-capabilities.json]

        Use --enable-all instead of --disable to publish a higher-revision
        signed policy that clears all capability blocks.
        """,
        stderr
    )
    exit(64)
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

private func formatDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func privateKey(from url: URL) throws -> Curve25519.Signing.PrivateKey {
    let values = try url.resourceValues(forKeys: [
        .isRegularFileKey,
        .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw GeneratorError.unsafePrivateKey(
            "Capability private key must be a regular non-symlink file."
        )
    }

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    guard permissions & 0o077 == 0 else {
        throw GeneratorError.unsafePrivateKey(
            "Capability private key must not be readable or writable by group/other users (use chmod 600)."
        )
    }

    let fileData = try Data(contentsOf: url)
    let trimmedText = String(data: fileData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let rawKey: Data
    if let trimmedText, let decoded = Data(base64Encoded: trimmedText) {
        rawKey = decoded
    } else {
        rawKey = fileData
    }
    guard rawKey.count == 32 else {
        throw GeneratorError.unsafePrivateKey(
            "Capability private key must contain a raw or base64-encoded 32-byte Ed25519 private key."
        )
    }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
}

private func parsePositiveInt(_ value: String, name: String) throws -> Int {
    guard let parsed = Int(value), parsed > 0 else {
        throw GeneratorError.invalidValue("\(name) must be a positive integer.")
    }
    return parsed
}

do {
    var revision: Int?
    var incidentID: String?
    var expiresAt: Date?
    var minimumBuild: Int?
    var maximumBuild: Int?
    var disabledCapabilities: [String] = []
    var enableAll = false
    var outputURL = URL(fileURLWithPath: "dist/provider-capabilities.json")

    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let option = arguments.removeFirst()
        switch option {
        case "--revision":
            guard !arguments.isEmpty else { usage() }
            revision = try parsePositiveInt(
                arguments.removeFirst(),
                name: "--revision"
            )
        case "--incident-id":
            guard !arguments.isEmpty else { usage() }
            incidentID = arguments.removeFirst()
        case "--expires-at":
            guard !arguments.isEmpty else { usage() }
            let rawValue = arguments.removeFirst()
            guard let parsed = parseDate(rawValue) else {
                throw GeneratorError.invalidValue(
                    "--expires-at must be an ISO-8601 timestamp."
                )
            }
            expiresAt = parsed
        case "--minimum-build":
            guard !arguments.isEmpty else { usage() }
            minimumBuild = try parsePositiveInt(
                arguments.removeFirst(),
                name: "--minimum-build"
            )
        case "--maximum-build":
            guard !arguments.isEmpty else { usage() }
            maximumBuild = try parsePositiveInt(
                arguments.removeFirst(),
                name: "--maximum-build"
            )
        case "--disable":
            guard !arguments.isEmpty else { usage() }
            let capability = arguments.removeFirst()
            guard supportedCapabilities.contains(capability) else {
                throw GeneratorError.invalidValue(
                    "Unsupported capability: \(capability)"
                )
            }
            disabledCapabilities.append(capability)
        case "--enable-all":
            enableAll = true
        case "--output":
            guard !arguments.isEmpty else { usage() }
            outputURL = URL(fileURLWithPath: arguments.removeFirst())
        case "--help", "-h":
            usage()
        default:
            throw GeneratorError.usage("Unknown option: \(option)")
        }
    }

    guard
        let revision,
        let incidentID,
        let expiresAt
    else {
        usage()
    }
    guard
        !incidentID.isEmpty,
        incidentID.count <= 64,
        incidentID.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        })
    else {
        throw GeneratorError.invalidValue(
            "--incident-id must contain 1–64 letters, numbers, dots, underscores, or hyphens."
        )
    }
    guard disabledCapabilities.isEmpty != !enableAll else {
        throw GeneratorError.invalidValue(
            "Choose one or more --disable values, or use --enable-all by itself."
        )
    }
    guard Set(disabledCapabilities).count == disabledCapabilities.count else {
        throw GeneratorError.invalidValue(
            "Each --disable capability may appear only once."
        )
    }
    if let minimumBuild, let maximumBuild, minimumBuild > maximumBuild {
        throw GeneratorError.invalidValue(
            "--minimum-build cannot exceed --maximum-build."
        )
    }

    let issuedAt = Date()
    guard expiresAt > issuedAt else {
        throw GeneratorError.invalidValue("--expires-at must be in the future.")
    }
    guard expiresAt.timeIntervalSince(issuedAt) <= 31 * 24 * 60 * 60 else {
        throw GeneratorError.invalidValue(
            "Capability policies may be valid for at most 31 days."
        )
    }

    guard
        let privateKeyPath = ProcessInfo.processInfo.environment[
            "VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE"
        ],
        !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw GeneratorError.unsafePrivateKey(
            "VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE is required."
        )
    }
    let signingKey = try privateKey(
        from: URL(fileURLWithPath: privateKeyPath)
    )

    let payload = Payload(
        schemaVersion: 1,
        revision: revision,
        incidentID: incidentID,
        issuedAt: formatDate(issuedAt),
        expiresAt: formatDate(expiresAt),
        minimumBuild: minimumBuild,
        maximumBuild: maximumBuild,
        disabledCapabilities: disabledCapabilities.sorted()
    )
    let payloadEncoder = JSONEncoder()
    payloadEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payloadData = try payloadEncoder.encode(payload)
    let signature = try signingKey.signature(for: payloadData)
    let envelope = Envelope(
        payload: payloadData.base64EncodedString(),
        signature: signature.base64EncodedString()
    )
    let envelopeEncoder = JSONEncoder()
    envelopeEncoder.outputFormatting = [
        .prettyPrinted,
        .sortedKeys,
        .withoutEscapingSlashes,
    ]
    let envelopeData = try envelopeEncoder.encode(envelope)

    let outputDirectory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    try envelopeData.write(to: outputURL, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o644))],
        ofItemAtPath: outputURL.path
    )

    print("Wrote signed provider capability policy: \(outputURL.path)")
    print("Revision: \(revision)")
    print("Incident: \(incidentID)")
    print(
        "Disabled: \(disabledCapabilities.isEmpty ? "none" : disabledCapabilities.sorted().joined(separator: ", "))"
    )
    print(
        "Public key: \(signingKey.publicKey.rawRepresentation.base64EncodedString())"
    )
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
