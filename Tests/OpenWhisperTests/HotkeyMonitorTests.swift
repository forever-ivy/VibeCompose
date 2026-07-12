import Foundation
import Testing
@testable import OpenWhisper

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Test
func hotkeyCallbackRegistryDispatchesEachRegisteredHandlerByIdentifier() {
    let registry = HotkeyCallbackRegistry()
    let f5PressCount = CounterBox()
    let escapePressCount = CounterBox()

    registry.register(id: 101) {
        f5PressCount.increment()
    }
    registry.register(id: 202) {
        escapePressCount.increment()
    }

    registry.dispatch(id: 101)
    registry.dispatch(id: 202)
    registry.dispatch(id: 101)

    #expect(f5PressCount.read() == 2)
    #expect(escapePressCount.read() == 1)
    #expect(registry.registeredHandlerCount == 2)
}

@Test
func hotkeyCallbackRegistryKeepsRemainingHandlersAfterUnregister() {
    let registry = HotkeyCallbackRegistry()
    let survivingPressCount = CounterBox()

    registry.register(id: 1) {}
    registry.register(id: 2) {
        survivingPressCount.increment()
    }

    registry.unregister(id: 1)
    registry.dispatch(id: 1)
    registry.dispatch(id: 2)

    #expect(survivingPressCount.read() == 1)
    #expect(registry.registeredHandlerCount == 1)
}
