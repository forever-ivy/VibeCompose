import CryptoKit
import Foundation

struct ThirdPartyLicenseManifest: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let dependencies: [ThirdPartyLicenseEntry]
}

struct ThirdPartyLicenseEntry:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let identity: String
    let name: String
    let sourceURL: String
    let revision: String
    let version: String?
    let licenseName: String
    let licenseFile: String
    let licenseSHA256: String

    var id: String { identity }

    var pinnedDescription: String {
        if let version {
            return L10n.format("Version %@ · revision %@", version, shortRevision)
        }
        return L10n.format("Revision %@", shortRevision)
    }

    private var shortRevision: String {
        String(revision.prefix(12))
    }
}

struct ThirdPartyLicenseDocument: Equatable, Identifiable, Sendable {
    let entry: ThirdPartyLicenseEntry
    let licenseText: String

    var id: String { entry.identity }
}

enum ThirdPartyLicenseCatalogError: Error, Equatable, LocalizedError {
    case missingResourceRoot
    case invalidManifest
    case unsupportedSchema(Int)
    case duplicateIdentity(String)
    case invalidEntry(String)
    case unsafeLicensePath(String)
    case missingLicense(String)
    case unreadableLicense(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingResourceRoot:
            return L10n.text(
                "OpenWhisper could not find its bundled third-party license resources."
            )
        case .invalidManifest:
            return L10n.text(
                "OpenWhisper could not read its third-party license manifest."
            )
        case .unsupportedSchema(let version):
            return L10n.format(
                "OpenWhisper cannot read third-party license manifest schema %ld.",
                version
            )
        case .duplicateIdentity(let identity):
            return L10n.format(
                "The third-party license manifest contains duplicate dependency %@.",
                identity
            )
        case .invalidEntry(let identity):
            return L10n.format(
                "The third-party license entry for %@ is incomplete.",
                identity
            )
        case .unsafeLicensePath(let identity):
            return L10n.format(
                "The third-party license path for %@ is unsafe.",
                identity
            )
        case .missingLicense(let identity):
            return L10n.format(
                "The bundled license for %@ is missing.",
                identity
            )
        case .unreadableLicense(let identity):
            return L10n.format(
                "The bundled license for %@ could not be read.",
                identity
            )
        case .checksumMismatch(let identity):
            return L10n.format(
                "The bundled license for %@ failed its integrity check.",
                identity
            )
        }
    }
}

enum ThirdPartyLicenseCatalog {
    static let manifestRelativePath =
        "Legal/third-party-licenses.json"
    static let noticesRelativePath =
        "Legal/THIRD_PARTY_NOTICES.md"
    private static let maximumLicenseBytes = 1_048_576

    static func load(bundle: Bundle = .main) throws
        -> [ThirdPartyLicenseDocument]
    {
        guard let resourceURL = bundle.resourceURL else {
            throw ThirdPartyLicenseCatalogError.missingResourceRoot
        }
        return try load(resourceRootURL: resourceURL)
    }

    static func load(resourceRootURL: URL) throws
        -> [ThirdPartyLicenseDocument]
    {
        let root = resourceRootURL.standardizedFileURL
        let manifestURL = root
            .appendingPathComponent(manifestRelativePath)
            .standardizedFileURL
        guard contains(manifestURL, within: root) else {
            throw ThirdPartyLicenseCatalogError.invalidManifest
        }

        let manifestData: Data
        do {
            manifestData = try secureRegularFileData(
                at: manifestURL,
                maximumBytes: 256 * 1024
            )
        } catch {
            throw ThirdPartyLicenseCatalogError.invalidManifest
        }

        let manifest: ThirdPartyLicenseManifest
        do {
            manifest = try JSONDecoder().decode(
                ThirdPartyLicenseManifest.self,
                from: manifestData
            )
        } catch {
            throw ThirdPartyLicenseCatalogError.invalidManifest
        }

        guard manifest.schemaVersion == 1 else {
            throw ThirdPartyLicenseCatalogError.unsupportedSchema(
                manifest.schemaVersion
            )
        }
        guard !manifest.dependencies.isEmpty else {
            throw ThirdPartyLicenseCatalogError.invalidManifest
        }

        var identities = Set<String>()
        return try manifest.dependencies.map { entry in
            guard identities.insert(entry.identity).inserted else {
                throw ThirdPartyLicenseCatalogError.duplicateIdentity(
                    entry.identity
                )
            }
            try validate(entry)

            let licenseURL = root
                .appendingPathComponent(entry.licenseFile)
                .standardizedFileURL
            guard
                entry.licenseFile.hasPrefix(
                    "Legal/ThirdPartyLicenses/"
                ),
                contains(licenseURL, within: root)
            else {
                throw ThirdPartyLicenseCatalogError.unsafeLicensePath(
                    entry.identity
                )
            }

            let data: Data
            do {
                data = try secureRegularFileData(
                    at: licenseURL,
                    maximumBytes: maximumLicenseBytes
                )
            } catch CocoaError.fileReadNoSuchFile {
                throw ThirdPartyLicenseCatalogError.missingLicense(
                    entry.identity
                )
            } catch {
                throw ThirdPartyLicenseCatalogError.unreadableLicense(
                    entry.identity
                )
            }

            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard digest == entry.licenseSHA256 else {
                throw ThirdPartyLicenseCatalogError.checksumMismatch(
                    entry.identity
                )
            }
            guard
                let licenseText = String(data: data, encoding: .utf8),
                !licenseText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            else {
                throw ThirdPartyLicenseCatalogError.unreadableLicense(
                    entry.identity
                )
            }

            return ThirdPartyLicenseDocument(
                entry: entry,
                licenseText: licenseText
            )
        }
    }

    private static func validate(_ entry: ThirdPartyLicenseEntry) throws {
        let sourceURL = URL(string: entry.sourceURL)
        guard
            !entry.identity.isEmpty,
            entry.identity.range(
                of: #"^[a-z0-9][a-z0-9._-]*$"#,
                options: .regularExpression
            ) != nil,
            !entry.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
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
            !entry.licenseName.isEmpty,
            entry.licenseSHA256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil
        else {
            throw ThirdPartyLicenseCatalogError.invalidEntry(
                entry.identity
            )
        }
    }

    private static func secureRegularFileData(
        at url: URL,
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
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func contains(_ candidate: URL, within root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/")
            ? root.path
            : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }
}
