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
    private let observer: Observer
    private(set) var status: Status = .waiting
    private(set) var id: Int = {
        _processID += 1
        return _processID
    }()

    init(_ observer: @escaping Observer) {
        self.observer = observer
        self.queue = DispatchQueue(label: "shapescript.progress.\(id)")
        DispatchQueue.main.async {
            self.observer(self.status)
        }
    }
}

extension LoadingProgress {
    typealias Observer = (Status) -> Void

    enum Status {
        case waiting
        case partial(Scene)
        case success(Scene)
        case failure(Error)
        case cancelled
    }

    var isCancelled: Bool {
        if case .cancelled = status {
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
        guard inProgress else { return }
        self.status = status
        DispatchQueue.main.async {
            self.observer(status)
        }
    }

    func dispatch(_ block: @escaping () throws -> Void) {
        guard inProgress else { return }
        queue.async { [weak self] in
            do {
                try block()
            } catch {
                self?.setStatus(.failure(error))
            }
        }
    }
}
