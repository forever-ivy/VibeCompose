import CryptoKit
import Foundation

public enum LicenseReceiptCodec {
    public static func sign(
        payload: LicenseReceiptPayload,
        privateKey: Data
    ) throws -> Data {
        let signingKey: Curve25519.Signing.PrivateKey
        do {
            signingKey = try Curve25519.Signing.PrivateKey(
                rawRepresentation: privateKey
            )
        } catch {
            throw LicenseValidationError.invalidPrivateKey
        }

        let payloadData: Data
        do {
            payloadData = try payloadEncoder().encode(payload)
        } catch {
            throw LicenseValidationError.malformedReceipt
        }
        guard payloadData.count <= LicenseManager.maximumPayloadBytes else {
            throw LicenseValidationError.receiptTooLarge
        }

        let signature = try signingKey.signature(for: payloadData)
        let envelope = SignedLicenseReceipt(
            payload: payloadData,
            signature: signature
        )
        do {
            let data = try envelopeEncoder().encode(envelope)
            guard data.count <= LicenseManager.maximumReceiptBytes else {
                throw LicenseValidationError.receiptTooLarge
            }
            return data
        } catch let error as LicenseValidationError {
            throw error
        } catch {
            throw LicenseValidationError.malformedReceipt
        }
    }

    public static func verify(
        _ receiptData: Data,
        publicKey: Data,
        expectedProductIdentifier: String,
        expectedDeviceIdentifier: String,
        now: Date
    ) throws -> LicenseReceiptPayload {
        guard receiptData.count <= LicenseManager.maximumReceiptBytes else {
            throw LicenseValidationError.receiptTooLarge
        }
        let envelope: SignedLicenseReceipt
        do {
            envelope = try envelopeDecoder().decode(
                SignedLicenseReceipt.self,
                from: receiptData
            )
        } catch {
            throw LicenseValidationError.malformedReceipt
        }
        guard
            envelope.schemaVersion
                == SignedLicenseReceipt.currentSchemaVersion
        else {
            throw LicenseValidationError.unsupportedEnvelopeSchema
        }
        guard envelope.payload.count <= LicenseManager.maximumPayloadBytes else {
            throw LicenseValidationError.receiptTooLarge
        }

        let verificationKey: Curve25519.Signing.PublicKey
        do {
            verificationKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKey
            )
        } catch {
            throw LicenseValidationError.invalidPublicKey
        }
        guard
            verificationKey.isValidSignature(
                envelope.signature,
                for: envelope.payload
            )
        else {
            throw LicenseValidationError.invalidSignature
        }

        let payload: LicenseReceiptPayload
        do {
            payload = try payloadDecoder().decode(
                LicenseReceiptPayload.self,
                from: envelope.payload
            )
        } catch {
            throw LicenseValidationError.malformedReceipt
        }

        try validate(
            payload,
            expectedProductIdentifier: expectedProductIdentifier,
            expectedDeviceIdentifier: expectedDeviceIdentifier,
            now: now
        )
        return payload
    }

    private static func validate(
        _ payload: LicenseReceiptPayload,
        expectedProductIdentifier: String,
        expectedDeviceIdentifier: String,
        now: Date
    ) throws {
        guard
            payload.schemaVersion
                == LicenseReceiptPayload.currentSchemaVersion
        else {
            throw LicenseValidationError.unsupportedPayloadSchema
        }
        guard payload.productIdentifier == expectedProductIdentifier else {
            throw LicenseValidationError.wrongProduct
        }
        guard
            validIdentifier(payload.licenseID),
            validIdentifier(payload.activationID),
            UUID(uuidString: payload.deviceIdentifier) != nil
        else {
            throw LicenseValidationError.invalidIdentifier
        }
        guard
            payload.deviceIdentifier.lowercased()
                == expectedDeviceIdentifier.lowercased()
        else {
            throw LicenseValidationError.deviceMismatch
        }
        guard Set(payload.features).count == payload.features.count else {
            throw LicenseValidationError.duplicateFeatures
        }
        guard
            payload.issuedAt
                <= now.addingTimeInterval(
                    LicenseManager.allowedFutureClockSkewSeconds
                ),
            payload.verificationDueAt >= payload.issuedAt,
            payload.offlineGraceEndsAt >= payload.verificationDueAt
        else {
            throw LicenseValidationError.invalidDates
        }
        guard
            payload.offlineGraceEndsAt.timeIntervalSince(
                payload.verificationDueAt
            ) <= LicenseManager.maximumOfflineGraceSeconds
        else {
            throw LicenseValidationError.excessiveOfflineGrace
        }
        guard payload.maximumBuild > 0 else {
            throw LicenseValidationError.invalidBuild
        }
        guard (1...100).contains(payload.maximumDevices) else {
            throw LicenseValidationError.invalidDeviceLimit
        }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func payloadEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func payloadDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func envelopeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func envelopeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
