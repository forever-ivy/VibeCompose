import Testing
@testable import VibeCompose

@MainActor
@Test
func permissionStatusMonitorRefreshesAfterSystemSettingsChanges() {
    var current = PermissionStatusSnapshot(
        microphone: .denied,
        accessibilityTrusted: false
    )
    let monitor = PermissionStatusMonitor {
        current
    }

    #expect(monitor.snapshot == current)

    current = PermissionStatusSnapshot(
        microphone: .granted,
        accessibilityTrusted: true
    )
    monitor.refresh()

    #expect(monitor.snapshot == current)
}

@MainActor
@Test
func permissionStatusMonitorPollsUntilMicrophoneRequestSettles() async {
    var current = PermissionStatusSnapshot(
        microphone: .undetermined,
        accessibilityTrusted: true
    )
    var pauseCount = 0
    let monitor = PermissionStatusMonitor {
        current
    }

    let result = await monitor.requestMicrophoneAccess(
        using: {
            .success(())
        },
        maximumRefreshAttempts: 4,
        pause: { _ in
            pauseCount += 1
            current = PermissionStatusSnapshot(
                microphone: .granted,
                accessibilityTrusted: true
            )
        }
    )

    if case .failure(let error) = result {
        Issue.record("Unexpected microphone request failure: \(error)")
    }
    #expect(pauseCount == 1)
    #expect(monitor.snapshot.microphone == .granted)
}

@MainActor
@Test
func permissionStatusMonitorRefreshesDeniedStateWithoutPolling() async {
    enum TestError: Error {
        case denied
    }

    var current = PermissionStatusSnapshot(
        microphone: .undetermined,
        accessibilityTrusted: true
    )
    var pauseCount = 0
    let monitor = PermissionStatusMonitor {
        current
    }

    let result = await monitor.requestMicrophoneAccess(
        using: {
            current = PermissionStatusSnapshot(
                microphone: .denied,
                accessibilityTrusted: true
            )
            return .failure(TestError.denied)
        },
        pause: { _ in
            pauseCount += 1
        }
    )

    if case .success = result {
        Issue.record("Expected the microphone request to fail.")
    }
    #expect(pauseCount == 0)
    #expect(monitor.snapshot.microphone == .denied)
}

@MainActor
@Test
func permissionStatusMonitorBoundsPollingWhenSystemStateStaysUndetermined() async {
    let current = PermissionStatusSnapshot(
        microphone: .undetermined,
        accessibilityTrusted: true
    )
    var pauseCount = 0
    let monitor = PermissionStatusMonitor {
        current
    }

    let result = await monitor.requestMicrophoneAccess(
        using: {
            .success(())
        },
        maximumRefreshAttempts: 3,
        pause: { _ in
            pauseCount += 1
        }
    )

    if case .failure(let error) = result {
        Issue.record("Unexpected microphone request failure: \(error)")
    }
    #expect(pauseCount == 2)
    #expect(monitor.snapshot.microphone == .undetermined)
}

@MainActor
@Test
func permissionStatusMonitorPollsUntilAccessibilityTrustSettles() async {
    var current = PermissionStatusSnapshot(
        microphone: .granted,
        accessibilityTrusted: false
    )
    var pauseCount = 0
    let monitor = PermissionStatusMonitor {
        current
    }

    let trusted = await monitor.refreshAccessibilityUntilTrusted(
        maximumRefreshAttempts: 5,
        pause: { _ in
            pauseCount += 1
            if pauseCount == 2 {
                current = PermissionStatusSnapshot(
                    microphone: .granted,
                    accessibilityTrusted: true
                )
            }
        }
    )

    #expect(trusted)
    #expect(pauseCount == 2)
    #expect(monitor.snapshot.accessibilityTrusted)
}

@MainActor
@Test
func permissionStatusMonitorStopsAccessibilityPollingWhenStillUntrusted() async {
    let current = PermissionStatusSnapshot(
        microphone: .granted,
        accessibilityTrusted: false
    )
    var pauseCount = 0
    let monitor = PermissionStatusMonitor {
        current
    }

    let trusted = await monitor.refreshAccessibilityUntilTrusted(
        maximumRefreshAttempts: 3,
        pause: { _ in
            pauseCount += 1
        }
    )

    #expect(trusted == false)
    #expect(pauseCount == 2)
    #expect(monitor.snapshot.accessibilityTrusted == false)
}
