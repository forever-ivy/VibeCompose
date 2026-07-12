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
    #expect(strings["Ready. Press F5 to dictate"] == "已就绪。按 F5 开始听写")
    #expect(strings["F5 again to transcribe"] == "再次按 F5 开始转写")
    #expect(strings["Saved automatically"] == "已自动保存")
    #expect(strings["Save failed"] == "保存失败")
    #expect(strings["Configuration"] == "配置")
    #expect(strings["Export Diagnostics…"] == "导出诊断…")
    #expect(strings["Support Diagnostics"] == "支持诊断")
    #expect(strings["Software Updates"] == "软件更新")
    #expect(strings["Check for Updates…"] == "检查更新…")
    #expect(strings["Automatically check for updates"] == "自动检查更新")
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
