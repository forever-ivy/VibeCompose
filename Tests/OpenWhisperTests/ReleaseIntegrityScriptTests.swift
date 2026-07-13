import Foundation
import CryptoKit
import Testing

@Test
func strictEnvironmentLoaderAcceptsDataWithoutExecutingIt() throws {
    let root = repositoryRoot()
    let loaderURL = root.appendingPathComponent("scripts/lib/load_env.sh")
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenWhisperReleaseTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let safeURL = temporaryDirectory.appendingPathComponent("safe.env")
    try "OPENWHISPER_APP_NAME=OpenWhisper\n".write(
        to: safeURL,
        atomically: true,
        encoding: .utf8
    )

    let safeResult = try runBash(
        """
        source "$1"
        load_env_file "$2" OPENWHISPER_APP_NAME
        printf '%s' "$OPENWHISPER_APP_NAME"
        """,
        arguments: [loaderURL.path, safeURL.path]
    )
    #expect(safeResult.status == 0)
    #expect(safeResult.stdout == "OpenWhisper")

    let markerURL = temporaryDirectory.appendingPathComponent("executed")
    let maliciousURL = temporaryDirectory.appendingPathComponent("malicious.env")
    try "OPENWHISPER_APP_NAME=$(touch \(markerURL.path))\n".write(
        to: maliciousURL,
        atomically: true,
        encoding: .utf8
    )

    let maliciousResult = try runBash(
        """
        source "$1"
        load_env_file "$2" OPENWHISPER_APP_NAME
        """,
        arguments: [loaderURL.path, maliciousURL.path]
    )
    #expect(maliciousResult.status != 0)
    #expect(FileManager.default.fileExists(atPath: markerURL.path) == false)
}

@Test
func packagingAndInstallationScriptsKeepReleaseIntegrityFailClosed() throws {
    let root = repositoryRoot()
    let packageScript = try String(
        contentsOf: root.appendingPathComponent("scripts/package_app.sh"),
        encoding: .utf8
    )
    let installScript = try String(
        contentsOf: root.appendingPathComponent("scripts/install_app.sh"),
        encoding: .utf8
    )

    #expect(packageScript.contains("load_product_env \"$PRODUCT_ENV\""))
    #expect(packageScript.contains("load_version_env \"$VERSION_ENV\""))
    #expect(packageScript.contains("verify_repository_hygiene.py"))
    #expect(!packageScript.contains("source \"$PRODUCT_ENV\""))
    #expect(!packageScript.contains("source \"$VERSION_ENV\""))
    #expect(packageScript.contains("OPENWHISPER_REQUIRE_DEVELOPER_ID"))
    #expect(packageScript.contains("notarytool submit"))
    #expect(packageScript.contains("stapler validate"))
    #expect(packageScript.contains("spctl --assess"))
    #expect(packageScript.contains("SHA256SUMS"))
    #expect(packageScript.contains("generate_release_metadata.sh"))
    #expect(packageScript.contains("codesign --verify --deep --strict"))
    #expect(packageScript.contains("Sparkle.framework"))
    #expect(packageScript.contains("@executable_path/../Frameworks"))
    #expect(packageScript.contains("OPENWHISPER_SPARKLE_FEED_URL"))
    #expect(packageScript.contains("OPENWHISPER_SPARKLE_PUBLIC_ED_KEY"))
    #expect(packageScript.contains("OPENWHISPER_CAPABILITY_POLICY_URL"))
    #expect(packageScript.contains("OPENWHISPER_CAPABILITY_PUBLIC_ED_KEY"))
    #expect(packageScript.contains("OPENWHISPER_LICENSE_PUBLIC_ED_KEY"))
    #expect(packageScript.contains("OPENWHISPER_PRO_PREVIEW_ENABLED"))
    #expect(packageScript.contains("OWCapabilityPolicyURL"))
    #expect(packageScript.contains("OWCapabilityPublicEDKey"))
    #expect(packageScript.contains("OWLicensePublicEDKey"))
    #expect(packageScript.contains("OWProPreviewEnabled"))
    #expect(packageScript.contains("sign_sparkle_components"))
    #expect(packageScript.contains("enable_adhoc_library_validation_exception"))
    #expect(packageScript.contains("plutil -lint \"$ENTITLEMENTS_FILE\""))
    #expect(
        packageScript.contains(
            "com.apple.security.cs.disable-library-validation"
        )
    )

    #expect(installScript.contains("STAGED_APP="))
    #expect(installScript.contains("BACKUP_APP="))
    #expect(installScript.contains("mv \"$TARGET_APP\" \"$BACKUP_APP\""))
    #expect(installScript.contains("mv \"$STAGED_APP\" \"$TARGET_APP\""))
    #expect(installScript.contains("restoring the previous app"))
    #expect(installScript.contains("codesign --verify --deep --strict"))
    #expect(installScript.contains("CFBundleVersion"))
    #expect(installScript.contains("TeamIdentifier=$EXPECTED_TEAM_ID"))
    #expect(installScript.contains("Developer ID Application:"))
}

