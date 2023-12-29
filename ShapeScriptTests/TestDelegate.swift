//
//  TestDelegate.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 03/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

let testsDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent()

class TestDelegate: EvaluationDelegate {
    let directory: URL
    init(directory: URL = testsDirectory) {
        self.directory = directory
    }

    var imports = [String]()
    func resolveURL(for name: String) -> URL {
        imports.append(name)
        return directory.appendingPathComponent(name)
    }

    var log = [AnyHashable?]()
    func debugLog(_ values: [AnyHashable]) {
        log += values
    }
}
