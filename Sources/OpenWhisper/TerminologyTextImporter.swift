import Foundation

struct TerminologyTextImportResult: Sendable, Equatable {
    let entries: [TerminologyEntry]
    let source: String
    let importedAt: String
}

enum TerminologyTextImportError: LocalizedError, Equatable {
    case unreadableText(String)
    case noValidEntries(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText(let source):
            return L10n.format("Could not read terminology dictionary text: %@", source)
        case .noValidEntries(let source):
            return L10n.format("No valid terminology entries found in %@.", source)
        }
    }
}

struct TerminologyTextImporter {
    func importEntries(from data: Data, sourceName: String) throws -> TerminologyTextImportResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TerminologyTextImportError.unreadableText(sourceName)
        }

        let importedAt = ISO8601DateFormatter().string(from: Date())
        let terms = extractTerms(from: text)
        guard !terms.isEmpty else {
            throw TerminologyTextImportError.noValidEntries(sourceName)
        }

        return TerminologyTextImportResult(
            entries: terms.map {
                TerminologyEntry(
                    type: .term,
                    original: $0,
                    replacement: nil,
                    aliases: [],
                    isEnabled: true,
                    source: sourceName,
                    usageCount: 0,
                    createdAt: importedAt
                )
            },
            source: sourceName,
            importedAt: importedAt
        )
    }

    private func extractTerms(from text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let term = firstField(from: String(line))
            guard isValidTerm(term) else {
                continue
            }

            let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else {
                continue
            }
            terms.append(term)
        }

        return terms
    }

    private func firstField(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("#") else {
            return ""
        }
        guard trimmed.contains(",") else {
            return trimmed
        }

        var field = ""
        var isQuoted = false
        var iterator = trimmed.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                isQuoted.toggle()
                continue
            }
            if character == "," && !isQuoted {
                break
            }
            field.append(character)
        }
        return field.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidTerm(_ term: String) -> Bool {
        guard !term.isEmpty else {
            return false
        }

        let lowercased = term.lowercased()
        let skippedHeaders: Set<String> = ["term", "terms", "original", "canonical", "word", "phrase"]
        return !skippedHeaders.contains(lowercased)
    }
}
