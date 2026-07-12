import Foundation
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
    #expect(!packageScript.contains("source \"$PRODUCT_ENV\""))
    #expect(!packageScript.contains("source \"$VERSION_ENV\""))
    #expect(packageScript.contains("OPENWHISPER_REQUIRE_DEVELOPER_ID"))
    #expect(packageScript.contains("notarytool submit"))
    #expect(packageScript.contains("stapler validate"))
    #expect(packageScript.contains("spctl --assess"))
    #expect(packageScript.contains("SHA256SUMS"))
    #expect(packageScript.contains("codesign --verify --deep --strict"))

    #expect(installScript.contains("STAGED_APP="))
    #expect(installScript.contains("BACKUP_APP="))
    #expect(installScript.contains("mv \"$TARGET_APP\" \"$BACKUP_APP\""))
    #expect(installScript.contains("mv \"$STAGED_APP\" \"$TARGET_APP\""))
    #expect(installScript.contains("restoring the previous app"))
    #expect(installScript.contains("codesign --verify --deep --strict"))
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
