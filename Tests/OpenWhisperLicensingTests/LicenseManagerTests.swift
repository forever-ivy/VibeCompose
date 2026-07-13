import CryptoKit
import Foundation
import Testing
@testable import OpenWhisperLicensing

private let testNow = Date(timeIntervalSince1970: 1_800_000_000)
private let testDeviceIdentifier =
    "11111111-2222-3333-4444-555555555555"

private func testPayload(
    deviceIdentifier: String = testDeviceIdentifier,
    features: [CommercialFeature] = [.voiceModes, .quickAdd],
    verificationDueAt: Date = testNow.addingTimeInterval(30 * 24 * 60 * 60),
    offlineGraceEndsAt: Date = testNow.addingTimeInterval(60 * 24 * 60 * 60),
    maximumBuild: Int = 100
) -> LicenseReceiptPayload {
    LicenseReceiptPayload(
        productIdentifier: "app.openwhisper.mac",
        licenseID: "license-test-001",
        activationID: "activation-test-001",
        deviceIdentifier: deviceIdentifier,
        edition: .founderPro,
        features: features,
        issuedAt: testNow.addingTimeInterval(-60),
        verificationDueAt: verificationDueAt,
        offlineGraceEndsAt: offlineGraceEndsAt,
        maximumBuild: maximumBuild,
        maximumDevices: 3
    )
}

private func signedReceipt(
    payload: LicenseReceiptPayload = testPayload(),
    privateKey: Curve25519.Signing.PrivateKey
) throws -> Data {
    try LicenseReceiptCodec.sign(
        payload: payload,
        privateKey: privateKey.rawRepresentation
    )
}

private func manager(
    receipt: Data?,
    publicKey: Data?,
    currentBuild: Int = 1,
    previewEnabled: Bool = false,
    deviceIdentifier: String = testDeviceIdentifier
) -> (
    LicenseManager,
    InMemoryLicenseReceiptStore,
    InMemoryLicenseDeviceIdentifierStore
) {
    let receiptStore = InMemoryLicenseReceiptStore(data: receipt)
    let deviceStore = InMemoryLicenseDeviceIdentifierStore(
        identifier: deviceIdentifier
    )
    return (
        LicenseManager(
            configuration: LicenseRuntimeConfiguration(
                productIdentifier: "app.openwhisper.mac",
                currentBuild: currentBuild,
                previewEnabled: previewEnabled,
                publicKey: publicKey
            ),
            receiptStore: receiptStore,
            deviceStore: deviceStore
        ),
        receiptStore,
        deviceStore
    )
}

@Test
func signedLicenseEnablesOnlyItsDeclaredFeatures() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let receipt = try signedReceipt(privateKey: privateKey)
    let (manager, _, _) = manager(
        receipt: receipt,
        publicKey: privateKey.publicKey.rawRepresentation
    )

    let snapshot = manager.snapshot(now: testNow)

    #expect(snapshot.state == .active)
    #expect(snapshot.edition == .founderPro)
    #expect(snapshot.allows(.voiceModes))
    #expect(snapshot.allows(.quickAdd))
    #expect(!snapshot.allows(.advancedHistory))
    #expect(snapshot.maximumDevices == 3)
}

@Test
func licenseUsesBoundedOfflineGraceThenRequiresVerification() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let payload = testPayload(
        verificationDueAt: testNow.addingTimeInterval(-60),
        offlineGraceEndsAt: testNow.addingTimeInterval(60)
    )
    let receipt = try signedReceipt(
        payload: payload,
        privateKey: privateKey
    )
    let (manager, _, _) = manager(
        receipt: receipt,
        publicKey: privateKey.publicKey.rawRepresentation
    )

    let grace = manager.snapshot(now: testNow)
    let expired = manager.snapshot(
        now: testNow.addingTimeInterval(120)
    )

    #expect(grace.state == .offlineGrace)
    #expect(grace.allows(.voiceModes))
    #expect(expired.state == .verificationRequired)
    #expect(!expired.allows(.voiceModes))
}

@Test
func newerBuildDoesNotDestroyPerpetualOlderBuildReceipt() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let receipt = try signedReceipt(
        payload: testPayload(maximumBuild: 10),
        privateKey: privateKey
    )
    let (manager, store, _) = manager(
        receipt: receipt,
        publicKey: privateKey.publicKey.rawRepresentation,
        currentBuild: 11
    )

    let snapshot = manager.snapshot(now: testNow)

    #expect(snapshot.state == .updateEntitlementExpired)
    #expect(snapshot.maximumBuild == 10)
    #expect(!snapshot.allows(.voiceModes))
    #expect(try store.loadReceiptData() == receipt)
}

@Test
func deviceBoundReceiptCannotBeInstalledOnAnotherDevice() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let receipt = try signedReceipt(privateKey: privateKey)
    let (manager, store, _) = manager(
        receipt: nil,
        publicKey: privateKey.publicKey.rawRepresentation,
        deviceIdentifier:
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )

    #expect(throws: LicenseValidationError.deviceMismatch) {
        _ = try manager.installReceipt(receipt, now: testNow)
    }
    #expect(try store.loadReceiptData() == nil)
}

