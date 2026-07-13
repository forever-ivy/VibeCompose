import AppKit
import Foundation
import Vision

enum PermissionSurfaceVerificationError: LocalizedError {
    case invalidArguments
    case unreadableImage
    case missingMicrophoneLabel
    case missingAccessibilityLabel
    case permissionsNotShownAsGranted(Int)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return """
            Usage: verify_permission_surface.swift <snapshot.png> \
              [--text-output <ocr.txt>]
            """
        case .unreadableImage:
            return "The permission surface snapshot could not be decoded."
        case .missingMicrophoneLabel:
            return "The installed permission surface does not show the Microphone card."
        case .missingAccessibilityLabel:
            return "The installed permission surface does not show the Accessibility card."
        case .permissionsNotShownAsGranted(let count):
            return """
            The installed permission surface did not show both permission cards \
            as granted (recognized granted statuses: \(count)).
            """
        }
    }
}

struct PermissionSurfaceArguments {
    let snapshotURL: URL
    let textOutputURL: URL?

    static func parse(_ arguments: [String]) throws -> Self {
        guard let first = arguments.first, !first.hasPrefix("--") else {
            throw PermissionSurfaceVerificationError.invalidArguments
        }

        var textOutputURL: URL?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--text-output":
                guard index + 1 < arguments.count else {
                    throw PermissionSurfaceVerificationError.invalidArguments
                }
                textOutputURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default:
                throw PermissionSurfaceVerificationError.invalidArguments
            }
        }

        return Self(
            snapshotURL: URL(fileURLWithPath: first),
            textOutputURL: textOutputURL
        )
    }
}

func normalized(_ value: String) -> String {
    value
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

func containsAny(_ text: String, candidates: [String]) -> Bool {
    candidates.contains { text.contains(normalized($0)) }
}

func containsCJKSequence(
    _ text: String,
    firstCharacters: [Character],
    trailingCharacterGroups: [[Character]]
) -> Bool {
    let characters = Array(text)
    for (index, character) in characters.enumerated()
    where firstCharacters.contains(character) {
        var searchStart = index + 1
        var matched = true
        for group in trailingCharacterGroups {
            guard searchStart < characters.count,
                  let matchIndex = characters[searchStart...].firstIndex(
                    where: group.contains
                  )
            else {
                matched = false
                break
            }
            searchStart = matchIndex + 1
        }
        if matched {
            return true
        }
    }
    return false
}

func containsMicrophoneLabel(_ text: String) -> Bool {
    containsAny(text, candidates: ["Microphone", "麦克风"])
        || containsCJKSequence(
            text,
            firstCharacters: ["麦"],
            trailingCharacterGroups: [["克"], ["风"]]
        )
}

func containsAccessibilityLabel(_ text: String) -> Bool {
    containsAny(text, candidates: ["Accessibility", "辅助功能"])
        || containsCJKSequence(
            text,
            firstCharacters: ["辅"],
            trailingCharacterGroups: [["助", "功"], ["功", "能"]]
        )
}

func containsGrantedStatus(_ text: String) -> Bool {
    containsAny(text, candidates: ["Granted", "已授权"])
        || containsCJKSequence(
            text,
            firstCharacters: ["已"],
            trailingCharacterGroups: [["授"], ["权", "枚", "扌"]]
        )
}

do {
    let arguments = try PermissionSurfaceArguments.parse(
        Array(CommandLine.arguments.dropFirst())
    )
    guard
        let image = NSImage(contentsOf: arguments.snapshotURL),
        let tiffRepresentation = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffRepresentation),
        let cgImage = bitmap.cgImage
    else {
        throw PermissionSurfaceVerificationError.unreadableImage
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    // Prefer the system's observed Simplified Chinese UI first. Vision's
    // language ordering materially affects mixed-script recognition quality.
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    try VNImageRequestHandler(cgImage: cgImage).perform([request])

    let lines = (request.results ?? []).compactMap {
        $0.topCandidates(1).first?.string
    }
    let normalizedLines = lines.map(normalized)
    let joinedText = normalizedLines.joined(separator: "\n")

    let hasMicrophoneLabel = containsMicrophoneLabel(joinedText)
    let hasAccessibilityLabel = containsAccessibilityLabel(joinedText)
    let grantedStatusCount = normalizedLines.filter {
        containsGrantedStatus($0)
    }.count

    if let textOutputURL = arguments.textOutputURL {
        try FileManager.default.createDirectory(
            at: textOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(
            to: textOutputURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: textOutputURL.path
        )
    }

    guard hasMicrophoneLabel else {
        throw PermissionSurfaceVerificationError.missingMicrophoneLabel
    }
    guard hasAccessibilityLabel else {
        throw PermissionSurfaceVerificationError.missingAccessibilityLabel
    }
    guard grantedStatusCount >= 2 else {
        throw PermissionSurfaceVerificationError.permissionsNotShownAsGranted(
            grantedStatusCount
        )
    }

    print(
        """
        Installed permission surface verification passed:
        - Microphone card recognized: \(hasMicrophoneLabel)
        - Accessibility card recognized: \(hasAccessibilityLabel)
        - Granted statuses recognized: \(grantedStatusCount)
        """
    )
} catch {
    fputs(
        "Installed permission surface verification failed: \(error.localizedDescription)\n",
        stderr
    )
    exit(1)
}
