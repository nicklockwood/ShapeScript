//
//  RenderProgress.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 30/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

public final class RenderProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var phase: Phase = .buildingLeaves
    private var completedUnitCount: Int = 0
    private var totalUnitCount: Int = 0
    private var _isFinished: Bool = false
    private var _isCancelled: Bool = false
    private var cancellationHandler: CancellationHandler = { false }
    private var activeUnitStart: Int = 0
    private var activeUnitCount: Int = 1
    private var activeCheckpointCount: Int = 0

    enum Phase: Sendable, Equatable {
        case buildingLeaves
        case buildingPreview
        case buildingFinal
        case exporting
        case writing
    }

    init(
        phase: Phase,
        completedUnitCount: Int,
        totalUnitCount: Int,
        isFinished: Bool,
        isCancelled: Bool
    ) {
        self.phase = phase
        self.completedUnitCount = max(0, completedUnitCount)
        self.totalUnitCount = max(0, totalUnitCount)
        self._isFinished = isFinished
        self._isCancelled = isCancelled
    }

    public init() {}
}

public extension RenderProgress {
    var fractionCompleted: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard totalUnitCount > 0 else {
            return nil
        }
        let fraction = min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
        return _isFinished ? fraction : min(fraction, 0.98)
    }

    var isCancelled: Bool {
        lock.lock()
        let cancellationHandler = cancellationHandler
        let isCancelled = _isCancelled
        lock.unlock()
        return isCancelled || cancellationHandler()
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFinished
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}

extension RenderProgress {
    func beginTracking(totalUnitCount: Int, isCancelled: @escaping CancellationHandler) {
        lock.lock()
        phase = .buildingLeaves
        completedUnitCount = 0
        self.totalUnitCount = max(1, totalUnitCount)
        _isFinished = false
        cancellationHandler = isCancelled
        activeUnitStart = 0
        activeUnitCount = 1
        activeCheckpointCount = 0
        lock.unlock()
    }

    func endTracking() {
        lock.lock()
        cancellationHandler = { false }
        lock.unlock()
    }

    func enter(_ phase: Phase) -> Bool {
        lock.lock()
        self.phase = phase
        lock.unlock()
        return !isCancelled
    }

    func beginUnit(_ phase: Phase, unitCount: Int) -> Bool {
        lock.lock()
        self.phase = phase
        activeUnitStart = completedUnitCount
        activeUnitCount = max(1, unitCount)
        activeCheckpointCount = 0
        lock.unlock()
        return !isCancelled
    }

    func checkpoint(_ phase: Phase) -> Bool {
        lock.lock()
        self.phase = phase
        activeCheckpointCount += 1
        completedUnitCount = min(
            activeUnitStart + min(activeCheckpointCount, max(0, activeUnitCount - 1)),
            totalUnitCount
        )
        lock.unlock()
        return !isCancelled
    }

    func cancellationHandler(for phase: Phase) -> CancellationHandler {
        { self.checkpoint(phase) == false }
    }

    func completeUnit(_ phase: Phase, by unitCount: Int = 1) -> Bool {
        lock.lock()
        self.phase = phase
        completedUnitCount = min(activeUnitStart + max(1, unitCount), totalUnitCount)
        activeUnitStart = completedUnitCount
        activeUnitCount = 1
        activeCheckpointCount = 0
        lock.unlock()
        return !isCancelled
    }

    func finish() {
        lock.lock()
        completedUnitCount = totalUnitCount
        _isFinished = true
        lock.unlock()
    }
}
