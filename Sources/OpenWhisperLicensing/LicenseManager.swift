import CryptoKit
import Foundation

public struct LicenseRuntimeConfiguration:
    Equatable,
    Sendable
{
    public let productIdentifier: String
    public let currentBuild: Int
    public let previewEnabled: Bool
    public let publicKey: Data?

    public init(
        productIdentifier: String,
        currentBuild: Int,
        previewEnabled: Bool,
        publicKey: Data?
    ) {
        self.productIdentifier = productIdentifier
        self.currentBuild = currentBuild
        self.previewEnabled = previewEnabled
        self.publicKey = publicKey
    }

    public init(infoDictionary: [String: Any]) throws {
        guard
            let productIdentifier =
                infoDictionary["CFBundleIdentifier"] as? String,
            !productIdentifier.isEmpty
        else {
            throw LicenseValidationError.configurationMissing
        }

        let currentBuild: Int
        if let value = infoDictionary["CFBundleVersion"] as? String,
           let parsed = Int(value)
        {
            currentBuild = parsed
        } else if let value = infoDictionary["CFBundleVersion"] as? NSNumber {
            currentBuild = value.intValue
        } else {
            throw LicenseValidationError.configurationMissing
        }
        guard currentBuild > 0 else {
            throw LicenseValidationError.invalidBuild
        }

        let previewEnabled =
            infoDictionary["OWProPreviewEnabled"] as? Bool ?? false
        let publicKey: Data?
        if let encoded = infoDictionary["OWLicensePublicEDKey"] as? String,
           !encoded.isEmpty
        {
            guard
                let decoded = Data(base64Encoded: encoded),
                decoded.count == 32
            else {
                throw LicenseValidationError.invalidPublicKey
            }
            publicKey = decoded
        } else {
            publicKey = nil
        }

        self.init(
            productIdentifier: productIdentifier,
            currentBuild: currentBuild,
            previewEnabled: previewEnabled,
            publicKey: publicKey
        )
    }
}

public protocol CommercialLicenseManaging: Sendable {
    func snapshot(now: Date) -> LicenseSnapshot
    func installReceipt(_ data: Data, now: Date) throws -> LicenseSnapshot
    func removeReceipt() throws
    func reset() throws
    func deviceIdentifier() throws -> String
    func canInstallReceipts() -> Bool
}

public extension CommercialLicenseManaging {
    func snapshot() -> LicenseSnapshot {
        snapshot(now: Date())
    }

    func installReceipt(_ data: Data) throws -> LicenseSnapshot {
        try installReceipt(data, now: Date())
    }
}

