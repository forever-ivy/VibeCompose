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
