#!/usr/bin/env swift

import CryptoKit
import Foundation

enum VerificationError: Error, LocalizedError {
    case usage
    case invalidInput(String)
    case noMatchingUpdate
    case signatureRejected

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: verify_sparkle_appcast.swift --appcast PATH --archive PATH --manifest PATH --public-key BASE64"
        case .invalidInput(let detail):
            detail
        case .noMatchingUpdate:
            "The appcast has no update matching the release manifest."
        case .signatureRejected:
            "The appcast archive signature does not match the packaged public key."
        }
    }
}

struct Manifest: Decodable {
    struct Release: Decodable {
        let version: String
        let build: String
    }

    struct Artifact: Decodable {
        let fileName: String
        let kind: String
        let byteCount: Int
        let sha256: String
        let downloadURL: String
    }

    let release: Release
    let artifacts: [Artifact]
}

struct Arguments {
    let appcast: URL
    let archive: URL
    let manifest: URL
    let publicKey: String

    init(_ rawArguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 1
        while index < rawArguments.count {
            let key = rawArguments[index]
            guard
                key.hasPrefix("--"),
                index + 1 < rawArguments.count
            else {
                throw VerificationError.usage
            }
            values[key] = rawArguments[index + 1]
            index += 2
        }

        guard
            let appcast = values["--appcast"],
            let archive = values["--archive"],
            let manifest = values["--manifest"],
            let publicKey = values["--public-key"]
        else {
            throw VerificationError.usage
        }

        self.appcast = URL(fileURLWithPath: appcast)
        self.archive = URL(fileURLWithPath: archive)
        self.manifest = URL(fileURLWithPath: manifest)
        self.publicKey = publicKey
    }
}

func requireRegularFile(_ url: URL) throws {
    let values = try url.resourceValues(
        forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
    )
    guard
        values.isRegularFile == true,
        values.isSymbolicLink != true
    else {
        throw VerificationError.invalidInput(
            "Expected a regular, non-symlink file: \(url.path)"
        )
    }
}

func attribute(
    named expectedName: String,
    in element: XMLElement
) -> String? {
    element.attributes?
        .first(where: { attribute in
            attribute.name == expectedName
                || attribute.localName == expectedName
                || attribute.name?.hasSuffix(":\(expectedName)") == true
        })?
        .stringValue
}

func childText(
    localName: String,
    in element: XMLElement
) -> String? {
    element.children?
        .first(where: { child in
            child.kind == .element
                && (
                    child.localName == localName
                        || child.name == localName
                        || child.name?.hasSuffix(":\(localName)") == true
                )
        })?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

do {
    let arguments = try Arguments(CommandLine.arguments)
    try requireRegularFile(arguments.appcast)
    try requireRegularFile(arguments.archive)
    try requireRegularFile(arguments.manifest)

    let manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: arguments.manifest)
    )
    guard
        let zipArtifact = manifest.artifacts.first(where: { $0.kind == "zip" })
    else {
        throw VerificationError.invalidInput(
            "Release manifest has no ZIP artifact."
        )
    }

    let archiveData = try Data(
        contentsOf: arguments.archive,
        options: [.mappedIfSafe]
    )
    guard arguments.archive.lastPathComponent == zipArtifact.fileName else {
        throw VerificationError.invalidInput(
            "Archive filename does not match the release manifest."
        )
    }
    guard archiveData.count == zipArtifact.byteCount else {
        throw VerificationError.invalidInput(
            "Archive byte count does not match the release manifest."
        )
    }
    guard sha256Hex(archiveData) == zipArtifact.sha256 else {
        throw VerificationError.invalidInput(
            "Archive SHA-256 does not match the release manifest."
        )
    }

    guard
        let publicKeyData = Data(base64Encoded: arguments.publicKey),
        publicKeyData.count == 32
    else {
        throw VerificationError.invalidInput(
            "Sparkle public key must be a 32-byte base64 Ed25519 key."
        )
    }
    let publicKey = try Curve25519.Signing.PublicKey(
        rawRepresentation: publicKeyData
    )

    let document = try XMLDocument(
        data: Data(contentsOf: arguments.appcast),
        options: [.nodePreserveAll]
    )
    let itemNodes = try document.nodes(
        forXPath: "//*[local-name()='item']"
    )

    var matchingSignature: Data?
    for case let item as XMLElement in itemNodes {
        guard
            childText(localName: "version", in: item)
                == manifest.release.build,
            let enclosure = item.children?
                .compactMap({ $0 as? XMLElement })
                .first(where: {
                    $0.localName == "enclosure"
                        || $0.name == "enclosure"
                        || $0.name?.hasSuffix(":enclosure") == true
                }),
            attribute(named: "url", in: enclosure)
                == zipArtifact.downloadURL,
            attribute(named: "length", in: enclosure)
                == String(zipArtifact.byteCount),
            let encodedSignature = attribute(
                named: "edSignature",
                in: enclosure
            ),
            let signature = Data(base64Encoded: encodedSignature),
            signature.count == 64
        else {
            continue
        }

        matchingSignature = signature
        break
    }

    guard let matchingSignature else {
        throw VerificationError.noMatchingUpdate
    }
    guard publicKey.isValidSignature(
        matchingSignature,
        for: archiveData
    ) else {
        throw VerificationError.signatureRejected
    }

    print(
        "Sparkle appcast signature verified for "
            + "\(zipArtifact.fileName) (build \(manifest.release.build))."
    )
} catch {
    FileHandle.standardError.write(
        Data("\(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
