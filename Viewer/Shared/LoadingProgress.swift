//
//  LoadingProgress.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

private var _processID = 0

typealias LoadingTask = (LoadingProgress) throws -> Void

final class LoadingProgress {
    private var thread: Thread?
    private var queue: [LoadingTask] = []
    private let observer: (Status) -> Void
    private(set) var status: Status = .waiting
    private(set) var id: Int = {
        _processID += 1
        return _processID
    }()

    init(observer: @escaping (Status) -> Void) {
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
        self.status = status
        DispatchQueue.main.async {
            self.observer(status)
        }
    }

    func dispatch(_ block: @escaping LoadingTask) {
        DispatchQueue.main.async { [weak self] in
            self?.queue.append(block)
        }
        if thread?.isExecuting == true {
            return
        }
        thread = Thread { [weak self] in
            do {
                while let task = DispatchQueue.main.sync(execute: { [weak self] () -> LoadingTask? in
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
