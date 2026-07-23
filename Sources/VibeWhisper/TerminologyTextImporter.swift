import Foundation

struct TerminologyTextImportResult: Sendable, Equatable {
    let entries: [TerminologyEntry]
    let source: String
    let importedAt: String
}

enum TerminologyTextImportError: LocalizedError, Equatable {
    case unreadableText(String)
    case noValidEntries(String)
    case fileTooLarge(String)
    case tooManyEntries(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText(let source):
            return L10n.format("Could not read terminology dictionary text: %@", source)
        case .noValidEntries(let source):
            return L10n.format("No valid terminology entries found in %@.", source)
        case .fileTooLarge(let source):
            return L10n.format("Terminology dictionary %@ is larger than 2 MB.", source)
        case .tooManyEntries(let source):
            return L10n.format("Terminology dictionary %@ contains more than 10,000 entries.", source)
        }
    }
}

struct TerminologyTextImporter {
    private static let maximumBytes = 2_000_000
    private static let maximumEntries = 10_000
    private static let maximumFieldCharacters = 240

    func importEntries(from fileURL: URL) throws -> TerminologyTextImportResult {
        let sourceName = fileURL.lastPathComponent
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TerminologyTextImportError.unreadableText(sourceName)
        }
        guard (values.fileSize ?? 0) <= Self.maximumBytes else {
            throw TerminologyTextImportError.fileTooLarge(sourceName)
        }

        return try importEntries(
            from: Data(contentsOf: fileURL, options: [.mappedIfSafe]),
            sourceName: sourceName
        )
    }

    func importEntries(from data: Data, sourceName: String) throws -> TerminologyTextImportResult {
        guard data.count <= Self.maximumBytes else {
            throw TerminologyTextImportError.fileTooLarge(sourceName)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TerminologyTextImportError.unreadableText(sourceName)
        }

        let importedAt = ISO8601DateFormatter().string(from: Date())
        let entries = extractEntries(
            from: text,
            sourceName: sourceName,
            importedAt: importedAt
        )
        guard !entries.isEmpty else {
            throw TerminologyTextImportError.noValidEntries(sourceName)
        }
        guard entries.count <= Self.maximumEntries else {
            throw TerminologyTextImportError.tooManyEntries(sourceName)
        }

        return TerminologyTextImportResult(
            entries: entries,
            source: sourceName,
            importedAt: importedAt
        )
    }

    private func extractEntries(
        from text: String,
        sourceName: String,
        importedAt: String
    ) -> [TerminologyEntry] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
        guard let firstLine = lines.first else {
            return []
        }

        let header = parseCSVFields(firstLine).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if header.contains("original") || header.contains("type") {
            return extractStructuredEntries(
                from: Array(lines.dropFirst()),
                header: header,
                sourceName: sourceName,
                importedAt: importedAt
            )
        }

        var seen = Set<String>()
        var entries: [TerminologyEntry] = []

        for line in lines {
            let term = parseCSVFields(line).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard isValidTerm(term) else {
                continue
            }

            let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else {
                continue
            }
            entries.append(
                TerminologyEntry(
                    type: .term,
                    original: term,
                    replacement: nil,
                    aliases: [],
                    isEnabled: true,
                    source: sourceName,
                    usageCount: 0,
                    createdAt: importedAt
                )
            )
        }

        return entries
    }

    private func extractStructuredEntries(
        from lines: [String],
        header: [String],
        sourceName: String,
        importedAt: String
    ) -> [TerminologyEntry] {
        let typeIndex = header.firstIndex(of: "type")
        let originalIndex = header.firstIndex(of: "original")
            ?? header.firstIndex(of: "term")
            ?? header.firstIndex(of: "word")
        let replacementIndex = header.firstIndex(of: "replacement")
            ?? header.firstIndex(of: "correction")
        let enabledIndex = header.firstIndex(of: "enabled")
        let aliasesIndex = header.firstIndex(of: "aliases")

        guard let originalIndex else {
            return []
        }

        var seen = Set<String>()
        var entries: [TerminologyEntry] = []
        for line in lines {
            let fields = parseCSVFields(line)
            guard originalIndex < fields.count else {
                continue
            }
            let original = fields[originalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidTerm(original) else {
                continue
            }

            let rawType = field(at: typeIndex, in: fields).lowercased()
            let replacement = field(at: replacementIndex, in: fields)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let type: TerminologyEntryType = rawType == TerminologyEntryType.correction.rawValue
                || !replacement.isEmpty
                ? .correction
                : .term
            guard type != .correction || !replacement.isEmpty else {
                continue
            }

            let entry = TerminologyEntry(
                type: type,
                original: original,
                replacement: type == .correction ? replacement : nil,
                aliases: field(at: aliasesIndex, in: fields)
                    .split(separator: "|")
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .filter { isValidTerm($0) },
                isEnabled: parseEnabled(field(at: enabledIndex, in: fields)),
                source: sourceName,
                usageCount: 0,
                createdAt: importedAt
            )
            guard seen.insert(TerminologyLibrary.key(for: entry)).inserted else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    private func parseCSVFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let nextIndex = line.index(after: index)
                if isQuoted, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    field.append("\"")
                    index = line.index(after: nextIndex)
                    continue
                }
                isQuoted.toggle()
            } else if character == "," && !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }

    private func isValidTerm(_ term: String) -> Bool {
        guard !term.isEmpty, term.count <= Self.maximumFieldCharacters else {
            return false
        }

        let lowercased = term.lowercased()
        let skippedHeaders: Set<String> = ["term", "terms", "original", "canonical", "word", "phrase"]
        return !skippedHeaders.contains(lowercased)
    }

    private func field(at index: Int?, in fields: [String]) -> String {
        guard let index, index < fields.count else {
            return ""
        }
        return fields[index]
    }

    private func parseEnabled(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return true
        }
        return !["0", "false", "no", "off", "disabled"].contains(normalized)
    }
}
