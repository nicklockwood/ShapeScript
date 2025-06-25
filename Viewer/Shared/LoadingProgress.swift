//
//  LoadingProgress.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

typealias LoadingTask = (LoadingProgress) throws -> Void

final class LoadingProgress {
    // Thread-safe
    let id: Int
    var status: Status {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    // Only accessed from internal thread
    private let lock = NSLock()
    private var _status: Status = .waiting

    // Only accessed from main thread
    private static var _processID = 0
    private let observer: (Status) -> Void
    private var thread: Thread? {
        didSet { assert(Thread.isMainThread) }
    }

    private var queue: [LoadingTask] = [] {
        didSet { assert(Thread.isMainThread) }
    }

    init(observer: @escaping (Status) -> Void) {
        assert(Thread.isMainThread)
        Self._processID += 1
        self.id = Self._processID
        self.observer = observer
        dispatch { _ in
            self.setStatus(.waiting)
        }
    }

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
    }

    // Thread-safe

    var isCancelled: Bool {
        if case .cancelled = status {
            return true
        }
        return false
    }

    var hasFailed: Bool {
        if case .failure = status {
            return true
        }
        return false
    }

    var inProgress: Bool {
        switch status {
        case .waiting, .partial:
            return true
        case .cancelled, .success, .failure:
            return false
        }
    }

    var didSucceed: Bool {
        switch status {
        case .success:
            return true
        case .waiting, .partial, .cancelled, .failure:
            return false
        }
    }

    func cancel() {
        setStatus(.cancelled)
    }

    func setStatus(_ status: Status) {
        if isCancelled || hasFailed { return }
        if Thread.isMainThread {
            dispatch { $0.setStatus(status) }
            return
        }
        assert(Thread.current.name == thread?.name)
        lock.lock()
        _status = status
        lock.unlock()
        DispatchQueue.main.async {
            self.observer(status)
        }
    }

    // Evaluate code on the loading thread
    // Must be called from the main thread
    func dispatch(_ block: @escaping LoadingTask) {
        assert(Thread.isMainThread)
        queue.append(block)
        if thread?.isExecuting == true {
            return
        }
        thread = Thread { [weak self] in
            do {
                while let task: LoadingTask = DispatchQueue.main.sync(execute: { [weak self] in
                    guard let self = self, !self.queue.isEmpty else {
                        return nil
                    }
                    return self.queue.removeFirst()
                }), let self = self {
                    try task(self)
                }
            } catch {
                self?.setStatus(.failure(ProgramError(error)))
            }
        }
        thread?.name = "shapescript.progress.\(id)"
        thread?.stackSize = 4 * 1024 * 1024
        thread?.start()
    }
}
