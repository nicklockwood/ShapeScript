//
//  InterpreterTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 08/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
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

    func resolveURL(for name: String) -> URL {
        testsDirectory.appendingPathComponent(name)
    }

    var log = [AnyHashable?]()
    func debugLog(_ values: [AnyHashable]) {
        log += values
    }
}

class InterpreterTests: XCTestCase {
    // MARK: Random numbers

    func testRandomNumberConsistency() {
        let context = EvaluationContext(source: "", delegate: nil)
        XCTAssertEqual(context.random.seed, 0)
        context.random = RandomSequence(seed: .random(in: 0 ..< 10))
        _ = context.random.next()
        let a = context.random.seed

        do {
            // Push a new block context
            let newContext = context.push(.group)
            XCTAssertEqual(a, newContext.random.seed) // test seed is not reset
            _ = newContext.random.next()
            XCTAssertNotEqual(a, newContext.random.seed)
            XCTAssertNotEqual(a, context.random.seed) // test original seed also affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push a new block context
            let newContext = context.push(.group)
            newContext.random = RandomSequence(seed: .random(in: 11 ..< 20))
            _ = newContext.random.next()
            XCTAssertNotEqual(5, newContext.random.seed)
            XCTAssertEqual(a, context.random.seed) // test original seed not affected
        }

        do {
            // Push a new block context
            let newContext = context.pushDefinition()
            XCTAssertEqual(a, newContext.random.seed) // test seed is not reset
            _ = newContext.random.next()
            XCTAssertNotEqual(a, newContext.random.seed)
            XCTAssertNotEqual(a, context.random.seed) // test original seed also affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push definition
            let newContext = context.pushDefinition()
            newContext.random = RandomSequence(seed: 0)
            _ = newContext.random.next()
            XCTAssertNotEqual(5, newContext.random.seed)
            XCTAssertEqual(a, context.random.seed) // test original seed not affected
        }

        do {
            // Push loop context
            context.pushScope { context in
                _ = context.random.next()
            }
            XCTAssertNotEqual(a, context.random.seed) // test original seed is affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push loop context
            context.pushScope { context in
                context.random = RandomSequence(seed: 99)
            }
            XCTAssertNotEqual(a, context.random.seed) // test original seed is affected
            XCTAssertEqual(context.random.seed, 99) // random state is preserved
            context.random = RandomSequence(seed: a) // reset seed
        }
    }

    // MARK: Name

