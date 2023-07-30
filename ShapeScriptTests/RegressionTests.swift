//
//  RegressionTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 27/07/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private let projectDirectory: URL = testsDirectory.deletingLastPathComponent()

private let exampleURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: projectDirectory.appendingPathComponent("Examples"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }

private let testShapesURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: testsDirectory.appendingPathComponent("TestShapes"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }

final class RegressionTests: XCTestCase {
    func testExamples() throws {
        XCTAssertFalse(exampleURLs.isEmpty)
        XCTAssertFalse(testShapesURLs.isEmpty)
        for url in exampleURLs + testShapesURLs {
            let name = url.lastPathComponent
            let input = try String(contentsOf: url)
            let program = try parse(input)
            let delegate = TestDelegate(directory: url.deletingLastPathComponent())
            let context = EvaluationContext(source: program.source, delegate: delegate)
            XCTAssertNoThrow(try program.evaluate(in: context), "\(name) errored")
            let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
            XCTAssert(geometry.isWatertight, "\(name) was not watertight")
        }
    }
}
