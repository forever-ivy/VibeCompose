import Foundation
import OpenWhisperLicensing

enum CommercialLicensing {
    static func manager(
        snapshotPrivacyMode: SnapshotPrivacyMode,
        infoDictionary: [String: Any] =
            Bundle.main.infoDictionary ?? [:]
    ) -> any CommercialLicenseManaging {
        if snapshotPrivacyMode.isEnabled {
            return StaticLicenseManager.preview
        }

        do {
            return LicenseManager(
                configuration: try LicenseRuntimeConfiguration(
                    infoDictionary: infoDictionary
                ),
                receiptStore: KeychainLicenseReceiptStore(
                    service:
                        ProductIdentity.licenseReceiptKeychainService
                ),
                deviceStore: KeychainLicenseDeviceIdentifierStore(
                    service:
                        ProductIdentity.licenseDeviceKeychainService
                )
            )
        } catch {
            return StaticLicenseManager(
                snapshot: LicenseSnapshot(
                    state: .configurationError
                )
            )
        }
    }
}

extension LicenseEdition {
    var localizedTitle: String {
        switch self {
        case .founderPro:
            return L10n.text("Founder Pro")
        case .pro:
            return L10n.text("OpenWhisper Pro")
        }
    }
}

extension LicenseSnapshot {
    var localizedStatusTitle: String {
        switch state {
        case .community:
            return L10n.text("Community")
        case .preview:
            return L10n.text("Pro Preview")
        case .active:
            return edition?.localizedTitle
                ?? L10n.text("OpenWhisper Pro")
        case .offlineGrace:
            return L10n.text("Pro — Offline Grace")
        case .verificationRequired:
            return L10n.text("License Verification Required")
        case .updateEntitlementExpired:
            return L10n.text("Update Entitlement Required")
        case .deviceMismatch:
            return L10n.text("License Device Mismatch")
        case .invalid:
            return L10n.text("Invalid License")
        case .configurationError:
            return L10n.text("License Verification Unavailable")
        }
    }

    var localizedStatusDetail: String {
        switch state {
        case .community:
            return L10n.text(
                "Community keeps the complete core dictation, safety, recovery, privacy, and update path available without a paid license."
            )
        case .preview:
            return L10n.text(
                "This private Alpha explicitly enables the Pro workflow preview. It is not a paid activation and does not include model access or service guarantees."
            )
        case .active:
            return L10n.text(
                "This Mac has a valid signed Pro activation receipt."
            )
        case .offlineGrace:
            return L10n.text(
                "Pro remains available temporarily while this Mac is offline. Import a refreshed signed receipt before the grace period ends."
            )
        case .verificationRequired:
            return L10n.text(
                "The offline grace period ended. Import a refreshed signed receipt to restore Pro workflows; Community dictation remains available."
            )
        case .updateEntitlementExpired:
            return L10n.text(
                "This license remains usable with an eligible older build, but it does not cover the current build. Import a renewed receipt or reinstall an eligible version."
            )
        case .deviceMismatch:
            return L10n.text(
                "The stored receipt was activated for another Mac. Remove it and import an activation issued for this device."
            )
        case .invalid:
            return L10n.text(
                "The stored receipt failed integrity or format validation. Community dictation remains available."
            )
        case .configurationError:
            return L10n.text(
                "This build does not contain a valid license verification key. Commercial releases are blocked when this configuration is missing."
            )
        }
    }
}
