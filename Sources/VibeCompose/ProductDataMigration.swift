import Foundation

enum ProductDataMigrationError: LocalizedError, Equatable {
    case unsafeContainer(String)
    case symbolicLink(String)
    case unsupportedItem(String)

    var errorDescription: String? {
        switch self {
        case .unsafeContainer(let path):
            return "VibeCompose refused to migrate an unsafe data path: \(path)"
        case .symbolicLink(let path):
            return "VibeCompose refused to migrate data through a symbolic link: \(path)"
        case .unsupportedItem(let path):
            return "VibeCompose could not safely migrate an unsupported item: \(path)"
        }
    }
}

struct ProductDataMigration {
    static let markerFileName = ".identity-migration-v1.json"

    let fileManager: FileManager
    let currentDirectoryURL: URL
    let legacyDirectoryURL: URL
    let now: () -> Date

    init(
        fileManager: FileManager = .default,
        currentDirectoryURL: URL,
        legacyDirectoryURL: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.currentDirectoryURL = currentDirectoryURL
        self.legacyDirectoryURL = legacyDirectoryURL
        self.now = now
    }

    var markerURL: URL {
        currentDirectoryURL.appendingPathComponent(Self.markerFileName)
    }

    func migrateIfNeeded() throws {
        try validateContainerPair()

        switch itemKind(at: markerURL) {
        case .regularFile:
            return
        case .symbolicLink:
            throw ProductDataMigrationError.symbolicLink(markerURL.path)
        case .directory, .other:
            throw ProductDataMigrationError.unsupportedItem(markerURL.path)
        case .missing:
            break
        }

        switch itemKind(at: legacyDirectoryURL) {
        case .missing:
            return
        case .symbolicLink:
            // Do not follow or mark a rejected source. If the user replaces it
            // with a real rollback container, a later launch can still migrate.
            return
        case .directory:
            break
        case .regularFile, .other:
            return
        }

        switch itemKind(at: currentDirectoryURL) {
        case .missing:
            try createSecureDirectory(currentDirectoryURL)
        case .directory:
            try setDirectoryPermissions(currentDirectoryURL)
        case .symbolicLink:
            throw ProductDataMigrationError.symbolicLink(
                currentDirectoryURL.path
            )
        case .regularFile, .other:
            throw ProductDataMigrationError.unsupportedItem(
                currentDirectoryURL.path
            )
        }

        let entries = try fileManager.contentsOfDirectory(
            at: legacyDirectoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for sourceURL in entries {
            let destinationURL = currentDirectoryURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: false
            )
            if sourceURL.lastPathComponent == "config.json" {
                try migrateConfig(
                    from: sourceURL,
                    to: destinationURL
                )
            } else {
                try migrateItem(
                    from: sourceURL,
                    to: destinationURL
                )
            }
        }

        try writeMarker()
    }

