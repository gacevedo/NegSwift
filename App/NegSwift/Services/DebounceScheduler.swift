//
//  DebounceScheduler.swift
//  NegSwift
//

import Foundation

@MainActor
final class DebounceScheduler {
    static let previewInterval: Duration = .milliseconds(300)

    private var task: Task<Void, Never>?
    private let interval: Duration

    init(interval: Duration = DebounceScheduler.previewInterval) {
        self.interval = interval
    }

    func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
