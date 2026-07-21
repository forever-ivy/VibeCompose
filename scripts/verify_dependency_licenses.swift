#!/usr/bin/env swift

import CryptoKit
import Foundation

struct ResolvedPackages: Decodable {
    let pins: [ResolvedPin]
}

struct ResolvedPin: Decodable {
    struct State: Decodable {
        let revision: String
        let version: String?
    }

    let identity: String
    let location: String
    let state: State
}

struct LicenseManifest: Decodable {
    let schemaVersion: Int
    let dependencies: [LicenseEntry]
}

struct LicenseEntry: Decodable {
    let sourceKind: String?
    let identity: String
    let name: String
    let sourceURL: String
    let revision: String
    let version: String?
    let licenseName: String
    let licenseFile: String
    let licenseSHA256: String
}

enum VerificationError: Error, CustomStringConvertible {
    case usage
    case invalidPath(String)
    case invalidManifest(String)
    case mismatch(String)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage: verify_dependency_licenses.swift \
              --root REPOSITORY_ROOT \
              [--app-resources APP_CONTENTS_RESOURCES]
            """
        case .invalidPath(let message),
             .invalidManifest(let message),
             .mismatch(let message):
            return message
        }
    }
}

func argumentValue(_ name: String, arguments: [String]) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
        throw VerificationError.usage
    }
    return arguments[valueIndex]
}

func regularFileData(
    _ url: URL,
    maximumBytes: Int
) throws -> Data {
    let values = try url.resourceValues(
        forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
    )
    guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let fileSize = values.fileSize,
        fileSize > 0,
        fileSize <= maximumBytes
    else {
        throw VerificationError.invalidPath(
            "Expected a bounded regular file: \(url.path)"
        )
    }
    return try Data(contentsOf: url, options: [.mappedIfSafe])
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

func isContained(_ candidate: URL, in root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/")
        ? root.path
        : root.path + "/"
    return candidate.standardizedFileURL.path.hasPrefix(rootPath)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard
        let rootPath = try argumentValue("--root", arguments: arguments)
    else {
        throw VerificationError.usage
    }
    let appResourcesPath = try argumentValue(
        "--app-resources",
        arguments: arguments
    )
    let recognized = Set(["--root", "--app-resources"])
    var index = 0
    while index < arguments.count {
        guard recognized.contains(arguments[index]) else {
            throw VerificationError.usage
        }
        index += 2
    }

    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        .standardizedFileURL
    let resourceRoot = root
        .appendingPathComponent(
            "Sources/OpenWhisper/Resources",
            isDirectory: true
        )
        .standardizedFileURL
    let manifestURL = resourceRoot
        .appendingPathComponent(
            "Legal/third-party-licenses.json"
        )
        .standardizedFileURL
    let noticesURL = resourceRoot
        .appendingPathComponent(
            "Legal/THIRD_PARTY_NOTICES.md"
        )
        .standardizedFileURL
    let resolvedURL = root
        .appendingPathComponent("Package.resolved")
        .standardizedFileURL

    let manifest = try JSONDecoder().decode(
        LicenseManifest.self,
        from: regularFileData(manifestURL, maximumBytes: 256 * 1024)
    )
    guard manifest.schemaVersion == 1 else {
        throw VerificationError.invalidManifest(
            "Unsupported third-party license manifest schema: "
                + "\(manifest.schemaVersion)"
        )
    }
    let resolved = try JSONDecoder().decode(
        ResolvedPackages.self,
        from: regularFileData(resolvedURL, maximumBytes: 1_048_576)
    )
    let notices = String(
        decoding: try regularFileData(
            noticesURL,
            maximumBytes: 256 * 1024
        ),
        as: UTF8.self
    )

    let manifestIdentities = manifest.dependencies.map(\.identity)
    let packageEntries = manifest.dependencies.filter {
        $0.sourceKind != "vendored"
    }
    let packageIdentities = packageEntries.map(\.identity)
    let resolvedIdentities = resolved.pins.map(\.identity)
    guard Set(manifestIdentities).count == manifestIdentities.count else {
        throw VerificationError.invalidManifest(
            "Third-party license manifest identities must be unique."
        )
    }
    guard Set(resolvedIdentities).count == resolvedIdentities.count else {
        throw VerificationError.invalidManifest(
            "Package.resolved identities must be unique."
        )
    }
    guard Set(packageIdentities) == Set(resolvedIdentities) else {
        let missing = Set(resolvedIdentities)
            .subtracting(packageIdentities)
            .sorted()
        let stale = Set(packageIdentities)
            .subtracting(resolvedIdentities)
            .sorted()
        throw VerificationError.mismatch(
            "Dependency license coverage mismatch. "
                + "Missing: \(missing). Stale: \(stale)."
        )
    }

    let resolvedByIdentity = Dictionary(
        uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0) }
    )
    let appResourceRoot = appResourcesPath.map {
        URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
    }

    for entry in manifest.dependencies {
        let sourceURL = URL(string: entry.sourceURL)
        guard
            entry.identity.range(
                of: #"^[a-z0-9][a-z0-9._-]*$"#,
                options: .regularExpression
            ) != nil,
            !entry.name.isEmpty,
            sourceURL?.scheme == "https",
            sourceURL?.host?.isEmpty == false,
            sourceURL?.user == nil,
            sourceURL?.password == nil,
            sourceURL?.query == nil,
            sourceURL?.fragment == nil,
            entry.revision.range(
                of: #"^[0-9a-f]{40}$"#,
                options: .regularExpression
            ) != nil,
            entry.licenseSHA256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil,
            !entry.licenseName.isEmpty,
            entry.sourceKind == nil
                || entry.sourceKind == "package"
                || entry.sourceKind == "vendored"
        else {
            throw VerificationError.invalidManifest(
                "Invalid dependency license entry: \(entry.identity)"
            )
        }
        if entry.sourceKind != "vendored" {
            guard let pin = resolvedByIdentity[entry.identity] else {
                throw VerificationError.mismatch(
                    "Missing resolved dependency: \(entry.identity)"
                )
            }
            guard
                entry.sourceURL == pin.location,
                entry.revision == pin.state.revision,
                entry.version == pin.state.version
            else {
                throw VerificationError.mismatch(
                    "Pinned dependency metadata does not match for "
                        + "\(entry.identity)."
                )
            }
        }
        guard
            entry.licenseFile.hasPrefix(
                "Legal/ThirdPartyLicenses/"
            )
        else {
            throw VerificationError.invalidManifest(
                "Unsafe license path for \(entry.identity)."
            )
        }

        let sourceLicenseURL = resourceRoot
            .appendingPathComponent(entry.licenseFile)
            .standardizedFileURL
        guard isContained(sourceLicenseURL, in: resourceRoot) else {
            throw VerificationError.invalidPath(
                "License path escapes the resource root for "
                    + "\(entry.identity)."
            )
        }
        let sourceData = try regularFileData(
            sourceLicenseURL,
            maximumBytes: 1_048_576
        )
        guard sha256(sourceData) == entry.licenseSHA256 else {
            throw VerificationError.mismatch(
                "Vendored license SHA-256 mismatch for "
                    + "\(entry.identity)."
            )
        }
        guard
            notices.contains(entry.name),
            notices.contains(entry.revision),
            notices.contains(
                sourceLicenseURL.lastPathComponent
            )
        else {
            throw VerificationError.mismatch(
                "THIRD_PARTY_NOTICES.md does not describe "
                    + "\(entry.identity)."
            )
        }

        if let appResourceRoot {
            let packagedLicenseURL = appResourceRoot
                .appendingPathComponent(entry.licenseFile)
                .standardizedFileURL
            guard isContained(packagedLicenseURL, in: appResourceRoot) else {
                throw VerificationError.invalidPath(
                    "Packaged license path escapes App resources for "
                        + "\(entry.identity)."
                )
            }
            let packagedData = try regularFileData(
                packagedLicenseURL,
                maximumBytes: 1_048_576
            )
            guard packagedData == sourceData else {
                throw VerificationError.mismatch(
                    "Packaged license differs from source for "
                        + "\(entry.identity)."
                )
            }
        }
    }

    if let appResourceRoot {
        for relativePath in [
            "Legal/third-party-licenses.json",
            "Legal/THIRD_PARTY_NOTICES.md",
        ] {
            let sourceURL = resourceRoot
                .appendingPathComponent(relativePath)
            let packagedURL = appResourceRoot
                .appendingPathComponent(relativePath)
            guard
                try regularFileData(
                    sourceURL,
                    maximumBytes: 256 * 1024
                )
                    == regularFileData(
                        packagedURL,
                        maximumBytes: 256 * 1024
                    )
            else {
                throw VerificationError.mismatch(
                    "Packaged legal resource differs from source: "
                        + relativePath
                )
            }
        }
    }

    print(
        "Dependency license verification passed for "
            + "\(packageEntries.count) pinned packages and "
            + "\(manifest.dependencies.count - packageEntries.count) "
            + "vendored sources."
    )
} catch {
    fputs("Dependency license verification failed: \(error)\n", stderr)
    exit(1)
}
