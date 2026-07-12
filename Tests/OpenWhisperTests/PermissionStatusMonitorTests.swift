import Testing
@testable import OpenWhisper

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