@Test
func releaseMetadataGeneratorProducesExactArtifactContract() throws {
    let root = repositoryRoot()
    let generatorURL = root.appendingPathComponent(
        "scripts/generate_release_metadata.swift"
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "OpenWhisperReleaseMetadataTests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let zipURL = temporaryDirectory.appendingPathComponent("OpenWhisper.zip")
    let dmgURL = temporaryDirectory.appendingPathComponent("OpenWhisper.dmg")
    let outputURL = temporaryDirectory.appendingPathComponent("manifest.json")
    let zipData = Data("zip-artifact".utf8)
    let dmgData = Data("dmg-artifact".utf8)
    try zipData.write(to: zipURL)
    try dmgData.write(to: dmgURL)

    let result = try runBash(
        """
        swift "$1" \
          --output "$2" \
          --app-name OpenWhisper \
          --bundle-id app.openwhisper.mac \
          --repository forever-ivy/openwhisper \
          --minimum-macos 13.0 \
          --version 0.1.0 \
          --build 1 \
          --architecture arm64 \
          --zip "$3" \
          --dmg "$4" \
          --zip-url https://example.invalid/OpenWhisper.zip \
          --dmg-url https://example.invalid/OpenWhisper.dmg \
          --generated-at 2026-07-13T00:00:00Z
        """,
        arguments: [
            generatorURL.path,
            outputURL.path,
            zipURL.path,
            dmgURL.path,
        ]
    )
    #expect(result.status == 0)

    let object = try #require(
        try JSONSerialization.jsonObject(
            with: Data(contentsOf: outputURL)
        ) as? [String: Any]
    )
    #expect(object["schemaVersion"] as? Int == 1)
    let release = try #require(object["release"] as? [String: Any])
    #expect(release["version"] as? String == "0.1.0")
    #expect(release["build"] as? String == "1")
    #expect(release["tag"] as? String == "v0.1.0")
    let artifacts = try #require(object["artifacts"] as? [[String: Any]])
    #expect(artifacts.count == 2)
    #expect(artifacts[0]["kind"] as? String == "zip")
    #expect(artifacts[0]["byteCount"] as? Int == zipData.count)
    #expect(
        artifacts[0]["sha256"] as? String
            == SHA256.hash(data: zipData).map {
                String(format: "%02x", $0)
            }
            .joined()
    )

    let attributes = try FileManager.default.attributesOfItem(
        atPath: outputURL.path
    )
    #expect(
        (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
    )

    let insecureResult = try runBash(
        """
        swift "$1" \
          --output "$2" \
          --app-name OpenWhisper \
          --bundle-id app.openwhisper.mac \
          --repository forever-ivy/openwhisper \
          --minimum-macos 13.0 \
          --version 0.1.0 \
          --build 1 \
          --architecture arm64 \
          --zip "$3" \
          --dmg "$4" \
          --zip-url http://example.invalid/OpenWhisper.zip \
          --dmg-url https://example.invalid/OpenWhisper.dmg
        """,
        arguments: [
            generatorURL.path,
            outputURL.path,
            zipURL.path,
            dmgURL.path,
        ]
    )
    #expect(insecureResult.status != 0)
}

