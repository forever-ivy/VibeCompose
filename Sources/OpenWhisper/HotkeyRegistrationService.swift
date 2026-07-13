import Foundation

@MainActor
final class HotkeyRegistrationService {
    typealias MonitorFactory = @MainActor (
        HotkeyBinding,
        @escaping @Sendable () -> Void
    ) throws -> AnyObject

    enum StartupOutcome: Equatable {
        case registered(HotkeyBinding)
        case fellBack(
            requested: HotkeyBinding,
            active: HotkeyBinding,
            reason: String
        )
        case unavailable(
            requested: HotkeyBinding,
            reason: String
        )

        var activeBinding: HotkeyBinding? {
            switch self {
            case .registered(let binding):
                return binding
            case .fellBack(_, let active, _):
                return active
            case .unavailable:
                return nil
            }
        }
    }

    private let monitorFactory: MonitorFactory
    private var activeMonitor: AnyObject?
    private var activeHandler:
        (@Sendable () -> Void)?
    private(set) var activeBinding: HotkeyBinding?
    private(set) var isSuspended = false

    init(
        monitorFactory: @escaping MonitorFactory = {
            binding,
            onPress in
            try HotkeyMonitor(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                onPress: onPress
            )
        }
    ) {
        self.monitorFactory = monitorFactory
    }

    func start(
        preferred binding: HotkeyBinding,
        onPress: @escaping @Sendable () -> Void
    ) -> StartupOutcome {
        activeMonitor = nil
        activeBinding = nil
        activeHandler = onPress
        isSuspended = false

        do {
            let validated = try binding.validated()
            activeMonitor = try monitorFactory(
                validated,
                onPress
            )
            activeBinding = validated
            return .registered(validated)
        } catch {
            let primaryReason = error.localizedDescription
            guard binding != .f5 else {
                return .unavailable(
                    requested: binding,
                    reason: primaryReason
                )
            }

            do {
                let fallback = try HotkeyBinding.f5.validated()
                activeMonitor = try monitorFactory(
                    fallback,
                    onPress
                )
                activeBinding = fallback
                return .fellBack(
                    requested: binding,
                    active: fallback,
                    reason: primaryReason
                )
            } catch {
                return .unavailable(
                    requested: binding,
                    reason: error.localizedDescription
                )
            }
        }
    }

    func replace(
        with binding: HotkeyBinding,
        onPress: @escaping @Sendable () -> Void,
        persist: () throws -> Void
    ) throws {
        let validated = try binding.validated()
        if activeBinding == validated,
           !isSuspended
        {
            try persist()
            return
        }

        let candidate = try monitorFactory(
            validated,
            onPress
        )
        do {
            try persist()
        } catch {
            _ = candidate
            throw error
        }

        activeMonitor = candidate
        activeBinding = validated
        activeHandler = onPress
        isSuspended = false
    }

    func suspend() {
        guard
            activeBinding != nil,
            activeMonitor != nil
        else {
            return
        }
        activeMonitor = nil
        isSuspended = true
    }

    func resume() throws {
        guard isSuspended else {
            return
        }
        guard
            let activeBinding,
            let activeHandler
        else {
            isSuspended = false
            return
        }
        activeMonitor = try monitorFactory(
            activeBinding,
            activeHandler
        )
        isSuspended = false
    }

    func stop() {
        activeMonitor = nil
        activeBinding = nil
        activeHandler = nil
        isSuspended = false
    }
}
