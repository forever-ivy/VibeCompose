import Foundation
import Sparkle

struct SoftwareUpdateConfiguration: Equatable, Sendable {
    enum ValidationError: Error, Equatable, LocalizedError {
        case incomplete
        case invalidFeedURL
        case invalidPublicKey

        var errorDescription: String? {
            switch self {
            case .incomplete:
                L10n.text(
                    "Software updates are unavailable because this build has incomplete update configuration."
                )
            case .invalidFeedURL:
                L10n.text(
                    "Software updates are unavailable because this build has an invalid update feed."
                )
            case .invalidPublicKey:
                L10n.text(
                    "Software updates are unavailable because this build has an invalid update signing key."
                )
            }
        }
    }

    let feedURL: URL
    let publicKey: String

    init(infoDictionary: [String: Any]) throws {
        let rawFeedURL = (infoDictionary["SUFeedURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPublicKey = (infoDictionary["SUPublicEDKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !rawFeedURL.isEmpty, !rawPublicKey.isEmpty else {
            throw ValidationError.incomplete
        }
        guard
            let feedURL = URL(string: rawFeedURL),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            feedURL.user == nil,
            feedURL.password == nil
        else {
            throw ValidationError.invalidFeedURL
        }
        guard
            let publicKeyData = Data(base64Encoded: rawPublicKey),
            publicKeyData.count == 32
        else {
            throw ValidationError.invalidPublicKey
        }

        self.feedURL = feedURL
        self.publicKey = rawPublicKey
    }

    static func load(bundle: Bundle = .main) -> Result<Self, ValidationError> {
        do {
            return .success(try Self(infoDictionary: bundle.infoDictionary ?? [:]))
        } catch let error as ValidationError {
            return .failure(error)
        } catch {
            return .failure(.incomplete)
        }
    }
}

struct SoftwareUpdateSnapshot: Equatable, Sendable {
    let isConfigured: Bool
    let canCheckForUpdates: Bool
    let automaticallyChecksForUpdates: Bool
    let lastUpdateCheckDate: Date?
    let detail: String
}

enum SoftwareUpdateError: Error, Equatable, LocalizedError {
    case unavailable(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            detail
        case .busy:
            L10n.text("An update check is already in progress.")
        }
    }
}

@MainActor
protocol SoftwareUpdating: AnyObject {
    func snapshot() -> SoftwareUpdateSnapshot
    func checkForUpdates() -> Result<Void, SoftwareUpdateError>
    func setAutomaticallyChecksForUpdates(
        _ enabled: Bool
    ) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>
}

@MainActor
final class SparkleSoftwareUpdater: SoftwareUpdating {
    private let controller: SPUStandardUpdaterController?
    private let unavailableDetail: String?

    init(bundle: Bundle = .main) {
        switch SoftwareUpdateConfiguration.load(bundle: bundle) {
        case .success:
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            unavailableDetail = nil
        case .failure(let error):
            controller = nil
            unavailableDetail = error.localizedDescription
        }
    }

    func snapshot() -> SoftwareUpdateSnapshot {
        guard let updater = controller?.updater else {
            return SoftwareUpdateSnapshot(
                isConfigured: false,
                canCheckForUpdates: false,
                automaticallyChecksForUpdates: false,
                lastUpdateCheckDate: nil,
                detail: unavailableDetail
                    ?? L10n.text("Software updates are unavailable in this build.")
            )
        }

        return SoftwareUpdateSnapshot(
            isConfigured: true,
            canCheckForUpdates: updater.canCheckForUpdates,
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            lastUpdateCheckDate: updater.lastUpdateCheckDate,
            detail: L10n.text(
                "Updates are verified with Sparkle and the signing key embedded in this app."
            )
        )
    }

    func checkForUpdates() -> Result<Void, SoftwareUpdateError> {
        guard let controller else {
            return .failure(
                .unavailable(
                    unavailableDetail
                        ?? L10n.text("Software updates are unavailable in this build.")
                )
            )
        }
        guard controller.updater.canCheckForUpdates else {
            return .failure(.busy)
        }

        controller.checkForUpdates(nil)
        return .success(())
    }

    func setAutomaticallyChecksForUpdates(
        _ enabled: Bool
    ) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError> {
        guard let updater = controller?.updater else {
            return .failure(
                .unavailable(
                    unavailableDetail
                        ?? L10n.text("Software updates are unavailable in this build.")
                )
            )
        }
        updater.automaticallyChecksForUpdates = enabled
        return .success(snapshot())
    }
}
