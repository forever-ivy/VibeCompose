import Foundation
import Testing
@testable import OpenWhisper

@Test
func simplifiedChineseLocalizationCoversCorePermissionAndDictationUI() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let stringsURL = root
        .appendingPathComponent("Sources/OpenWhisper/Resources/zh-Hans.lproj/Localizable.strings")
    let data = try Data(contentsOf: stringsURL)
    let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
    let strings = try #require(propertyList as? [String: String])

    #expect(strings["OpenWhisper Settings"] == "OpenWhisper 设置")
    #expect(strings["Microphone"] == "麦克风")
    #expect(strings["Accessibility"] == "辅助功能")
    #expect(strings["Refresh Status"] == "刷新权限状态")
    #expect(
        strings[
            "OpenWhisper still cannot confirm microphone access. Click Refresh Status or reopen the app."
        ] == "OpenWhisper 仍无法确认麦克风权限。请点击“刷新权限状态”或重新打开应用。"
    )
    #expect(strings["Ready. Press F5 to dictate"] == "已就绪。按 F5 开始听写")
    #expect(strings["F5 again to transcribe"] == "再次按 F5 开始转写")
    #expect(strings["Inserted"] == "已确认插入")
    #expect(strings["Paste sent"] == "已发送粘贴")
    #expect(strings["Verified insertions"] == "已确认插入")
    #expect(
        strings["Transcript insertion verified"]
            == "已确认转写结果插入成功"
    )
    #expect(strings["Saved automatically"] == "已自动保存")
    #expect(strings["Save failed"] == "保存失败")
    #expect(strings["Configuration"] == "配置")
    #expect(strings["Export Diagnostics…"] == "导出诊断…")
    #expect(strings["Support Diagnostics"] == "支持诊断")
    #expect(strings["Export Product Metrics…"] == "导出产品指标…")
    #expect(
        strings["Keep local anonymous product metrics"]
            == "保留本地匿名产品指标"
    )
    #expect(strings["Software Updates"] == "软件更新")
    #expect(strings["Check for Updates…"] == "检查更新…")
    #expect(strings["Automatically check for updates"] == "自动检查更新")
    #expect(strings["Provider Safety"] == "服务安全策略")
    #expect(strings["Refresh Safety Policy"] == "刷新安全策略")
    #expect(strings["Managed ChatGPT transcription"] == "ChatGPT 托管转写")
    #expect(strings["Endpoint"] == "端点")
    #expect(strings["Model"] == "模型")
    #expect(strings["API Key"] == "API 密钥")
    #expect(strings["Save API Key"] == "保存 API 密钥")
    #expect(strings["Remove API Key"] == "移除 API 密钥")
    #expect(strings["Use Paid API"] == "使用付费 API")
    #expect(
        strings["Switch Back to ChatGPT Account"]
            == "切回 ChatGPT 账户"
    )
    #expect(
        strings["API key stored in Keychain"]
            == "API 密钥已存入钥匙串"
    )
    #expect(strings["Open Source Licenses"] == "开源许可证")
    #expect(
        strings["View Third-Party Licenses…"]
            == "查看第三方许可证…"
    )
    #expect(strings["Third-Party Licenses"] == "第三方许可证")
    #expect(strings["Skills"] == "技能")
    #expect(strings["Default Skill"] == "默认技能")
    #expect(strings["Backend Prompt"] == "后端任务提示词")
    #expect(strings["Code Prompt"] == "代码提示词")
    #expect(strings["Application Rules"] == "应用规则")
    #expect(strings["Skills require OpenWhisper Pro"] == "技能需要 OpenWhisper Pro")
    #expect(strings["Context"] == "上下文")
    #expect(strings["Context Rewrite"] == "选区改写")
    #expect(strings["Context Reply"] == "选区回复")
    #expect(strings["Replace Selection"] == "替换选区")
    #expect(strings["Ask every time"] == "每次询问")
    #expect(
        strings[
            "Reply, Email, Backend Prompt, Code Prompt, and Translate need a connected ChatGPT account for AI Polish. Direct dictation and transcription recovery still work without it."
        ]
            == "回复、邮件、后端任务提示词、代码提示词和翻译技能需要连接 ChatGPT 账号才能使用 AI 润色。未连接时，直述听写和转写恢复路径仍可继续使用。"
    )
}

@Test
func simplifiedChineseInfoPlistLocalizesMicrophoneUsageDescription() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let stringsURL = root
        .appendingPathComponent("Sources/OpenWhisper/Resources/zh-Hans.lproj/InfoPlist.strings")
    let data = try Data(contentsOf: stringsURL)
    let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
    let strings = try #require(propertyList as? [String: String])

    #expect(strings["NSMicrophoneUsageDescription"]?.contains("麦克风") == true)
}