@Test
func sparkleAppcastVerifierMatchesManifestArchiveAndPublicKey() throws {
    let root = repositoryRoot()
    let verifierURL = root.appendingPathComponent(
        "scripts/verify_sparkle_appcast.swift"
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "OpenWhisperSparkleVerificationTests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let archiveURL = temporaryDirectory.appendingPathComponent(
        "OpenWhisper-0.1.0-macos-arm64.zip"
    )
    let manifestURL = temporaryDirectory.appendingPathComponent(
        "release-manifest.json"
    )
    let appcastURL = temporaryDirectory.appendingPathComponent("appcast.xml")
    let archiveData = Data("signed-openwhisper-update".utf8)
    try archiveData.write(to: archiveURL)

    let privateKey = Curve25519.Signing.PrivateKey()
    let signature = try privateKey.signature(for: archiveData)
    let publicKey = privateKey.publicKey.rawRepresentation
        .base64EncodedString()
    let sha256 = SHA256.hash(data: archiveData)
        .map { String(format: "%02x", $0) }
        .joined()
    let downloadURL = "https://example.invalid/OpenWhisper-0.1.0-macos-arm64.zip"

    let manifest: [String: Any] = [
        "release": [
            "version": "0.1.0",
            "build": "1",
        ],
        "artifacts": [
            [
                "fileName": archiveURL.lastPathComponent,
                "kind": "zip",
                "byteCount": archiveData.count,
                "sha256": sha256,
                "downloadURL": downloadURL,
            ],
        ],
    ]
    try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
    ).write(to: manifestURL)
    try """
    <?xml version="1.0"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <sparkle:version>1</sparkle:version>
          <enclosure
            url="\(downloadURL)"
            length="\(archiveData.count)"
            type="application/octet-stream"
            sparkle:edSignature="\(signature.base64EncodedString())"/>
        </item>
      </channel>
    </rss>
    """.write(to: appcastURL, atomically: true, encoding: .utf8)

    let validResult = try runBash(
        """
        swift "$1" \
          --appcast "$2" \
          --archive "$3" \
          --manifest "$4" \
          --public-key "$5"
        """,
        arguments: [
            verifierURL.path,
            appcastURL.path,
            archiveURL.path,
            manifestURL.path,
            publicKey,
        ]
    )
    #expect(validResult.status == 0)
    #expect(validResult.stdout.contains("signature verified"))

    try Data("tampered-update".utf8).write(to: archiveURL)
    let tamperedResult = try runBash(
        """
        swift "$1" \
          --appcast "$2" \
          --archive "$3" \
          --manifest "$4" \
          --public-key "$5"
        """,
        arguments: [
            verifierURL.path,
            appcastURL.path,
            archiveURL.path,
            manifestURL.path,
            publicKey,
        ]
    )
    #expect(tamperedResult.status != 0)
}

