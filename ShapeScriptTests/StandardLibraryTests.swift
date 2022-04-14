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

private let testsDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()

private class TestDelegate: EvaluationDelegate {
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
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("color", _)? = error?.type else {
                XCTFail()
                return
            }
        }
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
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("texture", _)? = error?.type else {
                XCTFail()
                return
            }
        }
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
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("detail", _)? = error?.type else {
                XCTFail()
                return
            }
        }
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
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("smoothing", _)? = error?.type else {
                XCTFail()
                return
            }
        }
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
            font "Helvetica"
            text "Hello"
        }
        foo
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
    }

    func testFontInBlockCall() throws {
        let program = try parse("""
        define foo {
            text "Hello"
        }
        foo {
            font "Helvetica"
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
}
