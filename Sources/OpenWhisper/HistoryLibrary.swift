import Foundation

enum HistoryKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case transcripts = "Transcripts"
    case recovery = "Recovery"

    var id: String { rawValue }
}

enum HistoryStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All statuses"
    case verified = "Verified insertions"
    case pasteSent = "Paste sent"
    case copied = "Copied"
    case errors = "Errors"

    var id: String { rawValue }
}

enum HistoryDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All time"
    case today = "Today"
    case sevenDays = "Last 7 days"
    case thirtyDays = "Last 30 days"

    var id: String { rawValue }

    func cutoffDate(
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: now)
        }
    }
}

enum HistoryEntryKind: Sendable, Equatable {
    case transcript
    case recovery
}

struct HistoryEntry: Identifiable, Sendable, Equatable {
    let id: String
    let kind: HistoryEntryKind
    let timestamp: Date
    let target: String
    let outcome: String
    let summary: String
    let searchableText: String
    let transcriptionRecord: TranscriptionHistoryRecord?
    let recoveryRecord: RecoveryRecord?

    static func transcript(_ record: TranscriptionHistoryRecord) -> HistoryEntry {
        HistoryEntry(
            id: "transcript-\(record.id.uuidString)",
            kind: .transcript,
            timestamp: record.timestamp,
            target: target(appName: record.appName),
            outcome: record.outcome,
            summary: collapsed(record.finalText),
            searchableText: [
                record.finalText,
                record.rawText ?? "",
                record.appName ?? "",
                record.appBundleIdentifier ?? "",
                record.outcome,
                record.textPolishProvider ?? "",
                record.skillID ?? "",
                record.skillName ?? "",
                record.skillSource ?? "",
                record.skillRevision ?? "",
                record.skillValidationIssueCodes
                    .joined(separator: " "),
                record.skillDeliveryAction ?? "",
                record.skillResultEdited
                    ? "edited"
                    : "",
            ].joined(separator: " "),
            transcriptionRecord: record,
            recoveryRecord: nil
        )
    }

    static func recovery(_ record: RecoveryRecord) -> HistoryEntry {
        let preferredText = record.polishText ?? record.asrText
        let fallback = record.errorMessage ?? L10n.text("Recoverable audio")
        return HistoryEntry(
            id: "recovery-\(record.id.uuidString)",
            kind: .recovery,
            timestamp: record.timestamp,
            target: target(appName: record.appName),
            outcome: record.outcome,
            summary: collapsed(preferredText ?? fallback),
            searchableText: [
                record.polishText ?? "",
                record.asrText ?? "",
                record.errorMessage ?? "",
                record.appName ?? "",
                record.appBundleIdentifier ?? "",
                record.outcome,
            ].joined(separator: " "),
            transcriptionRecord: nil,
            recoveryRecord: record
        )
    }

    private static func target(appName: String?) -> String {
        let value = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? L10n.text("Unknown target") : value
    }

    private static func collapsed(_ text: String, limit: Int = 180) -> String {
        let value = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit)) + "…"
    }
}

enum HistoryLibrary {
    static func filteredEntries(
        transcripts: [TranscriptionHistoryRecord],
        recovery: [RecoveryRecord],
        query: String,
        kindFilter: HistoryKindFilter,
        statusFilter: HistoryStatusFilter,
        dateFilter: HistoryDateFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HistoryEntry] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let cutoffDate = dateFilter.cutoffDate(relativeTo: now, calendar: calendar)

        return (transcripts.map(HistoryEntry.transcript) + recovery.map(HistoryEntry.recovery))
            .filter { entry in
                switch kindFilter {
                case .all:
                    return true
                case .transcripts:
                    return entry.kind == .transcript
                case .recovery:
                    return entry.kind == .recovery
                }
            }
            .filter { entry in
                switch statusFilter {
                case .all:
                    return true
                case .verified:
                    return TextDeliveryStatus.kind(for: entry.outcome) == .insertedAndVerified
                case .pasteSent:
                    return TextDeliveryStatus.kind(for: entry.outcome) == .pasteDispatched
                case .copied:
                    return TextDeliveryStatus.kind(for: entry.outcome) == .clipboard
                case .errors:
                    return TextDeliveryStatus.kind(for: entry.outcome) == .error ||
                        entry.kind == .recovery
                }
            }
            .filter { entry in
                guard let cutoffDate else {
                    return true
                }
                return entry.timestamp >= cutoffDate
            }
            .filter { entry in
                guard !normalizedQuery.isEmpty else {
                    return true
                }
                return entry.searchableText
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                    .contains(normalizedQuery)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
