import CryptoKit
import Foundation
import OpenWhisperLicensing

private enum LicenseToolError: LocalizedError {
    case usage(String)
    case missingOption(String)
    case invalidOption(String)
    case unsafeOutput(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message),
             .missingOption(let message),
             .invalidOption(let message),
             .unsafeOutput(let message):
            return message
        }
    }
}

private struct Arguments {
    let command: String
    let options: [String: String]

    init(_ values: [String]) throws {
        guard let command = values.first else {
            throw LicenseToolError.usage(Self.usage)
        }
        self.command = command

        var options: [String: String] = [:]
        var index = 1
        while index < values.count {
            let key = values[index]
            guard key.hasPrefix("--"), index + 1 < values.count else {
                throw LicenseToolError.usage(Self.usage)
            }
            guard options[key] == nil else {
                throw LicenseToolError.invalidOption(
                    "Duplicate option: \(key)"
                )
            }
            options[key] = values[index + 1]
            index += 2
        }
        self.options = options
    }

    func required(_ name: String) throws -> String {
        guard let value = options["--\(name)"], !value.isEmpty else {
            throw LicenseToolError.missingOption(
                "Missing required option --\(name)."
            )
        }
        return value
    }

    static let usage = """
    Usage:
      OpenWhisperLicenseTool generate-keypair \
        --private-key <path> --public-key <path>

      OpenWhisperLicenseTool issue \
        --private-key <path> --output <path> \
        --product <bundle-id> --license-id <id> --activation-id <id> \
        --device-id <uuid> --edition <founderPro|pro> \
        --features <comma-separated feature raw values> \
        --issued-at <ISO-8601> --verification-due-at <ISO-8601> \
        --offline-grace-ends-at <ISO-8601> \
        --maximum-build <number> --maximum-devices <number>

      OpenWhisperLicenseTool verify \
        --public-key <path> --receipt <path> \
        --product <bundle-id> --device-id <uuid> \
        --current-build <number> --now <ISO-8601>
    """
}

private func readBase64Key(at path: String, expectedBytes: Int) throws -> Data {
    let text = try String(
        contentsOf: URL(fileURLWithPath: path),
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let data = Data(base64Encoded: text),
        data.count == expectedBytes
    else {
        throw LicenseToolError.invalidOption(
            "Invalid base64 key at \(path)."
        )
    }
    return data
}

private func write(
    _ data: Data,
    to path: String,
    permissions: Int
) throws {
    let url = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: url.path) else {
        throw LicenseToolError.unsafeOutput(
            "Refusing to replace existing output: \(url.path)"
        )
    }
    try data.write(to: url, options: [.withoutOverwriting])
    try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
    )
}

private func parseDate(_ value: String, option: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
    ]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: value) else {
        throw LicenseToolError.invalidOption(
            "Invalid ISO-8601 value for --\(option)."
        )
    }
    return date
}

private func generateKeypair(_ arguments: Arguments) throws {
    let privateKeyURL = try arguments.required("private-key")
    let publicKeyURL = try arguments.required("public-key")
    let privateKey = Curve25519.Signing.PrivateKey()
    try write(
        Data(privateKey.rawRepresentation.base64EncodedString().utf8),
        to: privateKeyURL,
        permissions: 0o600
    )
    try write(
        Data(
            privateKey.publicKey.rawRepresentation
                .base64EncodedString().utf8
        ),
        to: publicKeyURL,
        permissions: 0o644
    )
    print("Created Ed25519 license signing keypair.")
}

private func issue(_ arguments: Arguments) throws {
    let featureValues = try arguments.required("features")
        .split(separator: ",")
        .map(String.init)
    let features = try featureValues.map { rawValue in
        guard let feature = CommercialFeature(rawValue: rawValue) else {
            throw LicenseToolError.invalidOption(
                "Unknown commercial feature: \(rawValue)"
            )
        }
        return feature
    }
    guard
        let edition = LicenseEdition(
            rawValue: try arguments.required("edition")
        )
    else {
        throw LicenseToolError.invalidOption("Invalid license edition.")
    }
    guard
        let maximumBuild = Int(
            try arguments.required("maximum-build")
        ),
        let maximumDevices = Int(
            try arguments.required("maximum-devices")
        )
    else {
        throw LicenseToolError.invalidOption(
            "Build and device limits must be integers."
        )
    }

    let payload = LicenseReceiptPayload(
        productIdentifier: try arguments.required("product"),
        licenseID: try arguments.required("license-id"),
        activationID: try arguments.required("activation-id"),
        deviceIdentifier: try arguments.required("device-id"),
        edition: edition,
        features: features,
        issuedAt: try parseDate(
            arguments.required("issued-at"),
            option: "issued-at"
        ),
        verificationDueAt: try parseDate(
            arguments.required("verification-due-at"),
            option: "verification-due-at"
        ),
        offlineGraceEndsAt: try parseDate(
            arguments.required("offline-grace-ends-at"),
            option: "offline-grace-ends-at"
        ),
        maximumBuild: maximumBuild,
        maximumDevices: maximumDevices
    )
    let privateKey = try readBase64Key(
        at: arguments.required("private-key"),
        expectedBytes: 32
    )
    let receipt = try LicenseReceiptCodec.sign(
        payload: payload,
        privateKey: privateKey
    )
    try write(
        receipt,
        to: arguments.required("output"),
        permissions: 0o600
    )
    print("Issued signed OpenWhisper license receipt.")
}

private func verify(_ arguments: Arguments) throws {
    let publicKey = try readBase64Key(
        at: arguments.required("public-key"),
        expectedBytes: 32
    )
    let receipt = try Data(
        contentsOf: URL(
            fileURLWithPath: arguments.required("receipt")
        ),
        options: [.mappedIfSafe]
    )
    let currentBuildValue = try arguments.required("current-build")
    guard
        let currentBuild = Int(currentBuildValue),
        currentBuild > 0
    else {
        throw LicenseToolError.invalidOption(
            "Current build must be a positive integer."
        )
    }
    let now = try parseDate(
        arguments.required("now"),
        option: "now"
    )
    let store = InMemoryLicenseReceiptStore(data: receipt)
    let deviceStore = InMemoryLicenseDeviceIdentifierStore(
        identifier: try arguments.required("device-id")
    )
    let manager = LicenseManager(
        configuration: LicenseRuntimeConfiguration(
            productIdentifier: try arguments.required("product"),
            currentBuild: currentBuild,
            previewEnabled: false,
            publicKey: publicKey
        ),
        receiptStore: store,
        deviceStore: deviceStore
    )
    let snapshot = manager.snapshot(now: now)
    guard snapshot.state == .active || snapshot.state == .offlineGrace else {
        throw LicenseToolError.invalidOption(
            "License does not grant access: \(snapshot.state.rawValue)"
        )
    }
    print(
        "License verified: \(snapshot.state.rawValue), "
            + "edition=\(snapshot.edition?.rawValue ?? "unknown"), "
            + "features=\(snapshot.enabledFeatures.map(\.rawValue).sorted().joined(separator: ","))"
    )
}

do {
    let arguments = try Arguments(
        Array(CommandLine.arguments.dropFirst())
    )
    switch arguments.command {
    case "generate-keypair":
        try generateKeypair(arguments)
    case "issue":
        try issue(arguments)
    case "verify":
        try verify(arguments)
    default:
        throw LicenseToolError.usage(Arguments.usage)
    }
} catch {
    fputs("OpenWhisperLicenseTool: \(error.localizedDescription)\n", stderr)
    exit(1)
}