public final class LicenseManager:
    CommercialLicenseManaging,
    @unchecked Sendable
{
    public static let maximumReceiptBytes = 64 * 1024
    public static let maximumPayloadBytes = 16 * 1024
    public static let maximumOfflineGraceSeconds: TimeInterval =
        90 * 24 * 60 * 60
    public static let allowedFutureClockSkewSeconds: TimeInterval = 5 * 60

    private let configuration: LicenseRuntimeConfiguration
    private let receiptStore: any LicenseReceiptPersisting
    private let deviceStore: any LicenseDeviceIdentifying

    public init(
        configuration: LicenseRuntimeConfiguration,
        receiptStore: any LicenseReceiptPersisting,
        deviceStore: any LicenseDeviceIdentifying
    ) {
        self.configuration = configuration
        self.receiptStore = receiptStore
        self.deviceStore = deviceStore
    }

    public func snapshot(now: Date) -> LicenseSnapshot {
        if configuration.previewEnabled {
            return .preview
        }

        let receiptData: Data
        do {
            guard let stored = try receiptStore.loadReceiptData() else {
                return .community
            }
            receiptData = stored
        } catch {
            return LicenseSnapshot(state: .invalid)
        }

        guard let publicKey = configuration.publicKey else {
            return LicenseSnapshot(state: .configurationError)
        }

        let deviceIdentifier: String
        do {
            deviceIdentifier = try deviceStore
                .loadOrCreateDeviceIdentifier()
        } catch {
            return LicenseSnapshot(state: .invalid)
        }

        do {
            let payload = try LicenseReceiptCodec.verify(
                receiptData,
                publicKey: publicKey,
                expectedProductIdentifier:
                    configuration.productIdentifier,
                expectedDeviceIdentifier: deviceIdentifier,
                now: now
            )
            return Self.snapshot(
                payload: payload,
                currentBuild: configuration.currentBuild,
                now: now
            )
        } catch LicenseValidationError.deviceMismatch {
            return LicenseSnapshot(state: .deviceMismatch)
        } catch {
            return LicenseSnapshot(state: .invalid)
        }
    }

    public func installReceipt(
        _ data: Data,
        now: Date
    ) throws -> LicenseSnapshot {
        guard let publicKey = configuration.publicKey else {
            throw LicenseValidationError.configurationMissing
        }
        let deviceIdentifier = try deviceStore
            .loadOrCreateDeviceIdentifier()
        _ = try LicenseReceiptCodec.verify(
            data,
            publicKey: publicKey,
            expectedProductIdentifier: configuration.productIdentifier,
            expectedDeviceIdentifier: deviceIdentifier,
            now: now
        )
        try receiptStore.saveReceiptData(data)
        return snapshot(now: now)
    }

    public func removeReceipt() throws {
        try receiptStore.deleteReceiptData()
    }

    public func reset() throws {
        var firstError: (any Error)?
        do {
            try receiptStore.deleteReceiptData()
        } catch {
            firstError = error
        }
        do {
            try deviceStore.deleteDeviceIdentifier()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    public func deviceIdentifier() throws -> String {
        try deviceStore.loadOrCreateDeviceIdentifier()
    }

    public func canInstallReceipts() -> Bool {
        configuration.publicKey != nil
    }

    private static func snapshot(
        payload: LicenseReceiptPayload,
        currentBuild: Int,
        now: Date
    ) -> LicenseSnapshot {
        let common = (
            edition: payload.edition,
            licenseID: payload.licenseID,
            activationID: payload.activationID,
            verificationDueAt: payload.verificationDueAt,
            offlineGraceEndsAt: payload.offlineGraceEndsAt,
            maximumBuild: payload.maximumBuild,
            maximumDevices: payload.maximumDevices
        )

        guard currentBuild <= payload.maximumBuild else {
            return LicenseSnapshot(
                state: .updateEntitlementExpired,
                edition: common.edition,
                licenseID: common.licenseID,
                activationID: common.activationID,
                verificationDueAt: common.verificationDueAt,
                offlineGraceEndsAt: common.offlineGraceEndsAt,
                maximumBuild: common.maximumBuild,
                maximumDevices: common.maximumDevices
            )
        }

        let state: LicenseAccessState
        if now <= payload.verificationDueAt {
            state = .active
        } else if now <= payload.offlineGraceEndsAt {
            state = .offlineGrace
        } else {
            state = .verificationRequired
        }

        return LicenseSnapshot(
            state: state,
            edition: common.edition,
            enabledFeatures: state == .active || state == .offlineGrace
                ? Set(payload.features)
                : [],
            licenseID: common.licenseID,
            activationID: common.activationID,
            verificationDueAt: common.verificationDueAt,
            offlineGraceEndsAt: common.offlineGraceEndsAt,
            maximumBuild: common.maximumBuild,
            maximumDevices: common.maximumDevices
        )
    }
}

public final class StaticLicenseManager:
    CommercialLicenseManaging,
    @unchecked Sendable
{
    private let value: LicenseSnapshot
    private let identifier: String

    public init(
        snapshot: LicenseSnapshot,
        deviceIdentifier: String =
            "00000000-0000-0000-0000-000000000000"
    ) {
        value = snapshot
        identifier = deviceIdentifier
    }

    public static let preview = StaticLicenseManager(snapshot: .preview)
    public static let community = StaticLicenseManager(snapshot: .community)

    public func snapshot(now: Date) -> LicenseSnapshot {
        value
    }

    public func installReceipt(
        _ data: Data,
        now: Date
    ) throws -> LicenseSnapshot {
        throw LicenseValidationError.configurationMissing
    }

    public func removeReceipt() throws {}
    public func reset() throws {}

    public func deviceIdentifier() throws -> String {
        identifier
    }

    public func canInstallReceipts() -> Bool {
        false
    }
}
