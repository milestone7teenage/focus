import Foundation

/// Общий провайдер состояния жизненного цикла приложения.
/// Используется `UndoService` для проверки, активно ли приложение.
@unchecked Sendable
public final class AppLifecycleProvider {
    private let lock = NSLock()
    private var _state: UndoService.LifecycleState = .active

    public init() {}

    public var state: UndoService.LifecycleState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public func setState(_ newState: UndoService.LifecycleState) {
        lock.lock()
        defer { lock.unlock() }
        _state = newState
    }

    /// Замыкание для использования в `UndoService`.
    public var lifecycleProvider: () -> UndoService.LifecycleState {
        { self.state }
    }
}