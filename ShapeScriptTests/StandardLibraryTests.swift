//
//  StandardLibraryTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 13/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

class StandardLibraryTests: XCTestCase {
    // MARK: Color

    func testColorInRoot() throws {
        let program = try parse("""
        color 1 0 0
        sphere
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInGroup() throws {
        let program = try parse("""
        group {
            color 1 0 0
            sphere
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInBuilder() throws {
        let program = try parse("""
        extrude {
            color 1 0 0
            square
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInShape() throws {
        let program = try parse("cube { color 1 0 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInPathShape() throws {
        let program = try parse("circle { color 1 0 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInPath() throws {
        let program = try parse("""
        path {
            color red
            point 0 1
            color blue
            point 0 -1
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInNestedPath() throws {
        let program = try parse("""
        path {
            path {
                color red
            }
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInSVGPath() throws {
        let program = try parse("""
        svgpath {
            color red
            "M150 0 L75 200 225 200 Z"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInText() throws {
        let program = try parse("""
        text {
            color 1 0 0
            "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testColorInBlock() throws {
        let program = try parse("""
        define foo {
            color 1 0 0
            cone
        }
        foo
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    func testColorInBlockCall() throws {
        let program = try parse("""
        define foo {
            cone
        }
        foo {
            color 1 0 0
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    // MARK: Texture

    func testTextureInRoot() throws {
        let program = try parse("""
        texture "Stars1.jpg"
        sphere
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testTextureInGroup() throws {
        let program = try parse("""
        group {
            texture "Stars1.jpg"
            sphere
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testTextureInBuilder() throws {
        let program = try parse("""
        extrude {
            texture "Stars1.jpg"
            square
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testTextureInShape() throws {
        let program = try parse("""
        cube { texture "Stars1.jpg" }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testTextureInPathShape() throws {
        let program = try parse("""
        circle { texture "Stars1.jpg" }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTextureInPath() throws {
        let program = try parse("""
        path {
            texture "Stars1.jpg"
            point 0 1
            point 0 -1
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTextureInNestedPath() throws {
        let program = try parse("""
        path {
            path {
                texture "Stars1.jpg"
            }
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTextureInSVGPath() throws {
        let program = try parse("""
        svgpath {
            texture "Stars1.jpg"
            "M150 0 L75 200 225 200 Z"
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTextureInText() throws {
        let program = try parse("""
        text {
            texture "Stars1.jpg"
            "Hello"
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTextureInBlock() throws {
        let program = try parse("""
        define foo {
            texture "Stars1.jpg"
            cone
        }
        foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testTextureInBlockCall() throws {
        let program = try parse("""
        define foo {
            cone
        }
        foo {
            texture "Stars1.jpg"
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testEmptyTexture() throws {
        let program = try parse("""
        print texture
        texture ""
        print texture
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["", ""])
    }

    // MARK: Detail

    func testDetailInRoot() throws {
        let program = try parse("""
        detail 8
        sphere
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInGroup() throws {
        let program = try parse("""
        group {
            detail 8
            sphere
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInBuilder() throws {
        let program = try parse("""
        extrude {
            detail 8
            square
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInShape() throws {
        let program = try parse("cube { detail 8 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInPathShape() throws {
        let program = try parse("circle { detail 8 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInPath() throws {
        let program = try parse("""
        path {
            detail 8
            point 0 1
            point 0 -1
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInNestedPath() throws {
        let program = try parse("""
        path {
            path {
                detail 8
            }
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInSVGPath() throws {
        let program = try parse("""
        svgpath {
            detail 4
            "M150 0 L75 200 225 200 Z"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInText() throws {
        let program = try parse("""
        text {
            detail 4
            "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInBlock() throws {
        let program = try parse("""
        define foo {
            detail 8
            cone
        }
        foo
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testDetailInBlockCall() throws {
        let program = try parse("""
        define foo {
            cone
        }
        foo {
            detail 8
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    // MARK: Smoothing

    func testSmoothingInRoot() throws {
        let program = try parse("""
        smoothing 0
        sphere
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testSmoothingInGroup() throws {
        let program = try parse("""
        group {
            smoothing 0
            sphere
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testSmoothingInBuilder() throws {
        let program = try parse("""
        extrude {
            smoothing 0.5
            circle
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testSmoothingInShape() throws {
        let program = try parse("cube { smoothing 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testSmoothingInPathShape() throws {
        let program = try parse("circle { smoothing 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSmoothingInPath() throws {
        let program = try parse("""
        path {
            smoothing 8
            point 0 1
            point 0 -1
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSmoothingInNestedPath() throws {
        let program = try parse("""
        path {
            path {
                smoothing 0
            }
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSmoothingInSVGPath() throws {
        let program = try parse("""
        svgpath {
            smoothing 0
            "M150 0 L75 200 225 200 Z"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSmoothingInText() throws {
        let program = try parse("""
        text {
            smoothing 0
            "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSmoothingInBlock() throws {
        let program = try parse("""
        define foo {
            smoothing 0
            cone
        }
        foo
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testSmoothingInBlockCall() throws {
        let program = try parse("""
        define foo {
            cone
        }
        foo {
            smoothing 0
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    // MARK: Font

    func testFontInRoot() throws {
        let program = try parse("""
        font "Helvetica"
        text "Hello"
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInGroup() throws {
        let program = try parse("""
        group {
            font "Helvetica"
            text "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInBuilder() throws {
        let program = try parse("""
        extrude {
            font "Helvetica"
            text "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInShape() throws {
        let program = try parse("""
        cube { font "Helvetica" }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("font", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testFontInPathShape() throws {
        let program = try parse("""
        circle { font "Helvetica" }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("font", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testFontInPath() throws {
        let program = try parse("""
        path {
            font "Helvetica"
            text "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInNestedPath() throws {
        let program = try parse("""
        path {
            path {
                font "Helvetica"
                text "Hello"
            }
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInSVGPath() throws {
        let program = try parse("""
        svgpath {
            font "Helvetica"
            "M150 0 L75 200 225 200 Z"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("font", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testMissingMoveInSVGPath() throws {
        let program = try parse("""
        svgpath {
            "M 80 80 A 45 45, 0, 0, 0, 125 125 L 125 80 Z"
            "A 45 45, 0, 1, 0, 275 125 L 275 80 Z"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInText() throws {
        let program = try parse("""
        text {
            font "Helvetica"
            "Hello"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInBlock() throws {
        let program = try parse("""
        define foo {
            font "Times"
            print font
        }
        foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["Times"])
    }

    func testFontInBlockCallScope() throws {
        let program = try parse("""
        define foo {
            print font
        }
        group {
            font "Times"
            foo
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["Times"])
    }

    func testFontInBlockCall() throws {
        let program = try parse("""
        define foo {
            print font
        }
        foo {
            font "Times"
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["Times"])
    }

    // MARK: Strings

    func testSplit() throws {
        let program = try parse("""
        define foo "hello world"
        define bar split foo " "
        print bar.first
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["hello"])
    }

    func testSplit2() throws {
        let program = try parse("""
        define foo split "hello world" " "
        print foo.second
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["world"])
    }

    func testJoin() throws {
        let program = try parse("""
        define foo "hello" "world"
        print join foo ", "
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["hello, world"])
    }

    func testTrim() throws {
        let program = try parse("""
        define foo "  hello world\\n"
        print trim foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, ["hello world"])
    }

    // MARK: Polygons

    func testPrintPolygonPath() throws {
        let program = try parse("""
        print polygon { sides 4 }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, [Geometry(
            type: .path(Path.polygon(sides: 4)),
            in: context
        )])
    }

    func testPrintPolygonFace() throws {
        let program = try parse("""
        print polygon {
            point 0
            point 1 0
            point 1 1
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertNotNil(delegate.log.first as? Euclid.Polygon)
    }

    func testPrintDefaultPolygon() throws {
        let program = try parse("""
        print polygon
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, [Geometry(
            type: .path(Path.polygon(sides: 5)),
            in: context
        )])
    }

    func testPolygonWithoutArguments() throws {
        let program = try parse("polygon")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssert(context.children.first?.value is Geometry)
    }

    func testPrintAmbiguousPolygon() throws {
        let program = try parse("""
        print polygon {
            sides 2
            point 0
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case let .assertionFailure(message)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssert(message.contains("points") && message.contains("sides"))
        }
    }

    func testDefinePolygonPath() throws {
        let program = try parse("""
        define foo polygon { sides 4 }
        print foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, [Geometry(
            type: .path(Path.polygon(sides: 4)),
            in: context
        )])
    }

    func testDefinePolygonFace() throws {
        let program = try parse("""
        define foo polygon {
            point 0
            point 1 0
            point 1 1
        }
        print foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertNotNil(delegate.log.first as? Euclid.Polygon)
    }

    func testPolygonPathPosition() throws {
        let program = try parse("""
        print polygon {
            position 1 0 0
            sides 4
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, [Geometry(
            type: .path(Path.polygon(sides: 4)),
            in: context
        ).transformed(by: .offset(Vector(1, 0, 0)))])
    }

    func testPolygonFacePosition() throws {
        let program = try parse("""
        print polygon {
            position 1 0 0
            point 0
            point 1 0
            point 1 1
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertNotNil(delegate.log.first as? Euclid.Polygon)
    }

    func testPolygonFacePointTransform() throws {
        let program = try parse("""
        print polygon {
            point 0
            point 1 0
            translate 1 1
            point 0
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertNotNil(delegate.log.first as? Euclid.Polygon)
    }

    // MARK: Hulls

    func testPathInHull() throws {
        let program = try parse("""
        hull { square }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssert(context.children.first?.value is Geometry)
    }

    func testMultiplePathsInHull() throws {
        let program = try parse("""
        hull {
            square
            rotate 0 0.5
            square
        }
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        _ = geometry.build { true }
        XCTAssertEqual(geometry.mesh?.bounds, Mesh.cube().bounds)
    }

    // MARK: Functions

    func testDot() {
        let program = "print dot((1 0) (0 1))"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testCross() {
        let program = "print cross((1 0) (0 1))"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0, 0.0, 1.0])
    }

    func testLength() {
        let program = "print length(3 4)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5.0])
    }

    func testLengthZero() {
        let program = "print length(0 0 0)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testNormalize() {
        let program = "print normalize(3 4)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.6, 0.8])
    }

    func testNormalizeZero() {
        let program = "print normalize(0 0 0 0)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0, 0.0, 0.0, 0.0])
    }

    // MARK: Commands

    func testSizeCommandWithConfusingParens() throws {
        let program = try parse("""
        cube {
            define y 2
            size 1 y (3)
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.transform.scale, Vector(1, 2, 3))
    }

    // MARK: Objects

    func testObjectConstructor() throws {
        let program = try parse("""
        define foo object {
            bar 5
            baz "hello"
        }
        print foo
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(delegate.log, [["bar": 5, "baz": "hello"] as [String: AnyHashable]])
    }
}
