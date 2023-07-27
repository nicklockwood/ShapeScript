//
//  RegressionTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 27/07/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private let projectDirectory: URL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent().deletingLastPathComponent()

private let examplesDirectory: URL = projectDirectory
    .appendingPathComponent("Examples")

private let exampleURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(atPath: examplesDirectory.path)
    .map { URL(fileURLWithPath: $0, relativeTo: examplesDirectory) }
    .filter { $0.pathExtension == "shape" }

final class RegressionTests: XCTestCase {
    func testExamples() throws {
        for url in exampleURLs {
            let input = try String(contentsOf: url)
            let program = try parse(input)
            let delegate = TestDelegate(directory: examplesDirectory)
            let context = EvaluationContext(source: program.source, delegate: delegate)
            XCTAssertNoThrow(try program.evaluate(in: context))
            let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
            XCTAssert(geometry.isWatertight)
        }
    }
}
