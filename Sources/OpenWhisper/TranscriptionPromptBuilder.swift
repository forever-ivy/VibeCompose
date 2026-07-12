import Foundation

struct TranscriptionPromptBuilder {
    func buildPrompt(
        hintTerms: [String],
        speechCleanupEnabled: Bool = true,
        languagePreference: TranscriptLanguagePreference = .simplifiedChinese,
        punctuationPreference: TranscriptPunctuationPreference = .automatic,
        locale: String = Locale.preferredLanguages.first ?? "zh-CN"
    ) -> String {
        let hints = Self.clippedHintTerms(hintTerms)

        var lines: [String] = [
            "请将这段语音转成可直接粘贴使用的文本。",
            "输出带自然标点和断句，但不要做二次改写。",
            "保留中英混合表达，保持原意。",
            languageInstruction(for: languagePreference),
            punctuationInstruction(for: punctuationPreference),
            "不要改动文件名、版本号、路径、URL、邮箱、产品名、命令、参数名。",
            "不要把系统界面、输入框提示、按钮文案当作语音内容输出。",
            "优先正确写出术语、缩写、品牌词。",
            "只返回最终文本。",
            "Locale: \(locale)",
        ]

        if speechCleanupEnabled {
            lines.insert("清理口头填充词、无意义重复、停顿词和说话中途改口，只保留最终想表达的文本。", at: 2)
            lines.insert("如果用户口头说出列表、步骤或要点，用简洁的换行或项目符号整理，但不要扩写内容。", at: 3)
        }

        if !hints.isEmpty {
            lines.append("请特别注意这些术语：")
            lines.append(contentsOf: hints.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func languageInstruction(
        for preference: TranscriptLanguagePreference
    ) -> String {
        switch preference {
        case .simplifiedChinese:
            return "中文内容输出简体中文，不要输出繁体中文。"
        case .traditionalChinese:
            return "中文内容輸出繁體中文，不要轉成簡體中文。"
        case .preserve:
            return "保留转录结果原本的语言和中文简繁体，不要主动转换。"
        }
    }

    private func punctuationInstruction(
        for preference: TranscriptPunctuationPreference
    ) -> String {
        switch preference {
        case .automatic:
            return "标点随语言自动选择：中文使用全角标点，纯英文保留半角标点。"
        case .fullWidth:
            return "输出使用中文全角标点。"
        case .halfWidth:
            return "输出使用 ASCII 半角标点。"
        case .preserve:
            return "保留转录结果原有标点样式，不要主动转换全角或半角。"
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

            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else {
                continue
            }

            let nextTotal = totalCharacters + trimmed.count + (output.isEmpty ? 0 : 2)
            guard nextTotal <= 600 else {
                break
            }

            output.append(trimmed)
            totalCharacters = nextTotal
        }

        return output
    }
}
