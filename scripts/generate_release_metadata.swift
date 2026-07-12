#!/usr/bin/env swift

import CryptoKit
import Foundation

private struct ReleaseManifest: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let product: Product
    let release: Release
    let artifacts: [Artifact]

    struct Product: Codable {
        let name: String
        let bundleIdentifier: String
        let repository: String
        let minimumMacOS: String
    }

    struct Release: Codable {
        let version: String
        let build: String
        let tag: String
        let architecture: String
    }

    struct Artifact: Codable {
        let kind: String
        let fileName: String
        let downloadURL: String
        let byteCount: Int
        let sha256: String
    }
}

private enum GeneratorError: LocalizedError {
    case missingArgument(String)
    case invalidArgument(String)
    case invalidArtifact(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument --\(name)."
        case .invalidArgument(let message):
            return message
        case .invalidArtifact(let path):
            return "Release artifact is missing, symbolic, or not a regular file: \(path)"
        }
    }
}

private func arguments() throws -> [String: String] {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard raw.count.isMultiple(of: 2) else {
        throw GeneratorError.invalidArgument(
            "Arguments must be provided as --name value pairs."
        )
    }

    var parsed: [String: String] = [:]
    var index = 0
    while index < raw.count {
        let key = raw[index]
        guard key.hasPrefix("--"), key.count > 2 else {
            throw GeneratorError.invalidArgument("Invalid argument name: \(key)")
        }
        let name = String(key.dropFirst(2))
        guard parsed[name] == nil else {
            throw GeneratorError.invalidArgument("Duplicate argument: --\(name)")
        }
        parsed[name] = raw[index + 1]
        index += 2
    }
    return parsed
}

private func required(
    _ name: String,
    from values: [String: String]
) throws -> String {
    guard let value = values[name], !value.isEmpty else {
        throw GeneratorError.missingArgument(name)
    }
    return value
}

private func validatedArtifact(
    at url: URL
) throws -> (byteCount: Int, sha256: String) {
    let values = try url.resourceValues(
        forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
    )
    guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let byteCount = values.fileSize,
        byteCount > 0
    else {
        throw GeneratorError.invalidArtifact(url.path)
    }

    let handle = try FileHandle(forReadingFrom: url)
    defer {
        try? handle.close()
    }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    let digest = hasher.finalize().map {
        String(format: "%02x", $0)
    }
    .joined()
    return (byteCount, digest)
}

private func validatedDownloadURL(_ value: String) throws -> String {
    guard
        let components = URLComponents(string: value),
        components.scheme?.lowercased() == "https",
        components.host != nil,
        components.user == nil,
        components.password == nil,
        components.fragment == nil,
        components.url?.absoluteString == value
    else {
        throw GeneratorError.invalidArgument(
            "Artifact download URLs must be canonical HTTPS URLs without credentials or fragments."
        )
    }
    return value
}

do {
    let values = try arguments()
    let outputURL = URL(
        fileURLWithPath: try required("output", from: values)
    )
    let appName = try required("app-name", from: values)
    let bundleIdentifier = try required("bundle-id", from: values)
    let repository = try required("repository", from: values)
    let minimumMacOS = try required("minimum-macos", from: values)
    let version = try required("version", from: values)
    let build = try required("build", from: values)
    let architecture = try required("architecture", from: values)
    let zipURL = URL(
        fileURLWithPath: try required("zip", from: values)
    )
    let dmgURL = URL(
        fileURLWithPath: try required("dmg", from: values)
    )
    let zipDownloadURL = try validatedDownloadURL(
        try required("zip-url", from: values)
    )
    let dmgDownloadURL = try validatedDownloadURL(
        try required("dmg-url", from: values)
    )
    let generatedAt: Date
    if let value = values["generated-at"] {
        guard let parsed = ISO8601DateFormatter().date(from: value) else {
            throw GeneratorError.invalidArgument(
                "--generated-at must be an ISO-8601 timestamp."
            )
        }
        generatedAt = parsed
    } else {
        generatedAt = Date()
    }

    let zip = try validatedArtifact(at: zipURL)
    let dmg = try validatedArtifact(at: dmgURL)
    let manifest = ReleaseManifest(
        schemaVersion: 1,
        generatedAt: generatedAt,
        product: .init(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            repository: repository,
            minimumMacOS: minimumMacOS
        ),
        release: .init(
            version: version,
            build: build,
            tag: "v\(version)",
            architecture: architecture
        ),
        artifacts: [
            .init(
                kind: "zip",
                fileName: zipURL.lastPathComponent,
                downloadURL: zipDownloadURL,
                byteCount: zip.byteCount,
                sha256: zip.sha256
            ),
            .init(
                kind: "dmg",
                fileName: dmgURL.lastPathComponent,
                downloadURL: dmgDownloadURL,
                byteCount: dmg.byteCount,
                sha256: dmg.sha256
            ),
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(manifest)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let temporaryURL = outputURL
        .deletingLastPathComponent()
        .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: temporaryURL)
    }
    try data.write(to: temporaryURL, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o600))],
        ofItemAtPath: temporaryURL.path
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
        let existing = try outputURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard existing.isDirectory != true || existing.isSymbolicLink == true else {
            throw GeneratorError.invalidArgument(
                "Refusing to replace a directory with release metadata."
            )
        }
        try FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    print("Created \(outputURL.path)")
} catch {
    FileHandle.standardError.write(
        Data("error: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
