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
    private nonisolated(unsafe) var _status: Status = .waiting

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
                return false
            case .cancelled, .failure:
                return true
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
            return true
        case .cancelled, .success, .failure:
            return false
        }
    }

    nonisolated var didSucceed: Bool {
        switch status {
        case .success:
            return true
        case .waiting, .partial, .cancelled, .failure:
            return false
        }
    }

    nonisolated func cancel() {
        setStatus(.cancelled)
    }

    nonisolated func setStatus(_ status: Status) {
        lock.lock()
        // Once progress is cancelled or failed it can't be resumed
        if _status.isCancelledOrFailed {
            lock.unlock()
            return
        }
        _status = status
        lock.unlock()
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                observer(status)
            }
        } else {
            DispatchQueue.main.async {
                self.observer(status)
            }
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

    @MainActor private func resume() {
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
                    self.resume()
                }
            } catch {
                self?.setStatus(.failure(ProgramError(error)))
            }
        }
        thread?.name = "shapescript.progress.\(id)"
        thread?.qualityOfService = .userInitiated
        thread?.stackSize = 4 * 1024 * 1024
        thread?.start()
    }
}
