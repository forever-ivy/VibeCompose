import Foundation

public enum CommercialFeature:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case voiceModes
    case quickAdd
    case projectTerminology
    case advancedHistory
    case commandMode
    case automation
    case multiDevice
}

public enum LicenseEdition:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case founderPro
    case pro
}

public enum LicenseAccessState:
    String,
    Codable,
    Sendable
{
    case community
    case preview
    case active
    case offlineGrace
    case verificationRequired
    case updateEntitlementExpired
    case deviceMismatch
    case invalid
    case configurationError
}

public struct LicenseReceiptPayload:
    Codable,
    Equatable,
    Sendable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let productIdentifier: String
    public let licenseID: String
    public let activationID: String
    public let deviceIdentifier: String
    public let edition: LicenseEdition
    public let features: [CommercialFeature]
    public let issuedAt: Date
    public let verificationDueAt: Date
    public let offlineGraceEndsAt: Date
    public let maximumBuild: Int
    public let maximumDevices: Int

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        productIdentifier: String,
        licenseID: String,
        activationID: String,
        deviceIdentifier: String,
        edition: LicenseEdition,
        features: [CommercialFeature],
        issuedAt: Date,
        verificationDueAt: Date,
        offlineGraceEndsAt: Date,
        maximumBuild: Int,
        maximumDevices: Int
    ) {
        self.schemaVersion = schemaVersion
        self.productIdentifier = productIdentifier
        self.licenseID = licenseID
        self.activationID = activationID
        self.deviceIdentifier = deviceIdentifier
        self.edition = edition
        self.features = features
        self.issuedAt = issuedAt
        self.verificationDueAt = verificationDueAt
        self.offlineGraceEndsAt = offlineGraceEndsAt
        self.maximumBuild = maximumBuild
        self.maximumDevices = maximumDevices
    }
}

public struct SignedLicenseReceipt:
    Codable,
    Equatable,
    Sendable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let payload: Data
    public let signature: Data

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        payload: Data,
        signature: Data
    ) {
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.signature = signature
    }
}

public struct LicenseSnapshot:
    Equatable,
    Sendable
{
    public let state: LicenseAccessState
    public let edition: LicenseEdition?
    public let enabledFeatures: Set<CommercialFeature>
    public let licenseID: String?
    public let activationID: String?
    public let verificationDueAt: Date?
    public let offlineGraceEndsAt: Date?
    public let maximumBuild: Int?
    public let maximumDevices: Int?

    public init(
        state: LicenseAccessState,
        edition: LicenseEdition? = nil,
        enabledFeatures: Set<CommercialFeature> = [],
        licenseID: String? = nil,
        activationID: String? = nil,
        verificationDueAt: Date? = nil,
        offlineGraceEndsAt: Date? = nil,
        maximumBuild: Int? = nil,
        maximumDevices: Int? = nil
    ) {
        self.state = state
        self.edition = edition
        self.enabledFeatures = enabledFeatures
        self.licenseID = licenseID
        self.activationID = activationID
        self.verificationDueAt = verificationDueAt
        self.offlineGraceEndsAt = offlineGraceEndsAt
        self.maximumBuild = maximumBuild
        self.maximumDevices = maximumDevices
    }

    public var hasCommercialAccess: Bool {
        switch state {
        case .preview, .active, .offlineGrace:
            return true
        case .community,
             .verificationRequired,
             .updateEntitlementExpired,
             .deviceMismatch,
             .invalid,
             .configurationError:
            return false
        }
    }

    public func allows(_ feature: CommercialFeature) -> Bool {
        hasCommercialAccess && enabledFeatures.contains(feature)
    }

    public static let community = LicenseSnapshot(state: .community)

    public static let preview = LicenseSnapshot(
        state: .preview,
        enabledFeatures: Set(CommercialFeature.allCases)
    )
}

public enum LicenseValidationError:
    Error,
    Equatable,
    Sendable
{
    case receiptTooLarge
    case malformedReceipt
    case unsupportedEnvelopeSchema
    case unsupportedPayloadSchema
    case invalidPublicKey
    case invalidPrivateKey
    case invalidSignature
    case wrongProduct
    case invalidIdentifier
    case duplicateFeatures
    case invalidDates
    case excessiveOfflineGrace
    case invalidBuild
    case invalidDeviceLimit
    case deviceMismatch
    case configurationMissing
}

extension LicenseValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .receiptTooLarge:
            return "The license receipt is too large."
        case .malformedReceipt:
            return "The license receipt could not be decoded."
        case .unsupportedEnvelopeSchema,
             .unsupportedPayloadSchema:
            return "The license receipt format is not supported by this version."
        case .invalidPublicKey:
            return "The configured license verification key is invalid."
        case .invalidPrivateKey:
            return "The license signing key is invalid."
        case .invalidSignature:
            return "The license signature is invalid."
        case .wrongProduct:
            return "The license was issued for a different product."
        case .invalidIdentifier:
            return "The license contains an invalid identifier."
        case .duplicateFeatures:
            return "The license contains duplicate feature entries."
        case .invalidDates:
            return "The license validity dates are invalid."
        case .excessiveOfflineGrace:
            return "The license offline grace period exceeds the supported limit."
        case .invalidBuild:
            return "The license build entitlement is invalid."
        case .invalidDeviceLimit:
            return "The license device limit is invalid."
        case .deviceMismatch:
            return "The license is activated for a different Mac."
        case .configurationMissing:
            return "License verification is not configured in this build."
        }
    }
}
