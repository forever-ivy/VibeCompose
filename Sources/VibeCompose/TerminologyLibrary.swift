import Foundation

struct TerminologyImportPreview: Identifiable, Sendable, Equatable {
    let id = UUID()
    let result: TerminologyTextImportResult
    let newEntries: [TerminologyEntry]
    let duplicateEntries: [TerminologyEntry]
    let conflictingEntries: [TerminologyEntry]

    var importedCount: Int {
        result.entries.count
    }
}

enum TerminologyLibrary {
    static func importPreview(
        existing: [TerminologyEntry],
        result: TerminologyTextImportResult
    ) -> TerminologyImportPreview {
        var exactKeys = Set(existing.map(key(for:)))
        var identityKeys = Set(existing.map(identityKey(for:)))
        var newEntries: [TerminologyEntry] = []
        var duplicateEntries: [TerminologyEntry] = []
        var conflictingEntries: [TerminologyEntry] = []

        for entry in result.entries {
            let exactKey = key(for: entry)
            let identityKey = identityKey(for: entry)
            if exactKeys.contains(exactKey) {
                duplicateEntries.append(entry)
            } else if identityKeys.contains(identityKey) {
                conflictingEntries.append(entry)
            } else {
                newEntries.append(entry)
                exactKeys.insert(exactKey)
                identityKeys.insert(identityKey)
            }
        }

        return TerminologyImportPreview(
            result: result,
            newEntries: newEntries,
            duplicateEntries: duplicateEntries,
            conflictingEntries: conflictingEntries
        )
    }

    static func merge(
        existing: [TerminologyEntry],
        incoming: [TerminologyEntry]
    ) -> [TerminologyEntry] {
        var output = existing
        var identities = Set(existing.map(identityKey(for:)))

        for entry in incoming {
            guard identities.insert(identityKey(for: entry)).inserted else {
                continue
            }
            output.append(entry)
        }

        return output
    }

    static func csvData(entries: [TerminologyEntry]) -> Data {
        var rows = [
            ["type", "original", "replacement", "enabled", "aliases"],
        ]
        rows.append(
            contentsOf: entries
                .sorted {
                    $0.original.localizedStandardCompare($1.original) == .orderedAscending
                }
                .map { entry in
                    [
                        entry.type.rawValue,
                        entry.original,
                        entry.replacement ?? "",
                        entry.isEnabled ? "true" : "false",
                        entry.aliases.joined(separator: "|"),
                    ]
                }
        )

        let text = rows
            .map { $0.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        return Data(text.utf8)
    }

    static func key(for entry: TerminologyEntry) -> String {
        [
            entry.type.rawValue,
            folded(entry.original),
            folded(entry.replacement ?? ""),
        ].joined(separator: "|")
    }

    static func identityKey(for entry: TerminologyEntry) -> String {
        [
            entry.type.rawValue,
            folded(entry.original),
        ].joined(separator: "|")
    }

    private static func folded(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }

    private static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