    private func migrateConfig(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        guard itemKind(at: sourceURL) == .regularFile else {
            return
        }
        let legacyData = try readRegularFile(sourceURL)
        let legacyConfig = try JSONDecoder().decode(
            AppConfig.self,
            from: legacyData
        )

        let migratedConfig: AppConfig
        switch itemKind(at: destinationURL) {
        case .missing:
            migratedConfig = legacyConfig
        case .regularFile:
            let currentData = try readRegularFile(destinationURL)
            let currentConfig = try JSONDecoder().decode(
                AppConfig.self,
                from: currentData
            )
            migratedConfig = AppConfig.merging(
                base: AppConfig(),
                local: currentConfig,
                remote: legacyConfig
            )
        case .symbolicLink:
            throw ProductDataMigrationError.symbolicLink(
                destinationURL.path
            )
        case .directory, .other:
            throw ProductDataMigrationError.unsupportedItem(
                destinationURL.path
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeSecurely(
            try encoder.encode(migratedConfig),
            to: destinationURL
        )
    }

    private func migrateItem(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        switch itemKind(at: sourceURL) {
        case .missing, .symbolicLink:
            return
        case .directory:
            switch itemKind(at: destinationURL) {
            case .missing:
                try createSecureDirectory(destinationURL)
            case .directory:
                try setDirectoryPermissions(destinationURL)
            case .symbolicLink, .regularFile, .other:
                // Current data wins direct collisions, including an item with
                // a different type. Never traverse a destination symlink.
                return
            }
            let children = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                try migrateItem(
                    from: child,
                    to: destinationURL.appendingPathComponent(
                        child.lastPathComponent,
                        isDirectory: false
                    )
                )
            }
        case .regularFile:
            switch itemKind(at: destinationURL) {
            case .missing:
                try writeSecurely(
                    try readRegularFile(sourceURL),
                    to: destinationURL
                )
            case .regularFile
                where sourceURL.pathExtension.lowercased() == "jsonl":
                try mergeJSONL(
                    legacyURL: sourceURL,
                    currentURL: destinationURL
                )
            case .regularFile, .directory, .symbolicLink, .other:
                // Preserve the current file on direct collisions.
                return
            }
        case .other:
            return
        }
    }

    private func mergeJSONL(
        legacyURL: URL,
        currentURL: URL
    ) throws {
        let legacyLines = jsonLines(try readRegularFile(legacyURL))
        let currentLines = jsonLines(try readRegularFile(currentURL))
        var seen = Set<Data>()
        var mergedLines: [Data] = []
        for line in legacyLines + currentLines where seen.insert(line).inserted {
            mergedLines.append(line)
        }

        var output = Data()
        for line in mergedLines {
            output.append(line)
            output.append(0x0A)
        }
        try writeSecurely(output, to: currentURL)
    }

    private func jsonLines(_ data: Data) -> [Data] {
        Array(data).split(
            separator: UInt8(0x0A),
            omittingEmptySubsequences: true
        ).map { Data($0) }
    }

    private func readRegularFile(_ url: URL) throws -> Data {
        guard itemKind(at: url) == .regularFile else {
            if itemKind(at: url) == .symbolicLink {
                throw ProductDataMigrationError.symbolicLink(url.path)
            }
            throw ProductDataMigrationError.unsupportedItem(url.path)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func writeSecurely(_ data: Data, to url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        switch itemKind(at: parentURL) {
        case .missing:
            try createSecureDirectory(parentURL)
        case .directory:
            break
        case .symbolicLink:
            throw ProductDataMigrationError.symbolicLink(parentURL.path)
        case .regularFile, .other:
            throw ProductDataMigrationError.unsupportedItem(parentURL.path)
        }
        if itemKind(at: url) == .symbolicLink {
            throw ProductDataMigrationError.symbolicLink(url.path)
        }
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private func createSecureDirectory(_ url: URL) throws {
        if itemKind(at: url) == .symbolicLink {
            throw ProductDataMigrationError.symbolicLink(url.path)
        }
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try setDirectoryPermissions(url)
    }

    private func setDirectoryPermissions(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }

    private func writeMarker() throws {
        struct Marker: Codable {
            let schemaVersion: Int
            let completedAt: Date
            let sourceContainer: String
            let rollbackCopyRetained: Bool
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let marker = Marker(
            schemaVersion: 1,
            completedAt: now(),
            sourceContainer: LegacyProductIdentity.name,
            rollbackCopyRetained: true
        )
        try writeSecurely(try encoder.encode(marker), to: markerURL)
    }

    private func validateContainerPair() throws {
        let current = currentDirectoryURL.standardizedFileURL
        let legacy = legacyDirectoryURL.standardizedFileURL
        let currentParent = current.deletingLastPathComponent()
        let legacyParent = legacy.deletingLastPathComponent()
        guard
            current.lastPathComponent == ProductIdentity.name,
            legacy.lastPathComponent == LegacyProductIdentity.name,
            currentParent == legacyParent,
            currentParent.lastPathComponent == "Application Support",
            current.path != "/",
            legacy.path != "/"
        else {
            throw ProductDataMigrationError.unsafeContainer(
                "\(legacy.path) -> \(current.path)"
            )
        }
    }

    private enum ItemKind {
        case missing
        case regularFile
        case directory
        case symbolicLink
        case other
    }

    private func itemKind(at url: URL) -> ItemKind {
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: url.path
        )) != nil {
            return .symbolicLink
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) else {
            return .missing
        }
        if isDirectory.boolValue {
            return .directory
        }
        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey]
        )
        return values?.isRegularFile == true ? .regularFile : .other
    }
}
