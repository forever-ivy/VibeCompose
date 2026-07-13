import AppKit
import Foundation
import Testing
@testable import OpenWhisper

@MainActor
@Test
func liveTextInjectorPastesIntoLaunchAppEditorAfterFocusMovesAway() async throws {
    guard ProcessInfo.processInfo.environment["OPENWHISPER_LIVE_TEXTINJECTOR_ACCEPTANCE"] == "1" else {
        return
    }

    let phrase = "focus paste test \(UUID().uuidString.prefix(8))"
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openwhisper-live-inject-\(UUID().uuidString).txt")
    _ = FileManager.default.createFile(atPath: fileURL.path, contents: Data())

    _ = try runAppleScript("""
    tell application "TextEdit"
      activate
      open POSIX file "\(fileURL.path)"
      delay 0.4
      set text of front document to ""
    end tell
    tell application "System Events"
      tell process "TextEdit"
        set frontmost to true
        delay 0.2
      end tell
    end tell
    """)
    defer {
        _ = try? runAppleScript("""
        tell application "TextEdit"
          if (count of documents) > 0 then close front document saving no
        end tell
        """)
        try? FileManager.default.removeItem(at: fileURL)
    }

    try await Task.sleep(nanoseconds: 400_000_000)
    let launchAppContext = try #require(LaunchAppContext.current())
    #expect(launchAppContext.bundleIdentifier == "com.apple.TextEdit")

    _ = try runAppleScript("""
    tell application "System Events"
      tell process "OpenWhisper"
        click menu bar item 1 of menu bar 1
        delay 0.1
        click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 1
      end tell
    end tell
    delay 0.5
    """)

    let outcome = try await TextInjector().inject(
        text: phrase,
        preserveClipboard: false,
        restoreDelayMilliseconds: 50,
        launchAppContext: launchAppContext,
        automaticPasteAllowed: true
    )
    #expect(outcome == .insertedAndVerified)

    try await Task.sleep(nanoseconds: 400_000_000)
    let documentText = try runAppleScript("""
    tell application "TextEdit"
      if (count of documents) > 0 then return text of front document
      return ""
    end tell
    """)
    #expect(documentText.contains(phrase))
    #expect(NSPasteboard.general.string(forType: .string) == phrase)
}

@MainActor
@Test
func liveTextInjectorPastesIntoCodexComposerAfterFocusMovesAway() async throws {
    guard ProcessInfo.processInfo.environment["OPENWHISPER_LIVE_CODEX_ACCEPTANCE"] == "1" else {
        return
    }

    let phrase = "codex paste test \(UUID().uuidString.prefix(8))"

    _ = try runAppleScript("""
    tell application "Codex" to activate
    delay 0.4
    tell application "System Events"
      keystroke "n" using command down
    end tell
    delay 0.8
    """)

    let launchAppContext = try #require(LaunchAppContext.current())
    #expect(launchAppContext.bundleIdentifier == "com.openai.codex")
    #expect(FocusedElementInspector.hasEditableTextFocus(in: launchAppContext))

    _ = try runAppleScript("""
    tell application "System Events"
      tell process "OpenWhisper"
        click menu bar item 1 of menu bar 1
        delay 0.1
        click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 1
      end tell
    end tell
    delay 0.5
    """)

    let outcome = try await TextInjector().inject(
        text: phrase,
        preserveClipboard: false,
        restoreDelayMilliseconds: 50,
        launchAppContext: launchAppContext,
        automaticPasteAllowed: true
    )
    #expect(
        outcome == .insertedAndVerified ||
            outcome == .pasteDispatchedClipboardRetained
    )

    try await Task.sleep(nanoseconds: 500_000_000)
    _ = try runAppleScript("""
    tell application "Codex" to activate
    delay 0.4
    tell application "System Events"
      keystroke "a" using command down
      delay 0.1
      keystroke "c" using command down
    end tell
    delay 0.3
    """)
    let copiedBack = NSPasteboard.general.string(forType: .string)
    #expect(copiedBack?.contains(phrase) == true)
    #expect(NSPasteboard.general.string(forType: .string) == phrase)
}

private func runAppleScript(_ source: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error

    try process.run()
    input.fileHandleForWriting.write(Data(source.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()

    let outputText = String(
        data: output.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    if process.terminationStatus != 0 {
        let errorText = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw NSError(
            domain: "LiveTextInjectorAcceptanceTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: errorText]
        )
    }
    return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
}