    func testSetPrimitiveName() throws {
        let program = try parse("""
        cube { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
    }

    func testSetBuilderName() throws {
        let program = try parse("""
        extrude {
            name "Foo"
            circle
        }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
    }

    func testSetGroupName() throws {
        let program = try parse("""
        group {
            name "Foo"
            cube
            sphere
        }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
        XCTAssertNil(first.children.first?.name)
    }

    func testSetCustomBlockName() throws {
        let program = try parse("""
        define wheel {
            scale 1 0.2 1
            cylinder
        }
        wheel { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
        XCTAssert(first.children.isEmpty)
    }

    func testSetCustomGroupBlockName() throws {
        let program = try parse("""
        define wheels {
            scale 1 0.2 1
            cylinder
            translate 0 1 0
            cylinder
        }
        wheels { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
        XCTAssertNil(first.children.first?.name)
        XCTAssertEqual(first.children.count, 2)
    }

    func testSetPathBlockName() throws {
        let program = try parse("""
        define wheel {
            circle
        }
        wheel { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
        XCTAssert(first.children.isEmpty)
    }

    func testNameInvalidAtRoot() {
        let program = """
        name "Foo"
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("name", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testNameInvalidInDefine() {
        let program = """
        define foo {
            name "Foo"
            cube
        }
        foo
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("name", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Built-in symbol scope

    func testOverrideColorInRootScope() {
        let program = """
        print black
        define black white
        print black
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.black, Color.white])
    }

    func testReferenceOverriddenColorInBlockScope() {
        let program = """
        print black
        define black white
        define foo {
            print black
        }
        foo
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.black, Color.white])
    }

    func testeOverrideColorInBlockScope() {
        let program = """
        define black white
        define foo {
            define black red
            print black
        }
        foo
        print black
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red, Color.white])
    }

    // MARK: Option scope

    func testOptionValidInDefine() {
        let program = """
        define foo {
            option bar 5
        }
        foo { bar 5 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testOptionInvalidInPrimitive() {
        let program = """
        cube {
            option foo 5
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("option", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOptionInvalidAtRoot() {
        let program = "option foo 5"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("option", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Block scope

    func testLocalSymbolsNotPassedToCommand() {
        let program = """
        define foo {
            print baz
        }
        define bar {
            define baz 5
            foo
        }
        bar
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.range, program.range(of: "baz"))
            guard case .unknownSymbol("baz", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOptionsPassedToCommand() {
        let program = """
        define foo {
            option baz 0
            print baz
        }
        define bar {
            foo { baz 5 }
        }
        bar
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testGlobalSymbolsAvailableToCommand() {
        let program = """
        define baz 5
        define foo {
            print baz
        }
        define bar {
            foo
        }
        bar
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testOptionsNotSuggestedForTypoInShapeBlock() {
        let program = """
        cube {
            poption bar 0
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("poption", _)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssertNotEqual(error?.suggestion, "option")
        }
    }

    func testOptionsSuggestedForTypoInCustomBlock() {
        let program = """
        define foo {
            poption bar 0
        }
        foo
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("poption", _)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssertEqual(error?.suggestion, "option")
        }
    }

    // MARK: Position

    func testCumulativePosition() throws {
        let program = """
        translate 1 0 0
        cube { position 1 0 0 }
        """
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.transform.offset.x, 2)
    }

    func testPositionValidInPrimitive() {
        let program = """
        cube { position 1 0 0 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInGroup() {
        let program = """
        group { position 1 0 0 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInBuilder() {
        let program = """
        extrude {
            position 1 0 0
            circle
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInCSG() {
        let program = """
        difference {
            position 1 0 0
            cube
            sphere
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionInvalidAtRoot() {
        let program = """
        position 1 0 0
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("position", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPositionInvalidInDefine() {
        let program = """
        define foo {
            position 1 0 0
            cube
        }
        foo
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("position", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSetPositionWithTupleConstant() throws {
        let program = """
        define foo (1 0 0) 0
        cube {
            position foo
        }
        """
        let range = program.range(of: "foo", range: program.range(of: "position foo")!)!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "position",
                index: 0,
                expected: "vector",
                got: "vector, number"
            ), at: range))
        }
    }

    func testSetPositionWithTupleOfConstantAndLiteral() throws {
        let program = """
        define pos 1 0 0
        cube {
            position pos 7
        }
        """
        let range = program.range(of: "7")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "position", max: 1), at: range
            ))
        }
    }

    // MARK: Color

    func testSetColorWithParens() throws {
        let program = """
        color (1 0 0)
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testColorWithoutParens() throws {
        let program = """
        color 1 0 0
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetColorWithSingleNumber() throws {
        let program = """
        color 0
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.black])
    }

    func testSetColorWithConstant() throws {
        let program = """
        define red 1 0 0
        color red
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetColorWithTooManyElements() throws {
        let program = """
        color 1 0 0 0.5 0.9
        print color
        """
        let range = program.range(of: "0.9")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 4), at: range
            ))
        }
    }

    func testSetColorWithConstantWithTooManyElements() throws {
        let program = """
        define foo 1 0 0 0.5 0.9
        color foo
        print color
        """
        let range = program.range(of: "foo", range: program.range(of: "color foo")!)!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 4), at: range
            ))
        }
    }

    func testSetColorWithTuple() throws {
        let program = """
        color (1 0 0) 0.5
        print color
        """
        let range = program.range(of: "0.5")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 1), at: range
            ))
        }
    }

    func testSetColorWithTupleConstant() throws {
        let program = """
        define foo (1 0 0) 0.5
        color foo
        print color
        """
        let range = program.range(of: "foo", range: program.range(of: "color foo")!)!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "color",
                index: 0,
                expected: "color",
                got: "color, number"
            ), at: range))
        }
    }

    func testSetColorWithTupleOfConstantAndLiteral() throws {
        let program = """
        define foo 1 0 0
        color foo 0.5
        print color
        """
        let range = program.range(of: "0.5")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 1), at: range
            ))
        }
    }

    func testSetColorWithHexLiteral() throws {
        let program = """
        color #fff
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.white])
    }

    func testSetColorWithHexConstant() throws {
        let program = """
        define foo #fff
        color foo
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.white])
    }

    func testSetColorWithHexTuple() throws {
        let program = """
        define foo #fff
        color foo 0.5
        print color
        """
        let range = program.range(of: "0.5")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 1), at: range
            ))
        }
    }

    func testSetColourWithBritishSpelling() throws {
        let program = """
        colour red
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testGetColourWithBritishSpelling() throws {
        let program = """
        color grey
        print colour
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.gray])
    }

    // MARK: Texture

    func testSetTextureWithStringLiteral() throws {
        let program = """
        texture \"Stars.jpg\"
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars.jpg", url: testsDirectory.appendingPathComponent("Stars.jpg")
        )])
    }

    func testSetTextureWithStringConstant() throws {
        let program = """
        define image \"Stars.jpg\"
        texture image
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars.jpg", url: testsDirectory.appendingPathComponent("Stars.jpg")
        )])
    }

    func testSetTextureWithNonExistentImage() throws {
        let program = """
        texture \"Nope.jpg\"
        print texture
        """
        let range = program.range(of: "\"Nope.jpg\"")!
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope.jpg", at: testsDirectory.appendingPathComponent("Nope.jpg")
            ), at: range))
        }
    }

    func testSetTextureWithTuple() throws {
        let program = """
        texture \"Stars.jpg\" 1
        print texture
        """
        let range = program.range(of: "1")!
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "texture", max: 1), at: range
            ))
        }
    }

    // MARK: Background

    func testSetBackgroundColorWithParens() throws {
        let program = """
        background (1 0 0)
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetBackgroundColorWithoutParens() throws {
        let program = """
        background 1 0 0
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetBackgroundColorWithConstant() throws {
        let program = """
        define bg 1 0 0
        background bg
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetBackgroundColorWithColorConstant() throws {
        let program = """
        color 1 0 0
        background color
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetBackgroundColorWithTooManyElements() throws {
        let program = """
        background 1 0 0 0.5 0.9
        print background
        """
        let range = program.range(of: "0.9")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "background", max: 4), at: range
            ))
        }
    }

    func testSetBackgroundTextureWithStringLiteral() throws {
        let program = """
        background \"Stars.jpg\"
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars.jpg", url: testsDirectory.appendingPathComponent("Stars.jpg")
        )])
    }

    func testSetBackgroundTextureWithStringConstant() throws {
        let program = """
        define image \"Stars.jpg\"
        background image
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars.jpg", url: testsDirectory.appendingPathComponent("Stars.jpg")
        )])
    }

    func testSetBackgroundTextureWithTextureConstant() throws {
        let program = """
        texture \"Stars.jpg\"
        background texture
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars.jpg", url: testsDirectory.appendingPathComponent("Stars.jpg")
        )])
    }

    func testSetBackgroundTextureWithNonExistentImage() throws {
        let program = """
        background \"Nope.jpg\"
        print background
        """
        let range = program.range(of: "\"Nope.jpg\"")!
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope.jpg", at: testsDirectory.appendingPathComponent("Nope.jpg")
            ), at: range))
        }
    }

    // MARK: Font

    func testSetValidFont() throws {
        let program = try parse("font \"Courier\"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Courier")
    }

    func testSetValidFontWithUntrimmedSpace() throws {
        let program = try parse("font \" Courier \"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Courier")
    }

    func testSetInvalidFont() throws {
        #if canImport(CoreGraphics)
        let program = try parse("font \"foo\"")
        let range = program.source.range(of: "\"foo\"")!
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown font 'foo'")
            XCTAssertEqual(error?.range, range)
            guard case .unknownFont("foo", options: _)? = error?.type else {
                XCTFail()
                return
            }
        }
        XCTAssertNil(context.font)
        #endif
    }

    func testSetEmptyFontString() throws {
        #if canImport(CoreGraphics)
        let program = try parse("font \"\"")
        let range = program.source.range(of: "\"\"")!
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Font name cannot be blank")
            XCTAssertEqual(error?.range, range)
            guard case .unknownFont("", options: _)? = error?.type else {
                XCTFail()
                return
            }
        }
        XCTAssertNil(context.font)
        #endif
    }

    func testSetBlankFont() throws {
        #if canImport(CoreGraphics)
        let program = try parse("font \" \"")
        let range = program.source.range(of: "\" \"")!
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Font name cannot be blank")
            XCTAssertEqual(error?.range, range)
            guard case .unknownFont("", options: _)? = error?.type else {
                XCTFail()
                return
            }
        }
        XCTAssertNil(context.font)
        #endif
    }

    func testSetFontWithTuple() throws {
        #if canImport(CoreGraphics)
        let program = try parse("font \"Courier\" \"foo\"")
        let range = program.source.range(of: "\"foo\"")!
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected argument")
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "font", max: 1), at: range
            ))
        }
        XCTAssertNil(context.font)
        #endif
    }

    // MARK: Block invocation

    func testInvokePrimitive() {
        let program = "cube { size 2 }"
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokePrimitiveWithoutBlock() {
        let program = "cube"
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokeDefineWithoutBlock() {
        let program = """
        define foo {}
        foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokeBuilderWithoutBlock() {
        let program = "lathe"
        let range = program.range(of: "lathe")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "lathe", index: 0, type: "block"), at: range
            ))
        }
    }

    func testInvokeGroupWithoutBlock() {
        let program = "group"
        let range = program.range(of: "group")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "group", index: 0, type: "block"), at: range
            ))
        }
    }

    func testInvokeExtrudeWithSingleArgument() throws {
        let program = "extrude square"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .extrude([.square()], along: []))
    }

    func testInvokeExtrudeWithSingleArgumentInParens() throws {
        let program = "extrude(square)"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .extrude([.square()], along: []))
    }

    func testInvokeExtrudeWithMultipleArguments() throws {
        let program = "extrude square circle"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.children.map { $0.type }, [
            .extrude([.square()], along: []),
            .extrude([.circle()], along: []),
        ])
    }

    func testInvokeExtrudeWithSingleArgumentInsideExpression() throws {
        let program = "extrude text \"foo\""
        let scene = try evaluate(parse(program), delegate: nil)
        #if canImport(CoreText)
        XCTAssertEqual(
            // Note: rendering optimization means letters get added as separate
            // children, making it difficult to compare the entire text string
            scene.children.first?.children.first?.type,
            .extrude(Path.text("f"), along: [])
        )
        #endif
    }

    func testInvokeExtrudeWithSingleArgumentOfWrongType() {
        let program = "extrude sphere"
        let range = program.range(of: "sphere")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "extrude",
                index: 0,
                expected: "block",
                got: "mesh"
            ), at: range))
        }
    }

    func testInvokeXorWithMultipleArguments() throws {
        let program = "xor cube sphere"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .xor)
        XCTAssertEqual(scene.children.first?.children.map { $0.type }, [
            .cube, .sphere(segments: 16),
        ])
    }

    func testInvokeBlockInExpressionWithMultipleArgumentsWithoutParens() throws {
        let program = "print xor cube sphere"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual((delegate.log.first as? Geometry)?.type, .xor)
    }

    func testInvokeBlockInExpressionWithMultipleArgumentsInParens() throws {
        let program = "print (xor cube sphere)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual((delegate.log.first as? Geometry)?.type, .xor)
    }

    func testInvokeTextInExpressionWithoutParens() {
        let program = "print 1 + text \"foo\""
        let range = program.range(of: "text")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "text", index: 0, type: "block"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testInvokeTextInExpressionWithParensButWrongArgumentType() {
        let program = "print 1 + (text 2)"
        let range = program.range(of: "2")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "text",
                index: 0,
                expected: "block",
                got: "number"
            ), at: range))
        }
    }

    func testAttemptToExtrudeMesh() throws {
        let program = """
        extrude {
            cube
        }
        """
        let range = program.range(of: "cube")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unused value")
            XCTAssertEqual(error, RuntimeError(.unusedValue(type: "mesh"), at: range))
        }
    }

    func testExtrudeTextWithParens() throws {
        let program = """
        extrude {
            (text "foo")
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testExtrudeTextWithoutParens() throws {
        let program = """
        extrude {
            text "foo"
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testExtrudeAlongTextWithParens() throws {
        let program = """
        extrude {
            square { size 0.01 }
            along (text "foo")
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testExtrudeAlongTextWithoutParens() throws {
        let program = """
        extrude {
            square { size 0.01 }
            along text "foo"
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testExtrudeAlongMultiplePathsWithoutParens() {
        let program = """
        extrude {
            square { size 0.01 }
            along circle square
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testExtrudeAlongNumber() {
        let program = """
        extrude {
            square { size 0.01 }
            along 2
        }
        """
        let range = program.range(of: "2")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for along should be a path, not a number.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "along",
                index: 0,
                expected: "path",
                got: "number"
            ), at: range))
        }
    }

    func testExtrudeAlongPathAndNumber() {
        let program = """
        extrude {
            square { size 0.01 }
            along square 2
        }
        """
        let range = program.range(of: "2")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            // TODO: this message isn't really ideal - need different handling for paths arguments
            XCTAssertEqual(error?.hint, "The second argument for along should be a path, not a number.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "along",
                index: 1,
                expected: "path",
                got: "number"
            ), at: range))
        }
    }

    // MARK: Ranges

    func testRange() {
        let program = "print 0 to 3"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 0, to: 3)])
    }

    func testInvalidRange() {
        let program = "print 4 to 3"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 4, to: 3)])
    }

    func testNegativeRange() {
        let program = "print -3 to -2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: -3, to: -2)])
    }

    func testFloatRange() {
        let program = "print 0.5 to 1.5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 0.5, to: 1.5)])
    }

    func testRangeWithStep() {
        let program = "print 0.5 to 1.5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 0.5, to: 1.5)])
    }

    func testRangePrecedence() {
        let program = "print 1 + 2 to 5 * 3 step 1 + 1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 3, to: 15, step: 2)])
    }

    func testRangeWithNonNumericStartValue() {
        let program = "define range \"foo\" to 10"
        let range = program.range(of: "\"foo\"")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "start value",
                index: 0,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithNonNumericEndValue() {
        let program = "define range 1 to \"bar\""
        let range = program.range(of: "\"bar\"")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "end value",
                index: 0,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithNonNumericStepValue() {
        let program = "define range 1 to 5 step \"foo\""
        let range = program.range(of: "\"foo\"")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "step value",
                index: 0,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithZeroStepValue() {
        let program = "define range 1 to 5 step 0"
        let range = program.range(of: "0")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Assertion failure")
            XCTAssertEqual(error, RuntimeError(
                .assertionFailure("Step value must be nonzero"), at: range
            ))
        }
    }

    // MARK: For loops

    func testForLoopWithIndex() {
        let program = "for i in 1 to 3 { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1, 2, 3])
    }

    func testForLoopWithoutIndex() {
        let program = "for 1 to 3 { print 0 }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0, 0, 0])
    }

    func testForLoopWithInvalidRange() {
        let program = "for 3 to 1 { print 0 }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
    }

    func testForLoopWithNegativeRange() {
        let program = "for i in -3 to -2 { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-3, -2])
    }

    func testForLoopWithFloatRange() {
        let program = "for i in 0.5 to 1.5 { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.5, 1.5])
    }

    func testForLoopWithFloatStep() {
        let program = "for i in 0 to 1 step 0.5 { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0, 0.5, 1])
    }

    func testForLoopWithNonRangeExpression() {
        let program = "for 1 { print i }"
        let range = program.range(of: "1")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "range",
                index: 0,
                expected: "range or tuple",
                got: "number"
            ), at: range))
        }
    }

    func testForLoopWithNonRangeExpression2() {
        let program = "for i in \"foo\" { print i }"
        let range = program.range(of: "\"foo\"")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "range",
                index: 0,
                expected: "range or tuple",
                got: "string"
            ), at: range))
        }
    }

    func testForLoopWithTuple() {
        let program = "for i in (3 1 4 1 5) { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3, 1, 4, 1, 5])
    }

    func testForLoopWithSingleElementTuple() {
        let program = "for i in (5) { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testForLoopWithEmptyTuple() {
        let program = "for i in () { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
    }

    func testForLoopWithNonNumericTuple() {
        let program = "for i in (\"hello\" \"world\") { print i }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["hello", "world"])
    }

    func testForLoopWithRangeVariable() {
        let program = """
        define range 1 to 3
        for i in range { print i }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1, 2, 3])
    }

    func testForLoopWithTupleVariable() {
        let program = """
        define values 3 1 4 1 5
        for i in values { print i }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3, 1, 4, 1, 5])
    }

    func testForLoopWithSingleElementVariable() {
        let program = """
        define values 3
        for i in values { print i }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3])
    }

    func testForLoopWithExpressionInLoopRange() {
        let program = """
        define i 2
        for i + 1 to 3 + 2 step 2 - 1 { print "a" }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["a", "a", "a"])
    }

    func testForLoopWithColorProperty() {
        let program = "for i in color { print i }"
        let range = program.range(of: "color")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "range",
                index: 0,
                expected: "range or tuple",
                got: "color"
            ), at: range))
        }
    }

    // MARK: Functions

    func testInvokeMonadicFunction() {
        let program = "print cos pi"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [cos(Double.pi)])
    }

    func testInvokeMonadicFunctionWithNoArgs() {
        let program = "print cos"
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "cos", index: 0, type: "number"), at: range
            ))
        }
    }

    func testInvokeMonadicFunctionWithTwoArgs() {
        let program = "print cos 1 2"
        let range = program.range(of: "2")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "cos", max: 1), at: range
            ))
        }
    }

    func testInvokeDyadicFunction() {
        let program = "print pow 1 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [pow(1.0, 2.0)])
    }

    func testInvokeDyadicFunctionWithNoArgs() {
        let program = "print pow"
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 0, type: "pair"), at: range
            ))
        }
    }

    func testInvokeDyadicFunctionWithOneArg() {
        let program = "print pow 1"
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 1, type: "number"), at: range
            ))
        }
    }

    func testInvokeDyadicFunctionWithThreeArgs() {
        let program = "print pow 1 2 3"
        let range = program.range(of: "3")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "pow", max: 2), at: range
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParens() {
        let program = "print 1 + (sqrt 9) 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [4, 5])
    }

    func testInvokeFunctionInExpressionWithoutParens() {
        let program = "print 1 + sqrt 9"
        let range = program.range(of: "sqrt")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "sqrt", index: 0, type: "number"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButWrongArgumentType() {
        let program = "print 1 + (sqrt \"a\")"
        let range = program.range(of: "\"a\"")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "sqrt",
                index: 0,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument() {
        let program = "print 1 + (pow 1)"
        let range = program.range(of: ")")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 1, type: "number"),
                at: range.lowerBound ..< range.lowerBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument2() {
        let program = "print 1 + pow(1)"
        let range = program.range(of: ")")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 1, type: "number"),
                at: range.lowerBound ..< range.lowerBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument() {
        let program = "print 1 + (pow 1 2 3)"
        let range = program.range(of: "3")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "pow", max: 2), at: range
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument2() {
        let program = "print 1 + pow(1 2 3)"
        let range = program.range(of: "3")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "pow", max: 2), at: range
            ))
        }
    }

    func testMinFunction() {
        let program = "print min 1 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testMaxFunction() {
        let program = "print max 1 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    // MARK: Member lookup

    func testTupleVectorLookup() {
        let program = "print (1 0).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testOutOfBoundsTupleVectorLookup() {
        let program = "print (1 0).z"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testTooLongTupleVectorLookup() {
        let program = "print (1 2 3 4).x"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownMember("x", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleSizeHeightLookup() {
        let program = "print (1 0.5).height"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.5])
    }

    func testTupleSizeDepthLookup() {
        let program = "print (1 0.5).depth"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleRotationRollLookup() {
        let program = "print (1 0.5).roll"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1.0])
    }

    func testTupleRotationPitchLookup() {
        let program = "print (1 0.5).pitch"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testTupleRGBARedLookup() {
        let program = "print (0.1 0.2 0.3 0.4).red"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.1])
    }

    func testTupleRGBAlphaLookup() {
        let program = "print (0.1 0.2 0.3).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleIAGreenLookup() {
        let program = "print (0.1 0.2).green"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.1])
    }

    func testTupleIAAlphaLookup() {
        let program = "print (0.1 0.2).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.2])
    }

    func testTooLongTupleColorLookup() {
        let program = "print (1 2 3 4 5).red"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'red'")
            guard case .unknownMember("red", of: "tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testNonNumericColorLookup() {
        let program = "print (\"foo\" \"bar\").red"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'red'")
            guard case .unknownMember("red", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleNonexistentLookup() {
        let program = "print (1 2).foo"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'foo'")
            guard case .unknownMember("foo", of: "tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testColorWidthLookup() {
        let program = "color 1 0.5\nprint color.width"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown color member property 'width'")
            guard case .unknownMember("width", of: "color", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRotationXLookup() {
        let program = """
        cube {
            print orientation.x
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown rotation member property 'x'")
            guard case .unknownMember("x", of: "rotation", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRotationYawLookup() {
        let program = """
        cube {
            orientation 0.3 0.2 0.1
            print orientation.yaw
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.2])
    }

    func testTupleOrdinalLookup() {
        let program = "define col 1 0.5\nprint col.second"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.5])
    }

    func testTupleOrdinalOutOfBoundsLookup() {
        let program = "define col 1 0.5\nprint col.third"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'third'")
            guard case .unknownMember("third", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleVeryHighOrdinalLookups() {
        let numbers = (1 ... 99).map { $0.description }.joined(separator: " ")
        let program = """
        define foo \(numbers)
        print foo.tenth
        print foo.nineteenth
        print foo.twentythird
        print foo.thirtyninth
        print foo.fortyseventh
        print foo.fiftythird
        print foo.sixtyeighth
        print foo.seventyfirst
        print foo.eightysixth
        print foo.ninetysecond
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10, 19, 23, 39, 47, 53, 68, 71, 86, 92])
    }

    func testSingleValueOrdinalLookup() {
        let program = """
        define foo 10
        print foo.first
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10])
    }

    func testSingleNumberXComponentLookup() {
        let program = """
        define foo 10
        print foo.x
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10])
    }

    func testSingleVectorYComponentLookup() {
        let program = """
        define foo 1 2 3
        define bar foo
        print bar.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    func testSingleVectorColorComponentLookup() {
        let program = """
        define foo color
        define bar foo
        print bar.red
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testMeshComponentLookup() {
        let program = """
        print (fill { circle }).x
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown mesh member property 'x'")
            guard case .unknownMember("x", of: "mesh", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testMemberPrecedence() {
        let program = """
        define a 0.5 0.3
        define b 0.2 0.4
        print a.x * b.x + a.y * b.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.22])
    }

    func testMemberChaining() {
        let program = """
        define a (1 2 3) (4 5 6)
        print a.second.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    // MARK: Recursion

    func testRecursiveLookupInDefine() {
        let program = """
        define foo {
            foo
        }
        foo
        """
        let range = program.range(of: "foo", range: program.range(of: "{\n    foo"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.range, range)
            guard case .assertionFailure("Too much recursion")? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRecursiveWhenCallingBlock() {
        let program = """
        define foo {
            cube {
                position foo
            }
        }
        foo
        """
        let range = program.range(of: "foo", range: program.range(of: "position foo"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.range, range)
            guard case .assertionFailure("Too much recursion")? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRecursiveMemberLookup() {
        let program = """
        define foo {
            cube {
                position foo.x
            }
        }
        foo
        """
        let range = program.range(of: "foo", range: program.range(of: "position foo"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.range, range)
            guard case .assertionFailure("Too much recursion")? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Edit distance

    func testEditDistance() {
        XCTAssertEqual("foo".editDistance(from: "fob"), 1)
        XCTAssertEqual("foo".editDistance(from: "boo"), 1)
        XCTAssertEqual("foo".editDistance(from: "bar"), 3)
        XCTAssertEqual("aba".editDistance(from: "bbb"), 2)
        XCTAssertEqual("foob".editDistance(from: "foo"), 1)
        XCTAssertEqual("foo".editDistance(from: "foob"), 1)
        XCTAssertEqual("foo".editDistance(from: "Foo"), 1)
        XCTAssertEqual("FOO".editDistance(from: "foo"), 3)
    }

    func testEditDistanceWithEmptyStrings() {
        XCTAssertEqual("foo".editDistance(from: ""), 3)
        XCTAssertEqual("".editDistance(from: "foo"), 3)
        XCTAssertEqual("".editDistance(from: ""), 0)
    }
}
