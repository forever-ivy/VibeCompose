import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return L10n.format(
                "Could not install the global hotkey handler. Status code: %d.",
                status
            )
        case .register(let status):
            return L10n.format(
                "Could not register the global hotkey. Status code: %d.",
                status
            )
        }
    }
}

final class HotkeyMonitor {
    private static let signature = OSType(0x4354484B) // CTHK
    private static let callbackRegistry = HotkeyCallbackRegistry()

    private let id: UInt32
    private let onPress: @Sendable () -> Void
    private var hotKeyRef: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32 = 0, onPress: @escaping @Sendable () -> Void) throws {
        self.id = UInt32.random(in: 1...UInt32.max)
        self.onPress = onPress

        try Self.callbackRegistry.installSharedHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw HotKeyError.register(registerStatus)
        }

        Self.callbackRegistry.register(id: id, handler: onPress)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        Self.callbackRegistry.unregister(id: id)
    }

    fileprivate static func handleEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return OSStatus(noErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return OSStatus(noErr)
        }

        callbackRegistry.dispatch(id: hotKeyID.id)
        return OSStatus(noErr)
    }
}

final class HotkeyCallbackRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UInt32: @Sendable () -> Void] = [:]
    private var sharedEventHandlerRef: EventHandlerRef?

    func installSharedHandlerIfNeeded() throws {
        lock.lock()
        if sharedEventHandlerRef != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ in
            HotkeyMonitor.handleEvent(eventRef)
        }

        var eventHandlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotKeyError.installHandler(status)
        }

        lock.lock()
        sharedEventHandlerRef = eventHandlerRef
        lock.unlock()
    }

    func register(id: UInt32, handler: @escaping @Sendable () -> Void) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    func unregister(id: UInt32) {
        lock.lock()
        handlers.removeValue(forKey: id)
        let shouldTearDown = handlers.isEmpty
        let eventHandlerRef = shouldTearDown ? sharedEventHandlerRef : nil
        if shouldTearDown {
            sharedEventHandlerRef = nil
        }
        lock.unlock()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func dispatch(id: UInt32) {
        lock.lock()
        let handler = handlers[id]
        lock.unlock()
        handler?()
    }

    var registeredHandlerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }
}
