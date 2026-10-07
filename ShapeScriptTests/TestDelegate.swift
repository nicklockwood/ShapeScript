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

func evaluate(
    _ program: Program,
    delegate: EvaluationDelegate?,
    isCancelled: @escaping CancellationHandler = { false }
) throws -> Scene {
    try ShapeScript.evaluate(
        program,
        delegate: delegate,
        cache: GeometryCache(diskCache: nil),
        isCancelled: isCancelled
    )
}
