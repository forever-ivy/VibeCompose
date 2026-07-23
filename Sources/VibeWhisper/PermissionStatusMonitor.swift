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
    typealias RefreshPause = @MainActor (Duration) async -> Void

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

    /// Poll after the user grants Accessibility in System Settings (or via the
    /// guided flow). TCC often lands a beat after the Settings toggle flips.
    @discardableResult
    func refreshAccessibilityUntilTrusted(
        maximumRefreshAttempts: Int = 20,
        refreshDelay: Duration = .milliseconds(250),
        pause: @escaping RefreshPause = { delay in
            try? await Task.sleep(for: delay)
        }
    ) async -> Bool {
        refresh()
        if snapshot.accessibilityTrusted {
            return true
        }

        guard maximumRefreshAttempts > 1 else {
            return snapshot.accessibilityTrusted
        }

        for _ in 1..<maximumRefreshAttempts {
            await pause(refreshDelay)
            refresh()
            if snapshot.accessibilityTrusted {
                return true
            }
        }
        return snapshot.accessibilityTrusted
    }

    func requestMicrophoneAccess(
        using request: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        maximumRefreshAttempts: Int = 10,
        refreshDelay: Duration = .milliseconds(100),
        pause: @escaping RefreshPause = { delay in
            try? await Task.sleep(for: delay)
        }
    ) async -> Result<Void, any Error> {
        let result = await request()
        refresh()

        guard
            case .success = result,
            snapshot.microphone == .undetermined,
            maximumRefreshAttempts > 1
        else {
            return result
        }

        for _ in 1..<maximumRefreshAttempts {
            await pause(refreshDelay)
            refresh()
            if snapshot.microphone != .undetermined {
                break
            }
        }
        return result
    }
}
