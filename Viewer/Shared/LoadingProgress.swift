//
//  LoadingProgress.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

typealias LoadingTask = @Sendable (LoadingProgress) throws -> Void

final class LoadingProgress: Sendable {
    // Thread-safe

    let id: Int
    nonisolated var status: Status {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    // Only accessed from internal thread

    private let lock = NSLock()
    private let partialObserverUpdateInterval: TimeInterval = 0.5
    private nonisolated(unsafe) var _status: Status = .waiting
    private nonisolated(unsafe) var pendingPartialStatus: Status?
    private nonisolated(unsafe) var partialObserverUpdateScheduled: Bool = false
    private nonisolated(unsafe) var partialObserverUpdateGeneration: Int = 0
    private nonisolated(unsafe) var lastPartialObserverUpdate: TimeInterval = 0

    // Only accessed from main thread

    @MainActor private static var _processID = 0
    @MainActor private let observer: @MainActor @Sendable (Status) -> Void
    @MainActor private var thread: Thread? {
        didSet { assert(Thread.isMainThread) }
    }

    @MainActor private var queue: [LoadingTask] = [] {
        didSet { assert(Thread.isMainThread) }
    }

    @MainActor init(observer: @escaping @MainActor @Sendable (Status) -> Void) {
        assert(Thread.isMainThread)
        Self._processID += 1
        self.id = Self._processID
        self.observer = observer
        // Defer initial update for one cycle
        DispatchQueue.main.async {
            if self.status.isCancelledOrFailed {
                return
            }
            // Note: status may have changed at this point, but
            // no other status should have been sent to the observer
            // (i.e. the changes are still waiting on the queue)
            observer(.waiting)
        }
    }

    // Nonisolated

    deinit {
        print("[\(id)] released")
    }
}

extension LoadingProgress {
    enum Status {
        case waiting
        case partial(Scene)
        case success(Scene)
        case failure(ProgramError)
        case cancelled

        nonisolated var isCancelledOrFailed: Bool {
            switch self {
            case .waiting, .partial, .success:
                false
            case .cancelled, .failure:
                true
            }
        }
    }

    // Thread-safe

    nonisolated var isCancelledOrFailed: Bool {
        status.isCancelledOrFailed
    }

    nonisolated var inProgress: Bool {
        switch status {
        case .waiting, .partial:
            true
        case .cancelled, .success, .failure:
            false
        }
    }

    nonisolated var didSucceed: Bool {
        switch status {
        case .success:
            true
        case .waiting, .partial, .cancelled, .failure:
            false
        }
    }

    nonisolated func cancel() {
        setStatus(.cancelled)
    }

    nonisolated func setStatus(_ status: Status) {
        enum ObserverAction {
            case notify(Status)
            case notifyPartial(Status)
            case schedulePendingPartial(delay: TimeInterval, generation: Int)
        }

        let action: ObserverAction
        lock.lock()
        // Once progress is cancelled or failed it can't be resumed
        if _status.isCancelledOrFailed {
            lock.unlock()
            return
        }
        _status = status
        switch status {
        case .partial:
            let now = CFAbsoluteTimeGetCurrent()
            if partialObserverUpdateScheduled {
                pendingPartialStatus = status
                lock.unlock()
                return
            }
            let delay = max(0, partialObserverUpdateInterval - (now - lastPartialObserverUpdate))
            partialObserverUpdateScheduled = true
            if delay > 0 {
                pendingPartialStatus = status
                partialObserverUpdateGeneration += 1
                action = .schedulePendingPartial(
                    delay: delay,
                    generation: partialObserverUpdateGeneration
                )
            } else {
                action = .notifyPartial(status)
            }
        case .waiting, .success, .failure, .cancelled:
            pendingPartialStatus = nil
            partialObserverUpdateScheduled = false
            partialObserverUpdateGeneration += 1
            action = .notify(status)
        }
        lock.unlock()
        switch action {
        case let .notify(status):
            performOnMain { self.observer(status) }
        case let .notifyPartial(status):
            performOnMain { self.notifyPartialObserver(status) }
        case let .schedulePendingPartial(delay, generation):
            schedulePendingPartialObserverUpdate(after: delay, generation: generation)
        }
    }

    // Main-thread only

    /// Evaluate code on the loading thread (but must be called from the main thread)
    @MainActor func dispatch(_ block: @escaping LoadingTask) {
        assert(Thread.isMainThread)
        assert(!status.isCancelledOrFailed)
        queue.append(block)
        if thread?.isExecuting == true {
            return
        }
        resume()
    }
}

private nonisolated extension LoadingProgress {
    func performOnMain(_ callback: @escaping @Sendable @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(callback)
        } else {
            DispatchQueue.main.async {
                callback()
            }
        }
    }

    func schedulePendingPartialObserverUpdate(after delay: TimeInterval, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.notifyPendingPartialObserver(generation: generation)
        }
    }
}

@MainActor private extension LoadingProgress {
    func resume() {
        assert(Thread.isMainThread)
        assert(!status.isCancelledOrFailed)
        let queue = queue
        guard !queue.isEmpty else { return }
        self.queue.removeAll()
        thread = Thread { [weak self] in
            do {
                for task in queue {
                    guard let self, !self.status.isCancelledOrFailed else { return }
                    try task(self)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.status.isCancelledOrFailed else { return }
                    resume()
                }
            } catch {
                self?.setStatus(.failure(ProgramError(error)))
            }
        }
        thread?.name = "shapescript.progress.\(id)"
        thread?.qualityOfService = .userInitiated
        thread?.stackSize = 16 * 1024 * 1024
        thread?.start()
    }

    func notifyPartialObserver(_ status: Status) {
        observer(status)

        let pendingStatus: Status?
        let generation: Int?
        lock.lock()
        lastPartialObserverUpdate = CFAbsoluteTimeGetCurrent()
        pendingStatus = pendingPartialStatus
        pendingPartialStatus = nil
        if pendingStatus != nil {
            partialObserverUpdateGeneration += 1
            generation = partialObserverUpdateGeneration
        } else {
            partialObserverUpdateScheduled = false
            generation = nil
        }
        lock.unlock()

        if let generation {
            schedulePendingPartialObserverUpdate(
                after: partialObserverUpdateInterval,
                generation: generation
            )
        }
    }

    func notifyPendingPartialObserver(generation: Int) {
        let status: Status?
        let isCurrentGeneration: Bool
        lock.lock()
        isCurrentGeneration = generation == partialObserverUpdateGeneration
        if isCurrentGeneration {
            status = pendingPartialStatus
            pendingPartialStatus = nil
        } else {
            status = nil
        }
        lock.unlock()

        guard let status else {
            guard isCurrentGeneration else {
                return
            }
            lock.lock()
            partialObserverUpdateScheduled = false
            lock.unlock()
            return
        }
        notifyPartialObserver(status)
    }
}
