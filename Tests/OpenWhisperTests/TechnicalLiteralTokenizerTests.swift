import Testing
@testable import OpenWhisper

@Test
func technicalLiteralTokenizerRoundTripsSupportedLiteralFamilies() throws {
    let text = """
    打开 /Users/小龍/專案/config.json，访问 https://example.com/繁體?q=a,b，\
    运行 `open -a OpenWhisper` --output=報告.txt，版本 v1.2.3，邮箱 dev@example.com，\
    调用 foo.bar(傳統)。
    """

    let tokenization = TechnicalLiteralTokenizer().tokenize(text)
    let restored = try #require(
        tokenization.restoringLiterals(in: tokenization.maskedText)
    )

    #expect(tokenization.literals.contains("/Users/小龍/專案/config.json"))
    #expect(tokenization.literals.contains("https://example.com/繁體?q=a,b"))
    #expect(tokenization.literals.contains("`open -a OpenWhisper`"))
    #expect(tokenization.literals.contains("--output=報告.txt"))
    #expect(tokenization.literals.contains("v1.2.3"))
    #expect(tokenization.literals.contains("dev@example.com"))
    #expect(tokenization.literals.contains("foo.bar(傳統)"))
    #expect(restored == text)
}

@Test
func terminologyNormalizerPreservesTechnicalLiteralsAcrossScriptAndPunctuationConversion() {
    let result = TerminologyNormalizer().normalize(
        text: "請打開 /Users/小龍/專案/config.json, 訪問 https://example.com/繁體?q=a,b! 再執行 `echo 傳統`.",
        importedEntries: [
            TerminologyEntry(canonical: "CONFIG", aliases: ["config"]),
        ],
        hintTerms: []
    )

    #expect(
        result.text
            == "请打开 /Users/小龍/專案/config.json， 访问 https://example.com/繁體?q=a,b！ 再执行 `echo 傳統`。"
    )
    #expect(result.text.contains("/Users/小龍/專案/config.json"))
    #expect(result.text.contains("https://example.com/繁體?q=a,b"))
    #expect(result.text.contains("`echo 傳統`"))
    #expect(result.text.contains("/Users/小龍/專案/CONFIG.json") == false)
}

@Test
func terminologyNormalizerHonorsPreserveLanguageAndPunctuationPreferences() {
    let original = "請保留繁體, path 是 /Users/小龍/config.json!"
    let result = TerminologyNormalizer(
        languagePreference: .preserve,
        punctuationPreference: .preserve
    ).normalize(
        text: original,
        importedEntries: [],
        hintTerms: []
    )

    #expect(result.text == original)
    #expect(result.applied == false)
}

@Test
func terminologyNormalizerSupportsTraditionalChineseWithHalfWidthPunctuation() {
    let result = TerminologyNormalizer(
        languagePreference: .traditionalChinese,
        punctuationPreference: .halfWidth
    ).normalize(
        text: "请打开文件，确认！路径是 /Users/小龙/项目。",
        importedEntries: [],
        hintTerms: []
    )

    #expect(result.text == "請打開文件,確認!路徑是 /Users/小龙/项目.")
}

@Test
func terminologyNormalizerCanForceFullWidthPunctuationForEnglishOutput() {
    let result = TerminologyNormalizer(
        languagePreference: .preserve,
        punctuationPreference: .fullWidth
    ).normalize(
        text: "Hello, world!",
        importedEntries: [],
        hintTerms: []
    )

    #expect(result.text == "Hello， world！")
}

@Test
func modelSafeLiteralTokensRequireExactlyOneCopyBeforeRestoration() throws {
    let tokenization = TechnicalLiteralTokenizer().tokenize(
        "Open /tmp/report.txt now.",
        style: .modelSafe
    )
    let token = try #require(
        tokenization.maskedText
            .split(separator: " ")
            .first(where: { $0.contains("OW_LITERAL") })
    )

    #expect(
        tokenization.restoringLiterals(
            in: tokenization.maskedText.replacingOccurrences(of: String(token), with: "")
        ) == nil
    )
    #expect(
        tokenization.restoringLiterals(
            in: "\(tokenization.maskedText) \(token)"
        ) == nil
    )
}