@Test
func tamperedReceiptDoesNotReplaceWorkingLicense() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let validReceipt = try signedReceipt(privateKey: privateKey)
    let (manager, store, _) = manager(
        receipt: validReceipt,
        publicKey: privateKey.publicKey.rawRepresentation
    )
    var tampered = validReceipt
    tampered[tampered.index(before: tampered.endIndex)] ^= 0x01

    #expect(throws: (any Error).self) {
        _ = try manager.installReceipt(tampered, now: testNow)
    }
    #expect(try store.loadReceiptData() == validReceipt)
    #expect(manager.snapshot(now: testNow).state == .active)
}

@Test
func duplicateFeaturesAndExcessiveGraceFailClosed() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let duplicateReceipt = try signedReceipt(
        payload: testPayload(
            features: [.voiceModes, .voiceModes]
        ),
        privateKey: privateKey
    )

    #expect(throws: LicenseValidationError.duplicateFeatures) {
        _ = try LicenseReceiptCodec.verify(
            duplicateReceipt,
            publicKey: privateKey.publicKey.rawRepresentation,
            expectedProductIdentifier: "app.openwhisper.mac",
            expectedDeviceIdentifier: testDeviceIdentifier,
            now: testNow
        )
    }

    let excessiveGraceReceipt = try signedReceipt(
        payload: testPayload(
            verificationDueAt: testNow.addingTimeInterval(60),
            offlineGraceEndsAt: testNow.addingTimeInterval(
                LicenseManager.maximumOfflineGraceSeconds + 120
            )
        ),
        privateKey: privateKey
    )
    #expect(throws: LicenseValidationError.excessiveOfflineGrace) {
        _ = try LicenseReceiptCodec.verify(
            excessiveGraceReceipt,
            publicKey: privateKey.publicKey.rawRepresentation,
            expectedProductIdentifier: "app.openwhisper.mac",
            expectedDeviceIdentifier: testDeviceIdentifier,
            now: testNow
        )
    }
}

@Test
func privateAlphaPreviewIsExplicitAndDoesNotNeedAReceipt() {
    let (manager, _, _) = manager(
        receipt: nil,
        publicKey: nil,
        previewEnabled: true
    )

    let snapshot = manager.snapshot(now: testNow)

    #expect(snapshot.state == .preview)
    #expect(
        snapshot.enabledFeatures
            == Set(CommercialFeature.allCases)
    )
}

@Test
func resetRemovesReceiptAndRotatesTheApplicationDeviceIdentifier() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let receipt = try signedReceipt(privateKey: privateKey)
    let (manager, receiptStore, _) = manager(
        receipt: receipt,
        publicKey: privateKey.publicKey.rawRepresentation
    )

    #expect(manager.snapshot(now: testNow).state == .active)
    let previousIdentifier = try manager.deviceIdentifier()

    try manager.reset()

    #expect(try receiptStore.loadReceiptData() == nil)
    #expect(manager.snapshot(now: testNow).state == .community)
    let replacementIdentifier = try manager.deviceIdentifier()
    #expect(replacementIdentifier != previousIdentifier)
    #expect(UUID(uuidString: replacementIdentifier) != nil)
}

@Test
func runtimeConfigurationParsesFailClosedInfoPlistValues() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let configuration = try LicenseRuntimeConfiguration(
        infoDictionary: [
            "CFBundleIdentifier": "app.openwhisper.mac",
            "CFBundleVersion": "42",
            "OWProPreviewEnabled": false,
            "OWLicensePublicEDKey":
                privateKey.publicKey.rawRepresentation
                    .base64EncodedString(),
        ]
    )

    #expect(configuration.productIdentifier == "app.openwhisper.mac")
    #expect(configuration.currentBuild == 42)
    #expect(!configuration.previewEnabled)
    #expect(
        configuration.publicKey
            == privateKey.publicKey.rawRepresentation
    )

    #expect(throws: LicenseValidationError.invalidPublicKey) {
        _ = try LicenseRuntimeConfiguration(
            infoDictionary: [
                "CFBundleIdentifier": "app.openwhisper.mac",
                "CFBundleVersion": "42",
                "OWLicensePublicEDKey": "not-a-key",
            ]
        )
    }
}

@Test
func keychainLicenseStoresRoundTripWithIsolatedServices() throws {
    let suffix = UUID().uuidString
    let receiptStore = KeychainLicenseReceiptStore(
        service: "app.openwhisper.tests.license.\(suffix)"
    )
    let deviceStore = KeychainLicenseDeviceIdentifierStore(
        service: "app.openwhisper.tests.device.\(suffix)"
    )
    defer {
        try? receiptStore.deleteReceiptData()
        try? deviceStore.deleteDeviceIdentifier()
    }

    let receipt = Data("signed-license-placeholder".utf8)
    try receiptStore.saveReceiptData(receipt)
    #expect(try receiptStore.loadReceiptData() == receipt)

    let firstIdentifier = try deviceStore
        .loadOrCreateDeviceIdentifier()
    let secondIdentifier = try deviceStore
        .loadOrCreateDeviceIdentifier()
    #expect(firstIdentifier == secondIdentifier)
    #expect(UUID(uuidString: firstIdentifier) != nil)

    try receiptStore.deleteReceiptData()
    try deviceStore.deleteDeviceIdentifier()
    #expect(try receiptStore.loadReceiptData() == nil)
}
