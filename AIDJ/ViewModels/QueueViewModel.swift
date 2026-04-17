import Foundation

@Observable
@MainActor
final class QueueViewModel {

    private(set) var items: [PlayableItem] = []
    private(set) var currentIndex: Int = 0

    private let coordinator: PlaybackCoordinator
    private var monitorTask: Task<Void, Never>?

    init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    func startObserving() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let queue = await coordinator.queue
                let index = await coordinator.currentIndex
                await MainActor.run {
                    self.items = queue
                    self.currentIndex = index
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stopObserving() {
        monitorTask?.cancel()
    }

    func skipSegment(at index: Int) {
        Task { await coordinator.removeItem(at: index) }
    }

    func remove(at index: Int) {
        Task { await coordinator.removeItem(at: index) }
    }

    func skip() {
        Task { try? await coordinator.skip() }
    }
}
