import Foundation

struct TranscriptionPromptBuilder {
    func buildPrompt(
        hintTerms: [String],
        speechCleanupEnabled: Bool = true,
        punctuationPreference: TranscriptPunctuationPreference = .automatic,
        locale: String = Locale.preferredLanguages.first ?? "zh-CN"
    ) -> String {
        let hints = Self.clippedHintTerms(hintTerms)

        var lines: [String] = [
            "Transcribe this speech into text that can be pasted directly.",
            "Add natural punctuation and sentence breaks, but do not rewrite meaning.",
            "Preserve the speaker's language exactly. If they spoke Chinese, keep Chinese (including the original simplified/traditional form). If they spoke English or another language, keep that language. Do not translate.",
            "Keep mixed-language phrases as spoken.",
            punctuationInstruction(for: punctuationPreference),
            "Do not alter filenames, version numbers, paths, URLs, emails, product names, commands, or parameter names.",
            "Do not treat system UI, placeholder text, or button labels as spoken content.",
            "Prefer correct spellings for terms, acronyms, and brand names.",
            "Return only the final transcript text.",
            "Locale: \(locale)",
        ]

        if speechCleanupEnabled {
            lines.insert(
                "Remove filler words, meaningless repeats, hesitation sounds, and mid-sentence self-corrections; keep only the final intended wording.",
                at: 2
            )
            lines.insert(
                "If the speaker dictates a list, steps, or bullet points, use concise line breaks or bullets without expanding the content.",
                at: 3
            )
        }

        if !hints.isEmpty {
            lines.append("Pay special attention to these terms:")
            lines.append(contentsOf: hints.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func punctuationInstruction(
        for preference: TranscriptPunctuationPreference
    ) -> String {
        switch preference {
        case .automatic:
            return "Choose punctuation style from the language of each phrase: full-width for Chinese runs, half-width for pure English runs."
        case .fullWidth:
            return "Use Chinese full-width punctuation."
        case .halfWidth:
            return "Use ASCII half-width punctuation."
        case .preserve:
            return "Preserve the transcript's original punctuation width; do not convert full-width and half-width forms."
        }
    }

    private static func clippedHintTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        var totalCharacters = 0

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else {
                continue
            }

            let projected = totalCharacters + trimmed.count
            guard projected <= 400 else {
                break
            }
            totalCharacters = projected
            output.append(trimmed)
            if output.count >= 24 {
                break
            }
        }

        return output
    }
}
