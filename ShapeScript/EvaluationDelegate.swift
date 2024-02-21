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
    func shouldPauseAtBreakpoint(_ index: Int) -> Bool
    func debugLog(_ values: [AnyHashable])
}

public extension EvaluationDelegate {
    func importGeometry(for _: URL) throws -> Geometry? { nil }
    func shouldPauseAtBreakpoint(_: Int) -> Bool { false }
}
