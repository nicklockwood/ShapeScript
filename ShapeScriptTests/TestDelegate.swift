//
//  TestDelegate.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 03/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Foundation

let testsDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent()

extension RuntimeErrorType {
    static func typeMismatch(for name: String, expected: String, got: String) -> Self {
        .typeMismatch(for: name, index: -1, expected: expected, got: got)
    }

    static func missingArgument(for name: String, type: String) -> Self {
        .missingArgument(for: name, index: 0, type: type)
    }

    static func missingArgument(for name: String, type: ValueType) -> Self {
        .missingArgument(for: name, index: 0, type: type.errorDescription)
    }
}

final class TestDelegate: EvaluationDelegate {
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
