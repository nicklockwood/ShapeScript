//
//  EvaluationDelegate.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 29/12/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public protocol EvaluationDelegate: AnyObject {
    func resolveURL(for path: String) -> URL
    func importGeometry(for url: URL) throws -> Geometry?
    func debugLog(_ values: [AnyHashable])
}

public extension EvaluationDelegate {
    func importGeometry(for _: URL) throws -> Geometry? { nil }
    func debugLog(_: [AnyHashable]) {}
}

/// Forwards file resolution and imports while suppressing debug output.
public final class SilentDelegate: EvaluationDelegate {
    private let delegate: EvaluationDelegate

    public init(_ delegate: EvaluationDelegate) {
        self.delegate = delegate
    }

    public func resolveURL(for path: String) -> URL {
        delegate.resolveURL(for: path)
    }

    public func importGeometry(for url: URL) throws -> Geometry? {
        try delegate.importGeometry(for: url)
    }
}