@Test
func releaseScriptsKeepCaskAndUpdaterGateFailClosed() throws {
    let root = repositoryRoot()
    let cask = try String(
        contentsOf: root.appendingPathComponent(
            "packaging/homebrew/Casks/openwhisper.rb"
        ),
        encoding: .utf8
    )
    let updateCaskScript = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/update_homebrew_cask.sh"
        ),
        encoding: .utf8
    )
    let releaseGate = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_release_gate.sh"
        ),
        encoding: .utf8
    )
    let updaterDecision = try String(
        contentsOf: root.appendingPathComponent(
            "docs/engineering/updater.md"
        ),
        encoding: .utf8
    )
    let appcastScript = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/generate_sparkle_appcast.sh"
        ),
        encoding: .utf8
    )
    let capabilityPolicyGenerator = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/generate_provider_capability_policy.swift"
        ),
        encoding: .utf8
    )
    let capabilityPolicyVerifier = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_provider_capability_policy.swift"
        ),
        encoding: .utf8
    )
    let packageManifest = try String(
        contentsOf: root.appendingPathComponent("Package.swift"),
        encoding: .utf8
    )
    let packageResolution = try String(
        contentsOf: root.appendingPathComponent("Package.resolved"),
        encoding: .utf8
    )

    #expect(!cask.contains("sha256 :no_check"))
    #expect(
        cask.contains(
            "sha256 \"0000000000000000000000000000000000000000000000000000000000000000\""
        )
    )
    #expect(updateCaskScript.contains("^[0-9a-f]{64}$"))
    #expect(updateCaskScript.contains("must not use the unreleased fail-closed value"))
    #expect(releaseGate.contains("Developer ID Application:"))
    #expect(releaseGate.contains("verify_repository_hygiene.py"))
    #expect(releaseGate.contains("OWLicensePublicEDKey"))
    #expect(releaseGate.contains("OWProPreviewEnabled"))
    #expect(
        releaseGate.contains(
            "Commercial release must disable the private Pro preview."
        )
    )
    #expect(releaseGate.contains("TeamIdentifier=$EXPECTED_TEAM_ID"))
    #expect(releaseGate.contains("stapler validate"))
    #expect(releaseGate.contains("spctl --assess"))
    #expect(releaseGate.contains("SUFeedURL"))
    #expect(releaseGate.contains("SUPublicEDKey"))
    #expect(releaseGate.contains("Sparkle.framework"))
    #expect(releaseGate.contains("sparkle:edSignature"))
    #expect(releaseGate.contains("OPENWHISPER_SPARKLE_APPCAST_PATH"))
    #expect(releaseGate.contains("OWCapabilityPolicyURL"))
    #expect(releaseGate.contains("OWCapabilityPublicEDKey"))
    #expect(releaseGate.contains("OPENWHISPER_CAPABILITY_POLICY_PATH"))
    #expect(releaseGate.contains("verify_provider_capability_policy.swift"))
    #expect(
        releaseGate.contains(
            "Commercial release must not disable hardened-runtime library validation."
        )
    )
    #expect(appcastScript.contains("generate_appcast"))
    #expect(appcastScript.contains("--ed-key-file"))
    #expect(appcastScript.contains("PRIVATE_KEY_MODE"))
    #expect(appcastScript.contains("sparkle:edSignature"))
    #expect(appcastScript.contains("verify_sparkle_appcast.swift"))
    #expect(releaseGate.contains("verify_sparkle_appcast.swift"))
    #expect(
        capabilityPolicyGenerator.contains(
            "OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE"
        )
    )
    #expect(capabilityPolicyGenerator.contains("Curve25519.Signing.PrivateKey"))
    #expect(capabilityPolicyGenerator.contains("31 * 24 * 60 * 60"))
    #expect(capabilityPolicyVerifier.contains("isValidSignature"))
    #expect(capabilityPolicyVerifier.contains("managedTranscription"))
    #expect(capabilityPolicyVerifier.contains("chatGPTTextPolish"))
    #expect(packageManifest.contains("exact: \"2.9.4\""))
    #expect(packageManifest.contains(".product(name: \"Sparkle\""))
    #expect(packageResolution.contains("\"version\" : \"2.9.4\""))
    #expect(updaterDecision.contains("Sparkle 2"))
    #expect(updaterDecision.contains("integrated in the private alpha"))
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func runBash(
    _ command: String,
    arguments: [String]
) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command, "_"] + arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    return (
        process.terminationStatus,
        String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "",
        String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    )
}
