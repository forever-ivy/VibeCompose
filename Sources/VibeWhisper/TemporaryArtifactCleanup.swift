import Foundation

struct TemporaryArtifactCleanupReport: Sendable, Equatable {
    let removedFileNames: [String]
    let failedFileNames: [String]
}

struct TemporaryArtifactCleanupService {
    let fileManager: FileManager
    let temporaryDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.temporaryDirectoryURL = temporaryDirectoryURL
            ?? fileManager.temporaryDirectory
    }

    func cleanupOrphans() -> TemporaryArtifactCleanupReport {
        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: temporaryDirectoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isDirectoryKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return TemporaryArtifactCleanupReport(
                removedFileNames: [],
                failedFileNames: [temporaryDirectoryURL.lastPathComponent]
            )
        }

        var removed: [String] = []
        var failed: [String] = []
        for candidate in candidates where isOwnedTemporaryArtifact(candidate) {
            do {
                let values = try candidate.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isDirectoryKey,
                    ]
                )
                guard values.isDirectory != true else {
                    continue
                }
                guard values.isRegularFile == true || values.isSymbolicLink == true else {
                    continue
                }
                try fileManager.removeItem(at: candidate)
                removed.append(candidate.lastPathComponent)
            } catch {
                failed.append(candidate.lastPathComponent)
            }
        }

        return TemporaryArtifactCleanupReport(
            removedFileNames: removed.sorted(),
            failedFileNames: failed.sorted()
        )
    }

    private func isOwnedTemporaryArtifact(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if let identifier = identifier(
            in: name,
            prefix: "vibewhisper-",
            suffix: ".wav"
        ) {
            return UUID(uuidString: identifier) != nil
        }
        if let identifier = identifier(
            in: name,
            prefix: "vibewhisper-upload-",
            suffix: ".multipart"
        ) {
            return UUID(uuidString: identifier) != nil
        }
        return false
    }

    private func identifier(
        in fileName: String,
        prefix: String,
        suffix: String
    ) -> String? {
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else {
            return nil
        }
        return String(
            fileName
                .dropFirst(prefix.count)
                .dropLast(suffix.count)
        )
    }
}
