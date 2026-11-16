import Foundation

/// Undo-менеджер: хранит DTO-снимок удалённой задачи в памяти на 3 секунды.
/// При сворачивании/уходе приложения в background/inactive снимок уничтожается мгновенно —
/// задача считается окончательно удалённой.
public actor UndoService {
    public enum LifecycleState: Sendable {
        case active
        case inactive
        case background
    }

    private struct Pending {
        let snapshot: TaskSnapshot
    }

    private let lifecycle: () -> LifecycleState
    private var pending: Pending?
    private var timerTask: Task<Void, Never>?

    public init(
        lifecycle: @escaping () -> LifecycleState = { .active }
    ) {
        self.lifecycle = lifecycle
    }

    /// Записывает снимок и запускает чистую отменяемую `Task` на 3 секунды.
    /// При сворачивании (lifecycle != .active) снимок уничтожается немедленно.
    public func store(snapshot: TaskSnapshot) {
        cancel()

        guard lifecycle() == .active else { return }

        self.pending = Pending(snapshot: snapshot)

        let timer = Task<Void, Never> { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.expire()
        }
        self.timerTask = timer
    }

    /// Попытка Undo: возвращает снимок, если он ещё доступен.
    /// Вызовите `restore` с полученным снимком для восстановления.
    public func undo() -> TaskSnapshot? {
        let p = pending
        cancel()
        return p?.snapshot
    }

    public func cancel() {
        timerTask?.cancel()
        timerTask = nil
        pending = nil
    }

    private func expire() {
        timerTask?.cancel()
        timerTask = nil
        pending = nil
    }
}