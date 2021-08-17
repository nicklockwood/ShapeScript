//
//  LoggingTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 17/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

class LoggingTests: XCTestCase {
    // MARK: Non-loggable values

    func testLogNonLoggableValue() {
        let input = NSObject()
        XCTAssertEqual(String(logDescriptionFor: input), "\(input)")
        XCTAssertEqual(String(nestedLogDescriptionFor: input), "\(input)")
    }

    func testLogNullValue() {
        let input: Any = String?.none as Any
        XCTAssertEqual(String(logDescriptionFor: input), "nil")
        XCTAssertEqual(String(nestedLogDescriptionFor: input), "nil")
    }

    func testLogArrayContainingNullValues() {
        let input: [Any?] = [nil, "hello"]
        XCTAssertEqual(String(logDescriptionFor: input), "nil \"hello\"")
        XCTAssertEqual(String(nestedLogDescriptionFor: input), "(nil \"hello\")")
    }

    // MARK: Strings

    func testLogString() {
        let input = "foo bar"
        XCTAssertEqual(input.logDescription, input)
        XCTAssertEqual(input.nestedLogDescription, "\"foo bar\"")
    }

    func testLogStringContainingQuotesSlashesAndLinebreaks() {
        let input = "\"foo\nbar\\baz\""
        XCTAssertEqual(input.logDescription, input)
        XCTAssertEqual(input.nestedLogDescription, "\"\\\"foo\\nbar\\\\baz\\\"\"")
    }

    // MARK: Numbers

    func testLogDouble() {
        let input = 4.5
        XCTAssertEqual(input.logDescription, "4.5")
        XCTAssertEqual(input.nestedLogDescription, "4.5")
    }

    func testLogDoubleAsInt() {
        let input = 4.0
        XCTAssertEqual(input.logDescription, "4")
        XCTAssertEqual(input.nestedLogDescription, "4")
    }

    func testLogVerySmallDouble() {
        let input = 0.00001
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogVeryPreciseDouble() {
        let input = 0.10001
        XCTAssertEqual(input.logDescription, "0.1")
        XCTAssertEqual(input.nestedLogDescription, "0.1")
    }

    // MARK: Vectors

    func testLogVector() {
        let input = Vector(1, 2, 3.5)
        XCTAssertEqual(input.logDescription, "1 2 3.5")
        XCTAssertEqual(input.nestedLogDescription, "(1 2 3.5)")
    }

    // MARK: Angles

    func testLogAngle() {
        let input = Angle.degrees(90)
        XCTAssertEqual(input.logDescription, "0.5")
        XCTAssertEqual(input.nestedLogDescription, "0.5")
    }

    // MARK: Rotations

    func testLogRotation() {
        let input = Rotation(roll: .degrees(90))
        XCTAssertEqual(input.logDescription, "0.5 0 0")
        XCTAssertEqual(input.nestedLogDescription, "(0.5 0 0)")
    }

    // MARK: Colors

    func testOpaqueColor() {
        let input = Color(r: 1, g: 0, b: 0, a: 1)
        XCTAssertEqual(input.logDescription, "1 0 0 1")
        XCTAssertEqual(input.nestedLogDescription, "(1 0 0 1)")
    }

    func testTranslucentColor() {
        let input = Color(r: 1, g: 0, b: 0, a: 0.5)
        XCTAssertEqual(input.logDescription, "1 0 0 0.5")
        XCTAssertEqual(input.nestedLogDescription, "(1 0 0 0.5)")
    }

    // MARK: Textures

    func testTextureFile() {
        let input = Texture.file(name: "Foo", url: URL(fileURLWithPath: "/foo/bar"))
        XCTAssertEqual(input.logDescription, "/foo/bar")
        XCTAssertEqual(input.nestedLogDescription, "\"/foo/bar\"")
    }

    func testTextureData() {
        let input = Texture.data(Data())
        XCTAssertEqual(input.logDescription, "texture { #data }")
        XCTAssertEqual(input.nestedLogDescription, "texture { #data }")
    }

    // MARK: MaterialProperties

    func testTextureFileMaterial() {
        let input = MaterialProperty
            .texture(.file(name: "Foo", url: URL(fileURLWithPath: "/foo/bar")))
        XCTAssertEqual(input.logDescription, "/foo/bar")
        XCTAssertEqual(input.nestedLogDescription, "\"/foo/bar\"")
    }

    // MARK: Paths

    func testPath() {
        let input = Path.square()
        XCTAssertEqual(input.logDescription, "path { points: 5 }")
        XCTAssertEqual(input.nestedLogDescription, "path")
    }

    func testSubpaths() {
        #if !os(Linux) // For some reason this test crashes on Linux
        let input = Path(subpaths: [.square(), .circle()])
        XCTAssertEqual(input.logDescription, "path { subpaths: 2 }")
        XCTAssertEqual(input.nestedLogDescription, "path")
        #endif
    }

    // MARK: Geometry

    func testCubeGeometry() {
        let context = EvaluationContext(source: "", delegate: nil)
        let input = Geometry(type: .cube, in: context)
        XCTAssertEqual(input.logDescription, """
        cube {
            size: 1 1 1
            position: 0 0 0
            orientation: 0 0 0
        }
        """)
        XCTAssertEqual(input.nestedLogDescription, "cube")
    }

    // MARK: Optionals

    func testNonNilOptional() {
        let input: String? = "foo"
        XCTAssertEqual(input.logDescription, "foo")
        XCTAssertEqual(input.nestedLogDescription, "\"foo\"")
    }

    func testNilOptional() {
        let input: String? = nil
        XCTAssertEqual(input.logDescription, "nil")
        XCTAssertEqual(input.nestedLogDescription, "nil")
    }

    // MARK: Arrays

    func testNumberArray() {
        let input = [1, 2, 3]
        XCTAssertEqual(input.logDescription, "1 2 3")
        XCTAssertEqual(input.nestedLogDescription, "(1 2 3)")
    }

    func testNestedNumberArray() {
        let input: [Any] = [1, [1, 2, 3], 4]
        XCTAssertEqual(input.logDescription, "1 (1 2 3) 4")
        XCTAssertEqual(input.nestedLogDescription, "(1 (1 2 3) 4)")
    }

    func testNestedStringArray() {
        let input: [Any] = ["foo", ["bar", "baz"]]
        XCTAssertEqual(input.logDescription, "\"foo\" (\"bar\" \"baz\")")
        XCTAssertEqual(input.nestedLogDescription, "(\"foo\" (\"bar\" \"baz\"))")
    }
}
