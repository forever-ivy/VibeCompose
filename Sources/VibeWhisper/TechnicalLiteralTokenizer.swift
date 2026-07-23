import Foundation

struct TechnicalLiteralTokenization: Sendable, Equatable {
    let maskedText: String
    let literals: [String]
    fileprivate let replacements: [String: String]

    var isEmpty: Bool {
        replacements.isEmpty
    }

    func restoringLiterals(
        in candidate: String,
        requireExactlyOnce: Bool = true
    ) -> String? {
        restoringLiterals(
            in: candidate,
            requireExactlyOnce: requireExactlyOnce,
            transform: { $0 }
        )
    }

    func restoringLiterals(
        in candidate: String,
        requireExactlyOnce: Bool = true,
        transform: (String) -> String
    ) -> String? {
        if requireExactlyOnce {
            for token in replacements.keys {
                guard candidate.components(separatedBy: token).count == 2 else {
                    return nil
                }
            }
        }

        return replacements.reduce(candidate) { text, replacement in
            text.replacingOccurrences(
                of: replacement.key,
                with: transform(replacement.value)
            )
        }
    }
}

struct TechnicalLiteralTokenizer: Sendable {
    enum TokenStyle: Sendable {
        case privateUse
        case modelSafe
    }

    func tokenize(
        _ text: String,
        style: TokenStyle = .privateUse
    ) -> TechnicalLiteralTokenization {
        let ranges = protectedRanges(in: text)
        guard !ranges.isEmpty else {
            return TechnicalLiteralTokenization(
                maskedText: text,
                literals: [],
                replacements: [:]
            )
        }

        var maskedText = text
        var literals = Array(repeating: "", count: ranges.count)
        var replacements: [String: String] = [:]

        for (index, nsRange) in ranges.enumerated().reversed() {
            guard let range = Range(nsRange, in: maskedText) else {
                continue
            }
            let literal = String(maskedText[range])
            let token = uniqueToken(
                for: index,
                style: style,
                avoiding: text,
                existing: replacements
            )
            literals[index] = literal
            replacements[token] = literal
            maskedText.replaceSubrange(range, with: token)
        }

        return TechnicalLiteralTokenization(
            maskedText: maskedText,
            literals: literals.filter { !$0.isEmpty },
            replacements: replacements
        )
    }

    func protectedRanges(in text: String) -> [NSRange] {
        let patterns = [
            #"(?s:```.*?```)"#,
            #"`[^`\r\n]+`"#,
            #"(?i)\b(?:https?|ftp)://[^\s<>{}\[\]"'，。！？；：]+"#,
            #"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"#,
            #"(?<![\w])(?:~|/|\./|\../)[^\s<>{}\[\]"'，。！？；：]+"#,
            #"\b[A-Za-z]:\\(?:[^\\\s<>:"|?*，。！？；：]+\\)*[^\\\s<>:"|?*，。！？；：]*"#,
            #"(?<!\S)--?[A-Za-z0-9][A-Za-z0-9-]*(?:=[^\s，。！？；：]+)?"#,
            #"\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*"#,
            #"\bv?\d+(?:\.\d+){1,}(?:[-+][A-Za-z0-9.-]+)?\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b"#,
            #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#,
            #"\b(?:sha(?:1|224|256|384|512):)?[0-9A-Fa-f]{32,128}\b"#,
            #"(?<![\w])[@A-Za-z0-9_+.-]+(?:/[@A-Za-z0-9_+.-]+)?\.[A-Za-z0-9]{1,16}(?![\w])"#,
            #"\b[A-Za-z_][A-Za-z0-9_.]*(?:::?[A-Za-z_][A-Za-z0-9_]*|\([^()\r\n]*\))"#,
        ]

        let fullRange = NSRange(text.startIndex..., in: text)
        var matches: [NSRange] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            matches.append(
                contentsOf: regex.matches(
                    in: text,
                    range: fullRange
                ).map(\.range)
            )
        }

        let normalized = matches
            .map { trimmedRange($0, in: text) }
            .filter { $0.length > 0 }
            .sorted { lhs, rhs in
                if lhs.location != rhs.location {
                    return lhs.location < rhs.location
                }
                return lhs.length > rhs.length
            }

        var merged: [NSRange] = []
        for range in normalized {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if NSIntersectionRange(last, range).length > 0 {
                let union = NSUnionRange(last, range)
                merged[merged.count - 1] = union
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private func trimmedRange(_ range: NSRange, in text: String) -> NSRange {
        guard var swiftRange = Range(range, in: text) else {
            return range
        }
        let trailingCharacters = CharacterSet(charactersIn: ".,!?;:，。！？；：")

        while
            swiftRange.lowerBound < swiftRange.upperBound,
            let scalar = text[swiftRange].unicodeScalars.last,
            trailingCharacters.contains(scalar)
        {
            swiftRange = swiftRange.lowerBound..<text.index(before: swiftRange.upperBound)
        }

        return NSRange(swiftRange, in: text)
    }

    private func uniqueToken(
        for index: Int,
        style: TokenStyle,
        avoiding originalText: String,
        existing: [String: String]
    ) -> String {
        var candidateIndex = index
        while true {
            let candidate: String
            switch style {
            case .privateUse:
                let scalarValue = 0xF0000 + candidateIndex
                candidate = Unicode.Scalar(scalarValue).map(String.init)
                    ?? "\u{F0000}"
            case .modelSafe:
                candidate = String(format: "⟪OW_LITERAL_%04d⟫", candidateIndex)
            }

            if !originalText.contains(candidate), existing[candidate] == nil {
                return candidate
            }
            candidateIndex += 1
        }
    }
}
