//
//  EvaluationProgress.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 04/10/2026.
//

import Foundation

/// Tracks the progress of a program evaluation and provides a cancellation mechanism.
public final class EvaluationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var estimatedUnitCount = 0
    private var startedImportCount = 0
    private var completedUnitCount = 0
    private var _fractionCompleted: Double?
    private var _isFinished = false
    private var _isCancelled = false
    private var cancellationHandler: CancellationHandler = { false }

    public init() {}
}

public extension EvaluationProgress {
    /// The completed fraction, or `nil` if evaluation has not started.
    var fractionCompleted: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _fractionCompleted
    }

    /// Whether cancellation has been requested.
    var isCancelled: Bool {
        lock.lock()
        let cancellationHandler = cancellationHandler
        let isCancelled = _isCancelled
        lock.unlock()
        return isCancelled || cancellationHandler()
    }

    /// Whether evaluation completed without being cancelled.
    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFinished
    }

    /// Requests cancellation of the evaluation.
    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}

extension EvaluationProgress {
    func beginTracking(
        program: Program,
        isCancelled: @escaping CancellationHandler
    ) {
        beginTracking(importCount: program.importCount, isCancelled: isCancelled)
    }

    func beginTracking(importCount: Int = 0, isCancelled: @escaping CancellationHandler) {
        lock.lock()
        estimatedUnitCount = 1 + importCount
        startedImportCount = 0
        completedUnitCount = 0
        _fractionCompleted = 0
        _isFinished = false
        cancellationHandler = isCancelled
        lock.unlock()
    }

    func endTracking() {
        lock.lock()
        cancellationHandler = { false }
        lock.unlock()
    }

    func beginImport() {
        lock.lock()
        startedImportCount += 1
        if startedImportCount >= estimatedUnitCount {
            estimatedUnitCount += 1
        }
        lock.unlock()
    }

    func discoveredImports(in program: Program) {
        discoveredImports(count: program.importCount)
    }

    func discoveredImports(count: Int) {
        lock.lock()
        estimatedUnitCount += count
        lock.unlock()
    }

    func completeUnit() {
        lock.lock()
        completedUnitCount += 1
        let fraction = min(Double(completedUnitCount) / Double(estimatedUnitCount), 0.98)
        _fractionCompleted = max(_fractionCompleted ?? 0, fraction)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        completedUnitCount = estimatedUnitCount
        _fractionCompleted = 1
        _isFinished = true
        lock.unlock()
    }
}
