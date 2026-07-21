import Foundation
import Testing
@testable import OpenWhisper

@Test
func thirdPartyLicenseCatalogCoversResolvedDependencies() throws {
    let root = thirdPartyLicenseRepositoryRoot()
    let documents = try ThirdPartyLicenseCatalog.load(
        resourceRootURL: root.appendingPathComponent(
            "Sources/OpenWhisper/Resources",
            isDirectory: true
        )
    )
    let resolvedData = try Data(
        contentsOf: root.appendingPathComponent("Package.resolved")
    )
    let resolvedObject = try #require(
        JSONSerialization.jsonObject(with: resolvedData)
            as? [String: Any]
    )
    let pins = try #require(
        resolvedObject["pins"] as? [[String: Any]]
    )
    let resolvedIdentities = Set(
        pins.compactMap { $0["identity"] as? String }
    )

    let packageDocuments = documents.filter {
        $0.entry.sourceKind != .vendored
    }
    #expect(Set(packageDocuments.map(\.entry.identity)) == resolvedIdentities)
    #expect(
        documents.map(\.entry.identity)
            == ["permissionflow", "sparkle", "edgeglow"]
    )
    #expect(documents.allSatisfy { !$0.licenseText.isEmpty })
    #expect(
        documents.first(where: { $0.id == "sparkle" })?
            .licenseText.contains("EXTERNAL LICENSES") == true
    )
    #expect(
        documents.first(where: { $0.id == "edgeglow" })?
            .entry.revision
            == "d39d0471a25af97d8de077591f69f938efa8bea8"
    )
}

@Test
func thirdPartyLicenseCatalogRejectsTamperedLicenseText() throws {
    let fixture = try makeThirdPartyLicenseFixture()
    defer {
        try? FileManager.default.removeItem(at: fixture)
    }
    let licenseURL = fixture.appendingPathComponent(
        "Legal/ThirdPartyLicenses/PermissionFlow-LICENSE.txt"
    )
    try Data("tampered".utf8).write(to: licenseURL)

    #expect(
        throws: ThirdPartyLicenseCatalogError.checksumMismatch(
            "permissionflow"
        )
    ) {
        try ThirdPartyLicenseCatalog.load(resourceRootURL: fixture)
    }
}

@Test
func thirdPartyLicenseCatalogRejectsSymlinkedLicense() throws {
    let fixture = try makeThirdPartyLicenseFixture()
    defer {
        try? FileManager.default.removeItem(at: fixture)
    }
    let licenseURL = fixture.appendingPathComponent(
        "Legal/ThirdPartyLicenses/PermissionFlow-LICENSE.txt"
    )
    let targetURL = fixture.appendingPathComponent("outside-license.txt")
    try Data("outside".utf8).write(to: targetURL)
    try FileManager.default.removeItem(at: licenseURL)
    try FileManager.default.createSymbolicLink(
        at: licenseURL,
        withDestinationURL: targetURL
    )

    #expect(
        throws: ThirdPartyLicenseCatalogError.unreadableLicense(
            "permissionflow"
        )
    ) {
        try ThirdPartyLicenseCatalog.load(resourceRootURL: fixture)
    }
}

@Test
func thirdPartyLicenseCatalogReportsMissingLicense() throws {
    let fixture = try makeThirdPartyLicenseFixture()
    defer {
        try? FileManager.default.removeItem(at: fixture)
    }
    let licenseURL = fixture.appendingPathComponent(
        "Legal/ThirdPartyLicenses/PermissionFlow-LICENSE.txt"
    )
    try FileManager.default.removeItem(at: licenseURL)

    #expect(
        throws: ThirdPartyLicenseCatalogError.missingLicense(
            "permissionflow"
        )
    ) {
        try ThirdPartyLicenseCatalog.load(resourceRootURL: fixture)
    }
}

@Test
func dependencyLicenseGateIsPartOfChecksPackagingAndRelease() throws {
    let root = thirdPartyLicenseRepositoryRoot()
    for path in [
        "scripts/check.sh",
        "scripts/package_app.sh",
        "scripts/check_packaged_app.sh",
        "scripts/verify_release_gate.sh",
    ] {
        let source = try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
        #expect(source.contains("verify_dependency_licenses.swift"))
    }

    let settingsSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )
    #expect(settingsSource.contains("View Third-Party Licenses…"))
    #expect(settingsSource.contains("ThirdPartyLicensesView"))
}

private func makeThirdPartyLicenseFixture() throws -> URL {
    let root = thirdPartyLicenseRepositoryRoot()
    let source = root.appendingPathComponent(
        "Sources/OpenWhisper/Resources",
        isDirectory: true
    )
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "OpenWhisperThirdPartyLicenses-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.copyItem(at: source, to: fixture)
    return fixture
}

private func thirdPartyLicenseRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
