import Combine
import Foundation
import OSLog

struct PermissionStatusSnapshot: Equatable, Sendable {
    let microphone: MicrophonePermissionState
    let accessibilityTrusted: Bool

    static func live() -> Self {
        Self(
            microphone: AudioRecorder.microphonePermissionState(),
            accessibilityTrusted: AccessibilityPermission.isTrusted()
        )
    }
}

@MainActor
final class PermissionStatusMonitor: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "PermissionStatus"
    )

    @Published private(set) var snapshot: PermissionStatusSnapshot
    private let snapshotProvider: @MainActor () -> PermissionStatusSnapshot

    init(
        snapshotProvider: @escaping @MainActor () -> PermissionStatusSnapshot = {
            PermissionStatusSnapshot.live()
        }
    ) {
        self.snapshotProvider = snapshotProvider
        self.snapshot = snapshotProvider()
    }

    func refresh() {
        let nextSnapshot = snapshotProvider()
        guard nextSnapshot != snapshot else {
            return
        }

        Self.logger.info(
            "Permission status changed: microphone=\(String(describing: nextSnapshot.microphone), privacy: .public), accessibilityTrusted=\(nextSnapshot.accessibilityTrusted, privacy: .public)"
        )
        snapshot = nextSnapshot
    }
}
