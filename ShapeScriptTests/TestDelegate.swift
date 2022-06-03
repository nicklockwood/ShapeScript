//
//  TestDelegate.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 03/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

let testsDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()

class TestDelegate: EvaluationDelegate {
    func importGeometry(for _: URL) throws -> Geometry? {
        preconditionFailure()
    }

    var imports = [String]()
    func resolveURL(for name: String) -> URL {
        imports.append(name)
        return testsDirectory.appendingPathComponent(name)
    }

    var log = [AnyHashable?]()
    func debugLog(_ values: [AnyHashable]) {
        log += values
    }
}
