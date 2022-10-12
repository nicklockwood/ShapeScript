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

final class LoadingProgress {
    private let queue: DispatchQueue
    private let observer: (Status) -> Void
    private(set) var status: Status = .waiting
    private(set) var id: Int = {
        _processID += 1
        return _processID
    }()

    init(observer: @escaping (Status) -> Void) {
        self.observer = observer
        queue = DispatchQueue(label: "shapescript.progress.\(id)")
        queue.async { self.setStatus(.waiting) }
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

    func dispatch(_ block: @escaping (LoadingProgress) throws -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            do {
                try block(self)
            } catch {
                self.setStatus(.failure(ProgramError(error)))
            }
        }
    }
}
