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

    func testLogNegativeDouble() {
        let input = -4.5
        XCTAssertEqual(input.logDescription, "-4.5")
        XCTAssertEqual(input.nestedLogDescription, "-4.5")
    }

    func testLogDoubleAsInt() {
        let input = 4.0
        XCTAssertEqual(input.logDescription, "4")
        XCTAssertEqual(input.nestedLogDescription, "4")
    }

    func testLogLargeDoubleAsInt() {
        let input = 4000000000.0
        XCTAssertEqual(input.logDescription, "4000000000")
        XCTAssertEqual(input.nestedLogDescription, "4000000000")
    }

    func testLogNegativeDoubleAsInt() {
        let input = -4.0
        XCTAssertEqual(input.logDescription, "-4")
        XCTAssertEqual(input.nestedLogDescription, "-4")
    }

    func testLogVeryLargeDouble() {
        let input = 1.01e20
        XCTAssertEqual(input.logDescription, "101000000000000000000")
        XCTAssertEqual(input.nestedLogDescription, "101000000000000000000")
    }

    func testLogSmallDouble() {
        let input = 0.0001
        XCTAssertEqual(input.logDescription, "0.0001")
        XCTAssertEqual(input.nestedLogDescription, "0.0001")
    }

    func testLogVerySmallDouble() {
        let input = 0.00001
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogVerySmallNegativeDouble() {
        let input = -0.00001
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogVeryVerySmallDouble() {
        let input = 0.000000001
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogVeryVerySmallNegativeDouble() {
        let input = -0.000000001
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogVeryPreciseDouble() {
        let input = 0.10001
        XCTAssertEqual(input.logDescription, "0.1")
        XCTAssertEqual(input.nestedLogDescription, "0.1")
    }

    func testLogLargeVeryPreciseDouble() {
        let input = 4000.12001
        XCTAssertEqual(input.logDescription, "4000.12")
        XCTAssertEqual(input.nestedLogDescription, "4000.12")
    }

    func testLogInfinity() {
        let input = Double.infinity
        XCTAssertEqual(input.logDescription, "∞")
        XCTAssertEqual(input.nestedLogDescription, "∞")
    }

    func testLogNegativeInfinity() {
        let input = -Double.infinity
        XCTAssertEqual(input.logDescription, "-∞")
        XCTAssertEqual(input.nestedLogDescription, "-∞")
    }

    func testNegativeZero() {
        let input = -0.0
        XCTAssertEqual(input.logDescription, "0")
        XCTAssertEqual(input.nestedLogDescription, "0")
    }

    func testLogNaN() {
        let input = Double.nan
        XCTAssertEqual(input.logDescription, "NaN")
        XCTAssertEqual(input.nestedLogDescription, "NaN")
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
        let input = Color(1, 0, 0, 1)
        XCTAssertEqual(input.logDescription, "1 0 0")
        XCTAssertEqual(input.nestedLogDescription, "(1 0 0)")
    }

    func testTranslucentColor() {
        let input = Color(1, 0, 0, 0.5)
        XCTAssertEqual(input.logDescription, "1 0 0 0.5")
        XCTAssertEqual(input.nestedLogDescription, "(1 0 0 0.5)")
    }

    func testMonochromeOpaqueColor() {
        let input = Color(1, 1, 1, 1)
        XCTAssertEqual(input.logDescription, "1 1 1")
        XCTAssertEqual(input.nestedLogDescription, "(1 1 1)")
    }

    func testMonochromeTranslucentColor() {
        let input = Color(0.5, 0.5, 0.5, 0.5)
        XCTAssertEqual(input.logDescription, "0.5 0.5 0.5 0.5")
        XCTAssertEqual(input.nestedLogDescription, "(0.5 0.5 0.5 0.5)")
    }

    // MARK: Textures

    func testTextureFile() {
        let input = Texture.file(name: "Foo", url: URL(fileURLWithPath: "/foo/bar"), intensity: 1)
        XCTAssertEqual(input.logDescription, "/foo/bar")
        XCTAssertEqual(input.nestedLogDescription, "\"/foo/bar\"")
    }

    func testTextureData() {
        let input = Texture.data(Data(), intensity: 1)
        XCTAssertEqual(input.logDescription, "texture { #data }")
        XCTAssertEqual(input.nestedLogDescription, "texture")
    }

    // MARK: Materials

    func testDefaultMaterial() {
        let input = Material.default
        XCTAssertEqual(input.logDescription, "material { default }")
        XCTAssertEqual(input.nestedLogDescription, "material")
    }

    func testColorMaterial() {
        let input = Material(color: .red)
        XCTAssertEqual(input.logDescription, "material { color 1 0 0 }")
        XCTAssertEqual(input.nestedLogDescription, "material")
    }

    func testPBRMaterial() {
        let input = Material(
            opacity: .color(.gray),
            diffuse: .color(.red),
            metallicity: .color(.white),
            roughness: nil,
            glow: nil
        )
        XCTAssertEqual(input.logDescription, """
        material {
            opacity 0.5
            color 1 0 0
            metallicity 1
        }
        """)
        XCTAssertEqual(input.nestedLogDescription, "material")
    }

    // MARK: MaterialProperties

    func testTextureFileMaterial() {
        let input = MaterialProperty.texture(.file(name: "Foo", url: URL(fileURLWithPath: "/foo/bar"), intensity: 1))
        XCTAssertEqual(input.logDescription, "/foo/bar")
        XCTAssertEqual(input.nestedLogDescription, "\"/foo/bar\"")
    }

    // MARK: Paths

    func testPath() {
        let input = Path.square()
        XCTAssertEqual(input.logDescription, "path { points 5 }")
        XCTAssertEqual(input.nestedLogDescription, "path")
    }

    func testSubpaths() {
        #if !os(Linux) // For some reason this test crashes on Linux
        let input = Path(subpaths: [.square(), .circle()])
        XCTAssertEqual(input.logDescription, "path { subpaths 2 }")
        XCTAssertEqual(input.nestedLogDescription, "path")
        #endif
    }

    // MARK: Geometry

    func testDefaultCubeGeometry() {
        let context = EvaluationContext(source: "", delegate: nil)
        let input = Geometry(type: .cube, in: context)
        XCTAssertEqual(input.logDescription, "cube")
        XCTAssertEqual(input.nestedLogDescription, "cube")
    }

    func testCubeGeometry() {
        let context = EvaluationContext(source: "", delegate: nil)
        context.transform = Transform(scale: -.one)
        let input = Geometry(type: .cube, in: context)
        XCTAssertEqual(input.logDescription, "cube { size -1 }")
        XCTAssertEqual(input.nestedLogDescription, "cube")
    }

    func testCubeGeometry2() {
        let context = EvaluationContext(source: "", delegate: nil)
        context.transform = Transform(offset: Vector(1, 2), scale: -.one)
        let input = Geometry(type: .cube, in: context)
        XCTAssertEqual(input.logDescription, """
        cube {
            size -1
            position 1 2 0
        }
        """)
        XCTAssertEqual(input.nestedLogDescription, "cube")
    }

    func testMeshGeometry() {
        let context = EvaluationContext(source: "", delegate: nil)
        let input = Geometry(type: .mesh(.init([
            Polygon([
                Vector(0, 0),
                Vector(1, 0),
                Vector(1, 1),
            ])!,
        ])), in: context)
        XCTAssertEqual(input.logDescription, "mesh { polygons 1 }")
        XCTAssertEqual(input.nestedLogDescription, "mesh")
    }

    func testMeshGeometry2() {
        let context = EvaluationContext(source: "", delegate: nil)
        context.name = "Mesh"
        let input = Geometry(type: .mesh(.init([
            Polygon([
                Vector(0, 0),
                Vector(1, 0),
                Vector(1, 1),
            ])!,
        ])), in: context)
        XCTAssertEqual(input.logDescription, """
        mesh {
            name "Mesh"
            polygons 1
        }
        """)
        XCTAssertEqual(input.nestedLogDescription, "mesh")
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

    // MARK: Objects

    func testObjectWithOneKey() {
        let input = ["foo": 1]
        XCTAssertEqual(input.logDescription, "object { foo 1 }")
        XCTAssertEqual(input.nestedLogDescription, "object")
    }

    func testObjectWithMultipleKeys() {
        let input = ["foo": 1, "bar": 2]
        XCTAssertEqual(input.logDescription, """
        object {
            bar 2
            foo 1
        }
        """)
        XCTAssertEqual(input.nestedLogDescription, "object")
    }

    func testEmptyObject() {
        let input = [String: Any]()
        XCTAssertEqual(input.logDescription, "object {}")
        XCTAssertEqual(input.nestedLogDescription, "object")
    }

    // MARK: Ranges

    func testIntRange() {
        let input = RangeValue(from: 1, to: 9)
        XCTAssertEqual(input.logDescription, "1 to 9")
        XCTAssertEqual(input.nestedLogDescription, "(1 to 9)")
    }

    func testFloatRange() {
        let input = RangeValue(from: 1.5, to: 2.5)
        XCTAssertEqual(input.logDescription, "1.5 to 2.5")
        XCTAssertEqual(input.nestedLogDescription, "(1.5 to 2.5)")
    }

    func testReverseRange() {
        let input = RangeValue(from: 4, to: 2)
        XCTAssertEqual(input.logDescription, "4 to 2")
        XCTAssertEqual(input.nestedLogDescription, "(4 to 2)")
    }

    func testRangeWithStep() {
        let input = RangeValue(from: 0, to: 5, step: 2)
        XCTAssertEqual(input.logDescription, "0 to 5 step 2")
        XCTAssertEqual(input.nestedLogDescription, "(0 to 5 step 2)")
    }

    func testRangeWithDefaultStep() {
        let input = RangeValue(from: 0, to: 5, step: 1)
        XCTAssertEqual(input.logDescription, "0 to 5")
        XCTAssertEqual(input.nestedLogDescription, "(0 to 5)")
    }
}
