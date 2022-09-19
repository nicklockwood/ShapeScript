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

private func expressionType(_ expression: String) throws -> ValueType? {
    let program = try parse("define foo \(expression)")
    guard case let .define(_, definition) = program.statements.last?.type,
          case let .expression(expression) = definition.type
    else {
        XCTFail()
        return nil
    }
    let context = EvaluationContext(source: "", delegate: nil)
    return try expression.staticType(in: context)
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

    func testSetNumberBlockName() throws {
        let program = """
        define foo {
            42
        }
        print foo { name "Foo" }
        """
        let range = program.range(of: "foo", range: program.range(of: "print foo")!)!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.assertionFailure(
                "Blocks that return a number value cannot be assigned a name"
            ), at: range))
        }
    }

    func testSetTupleBlockName() throws {
        let program = """
        define foo {
            "bar"
            42
        }
        print foo { name "Foo" }
        """
        let range = program.range(of: "foo", range: program.range(of: "print foo")!)!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.assertionFailure(
                "Blocks that return a text value cannot be assigned a name"
            ), at: range))
        }
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

    func testNameInvalidInCircle() {
        let input = """
        circle { name "Foo" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'name'")
        }
    }

    func testNameInvalidInPath() {
        let input = """
        path { name "Foo" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'name'")
        }
    }

    func testNameInvalidInText() {
        let input = """
        text { name "Foo" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'name'")
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

    func testOverrideColorInBlockScope() {
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

    func testOptionValidInBlockDefine() {
        let program = """
        define foo {
            option bar 5
        }
        foo { bar 5 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testOptionInvalidInFunctionDefine() {
        let program = """
        define foo() {
            option bar 5
        }
        foo()
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'option'")
            XCTAssertEqual(error?.hint, "The option command is not available in"
                + " this context. Did you mean 'define'?")
            guard case .unknownSymbol("option", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOptionInvalidInConditionalScope() {
        let program = """
        define foo {
            if true {
                option bar 5
            }
        }
        foo {}
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("option", _)? = error?.type else {
                XCTFail()
                return
            }
        }
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

    func testDuplicateOptionsPassedToCommand() {
        let program = """
        define foo {
            option baz 0
            print baz
        }
        define bar {
            foo {
                baz 5
                baz 6
            }
        }
        bar
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [6])
    }

    func testOptionDefaultValueFromGlobalConstant() {
        let program = """
        define baz 5
        define foo {
            option bar baz
            print bar
        }
        foo
        foo { bar 6 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5, 6])
    }

    func testOptionDefaultValueFromLocalConstant() {
        let program = """
        define foo {
            define baz 5
            option bar baz
            print bar
        }
        foo
        foo { bar 6 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5, 6])
    }

    func testOptionTypeEvaluationDoesNotChangeSeed() {
        let program = """
        seed 1
        define foo {
            option bar rnd
            print bar
        }
        foo
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.23645552527159452])
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

    func testDuplicatePositionCommand() throws {
        let program = """
        cube {
            position 1
            position 2
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
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
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithTuple2() throws {
        let program = """
        color (1 0 0 1) 0.5
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithTupleConstant() throws {
        let program = """
        define foo (1 0 0) 0.5
        color foo
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithTupleOfConstantAndLiteral() throws {
        let program = """
        define foo 1 0 0
        color foo 0.5
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithTupleOfConstantAndLiteral2() throws {
        let program = """
        define foo 1 0 0 1
        color foo 0.5
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithTupleOfConstantAndLiteral3() throws {
        let program = """
        define foo (1 0 0) 0.5
        color foo
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
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
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 1, 1, 0.5)])
    }

    func testSetColorWithHexTuple2() throws {
        let program = """
        color #f000 0.5
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithHexTuple3() throws {
        let program = """
        define foo #fff 0.5
        color foo
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 1, 1, 0.5)])
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

    func testColorInCube() throws {
        let program = try parse("cube { color 1 0 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    func testColorInCircle() throws {
        let program = try parse("circle { color 1 0 0 }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        switch geometry.type {
        case let .path(path):
            XCTAssertEqual(path.points.first?.color, .red)
        default:
            XCTFail()
        }
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
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        switch geometry.type {
        case let .path(path):
            XCTAssertEqual(path.points.first?.color, .red)
            XCTAssertEqual(path.points.last?.color, .blue)
        default:
            XCTFail()
        }
    }

    func testNestedPathColor() throws {
        let program = try parse("""
        path {
            color red
            circle
            color green
            square
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        switch geometry.type {
        case let .path(path):
            XCTAssertEqual(path.subpaths.first?.points.first?.color, .red)
            XCTAssertEqual(path.subpaths.last?.points.first?.color, .green)
        default:
            XCTFail()
        }
    }

    func testColorInText() throws {
        let program = try parse("""
        text {
            color 1 0 0
            "Hello"
            color 0 0 1
            "World"
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        #if canImport(CoreText)
        let line1 = try XCTUnwrap(context.children.first?.value as? Geometry)
        switch line1.type {
        case let .path(path):
            XCTAssertEqual(path.points.first?.color, .red)
        default:
            XCTFail()
        }
        let line2 = try XCTUnwrap(context.children.last?.value as? Geometry)
        switch line2.type {
        case let .path(path):
            XCTAssertEqual(path.points.first?.color, .blue)
        default:
            XCTFail()
        }
        #endif
    }

    // MARK: Texture

    func testSetTextureWithStringLiteral() throws {
        let program = """
        texture "Stars1.jpg"
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetTextureWithStringConstant() throws {
        let program = """
        define image "Stars1.jpg"
        texture image
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetTextureWithStringInterpolation() throws {
        let program = """
        texture ("Stars" 1 ".jpg")
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetTextureWithStringInterpolationWithoutParens() throws {
        let program = """
        texture "Stars" 1 ".jpg"
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetTextureWithInterpolatedConstant() throws {
        let program = """
        define image "Stars" 1 ".jpg"
        texture image
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetTextureWithNonExistentImage() throws {
        let program = """
        texture "Nope.jpg"
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

    func testTextureInvalidInCircle() {
        let input = """
        circle { texture "Stars1.jpg" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'texture'")
        }
    }

    func testTextureInvalidInPath() {
        let input = """
        path { texture "Stars1.jpg" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'texture'")
        }
    }

    func testTextureInvalidInText() {
        let input = """
        text { texture "Stars1.jpg" }
        """
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(input), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'texture'")
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

    func testSetBackgroundColorWithSingleNumber() throws {
        let program = """
        background 0
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.black])
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
        background "Stars1.jpg"
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetBackgroundTextureWithStringConstant() throws {
        let program = """
        define image "Stars1.jpg"
        background image
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetBackgroundTextureWithStringInterpolation() throws {
        let program = """
        background ("Stars" 1 ".jpg")
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetBackgroundTextureWithInterpolatedConstant() throws {
        let program = """
        define image "Stars" 1 ".jpg"
        background image
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetBackgroundTextureWithTextureConstant() throws {
        let program = """
        texture "Stars1.jpg"
        background texture
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg")
        )])
    }

    func testSetBackgroundTextureWithNonExistentImage() throws {
        let program = """
        background "Nope.jpg"
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

    func testSetBackgroundTextureWithNonExistentInterpolatedPath() throws {
        let program = """
        background "Nope" 1 ".jpg"
        print background
        """
        let range = program.range(of: "\"Nope\" 1 \".jpg\"")!
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope1.jpg", at: testsDirectory.appendingPathComponent("Nope1.jpg")
            ), at: range))
        }
    }

    func testCameraBackgroundNotDefaultedToClear() throws {
        let program = """
        camera {}
        background red
        """
        let scene = try evaluate(parse(program), delegate: nil)
        let camera = try XCTUnwrap(scene.cameras.first)
        XCTAssertNil(camera.camera?.background)
    }

    // MARK: Font

    func testSetValidFont() throws {
        let program = try parse("font \"Courier\"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Courier")
    }

    func testGetValidFont() throws {
        let program = """
        font "Courier"
        print font
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["Courier"])
    }

    func testSetValidFontWithStringInterpolation() throws {
        let program = try parse("font (\"Cou\" \"rier\")")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Courier")
    }

    func testSetValidFontWithStringInterpolationWithoutParens() throws {
        let program = try parse("font \"Cou\" \"rier\"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Courier")
    }

    func testSetValidFontWithInterpolatedConstant() throws {
        let program = try parse("""
        define name "Cou" "rier"
        font name
        """)
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
        XCTAssertEqual(context.font, "")
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
        XCTAssertEqual(context.font, "")
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
        XCTAssertEqual(context.font, "")
        #endif
    }

    func testSetFontWithFile() throws {
        #if canImport(CoreGraphics)
        let program = try parse("font \"EdgeOfTheGalaxyRegular-OVEa6.otf\"")
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.font, "Edge of the Galaxy Regular")
        #endif
    }

    // MARK: Import

    func testImport() throws {
        let program = try parse("import \"File1.shape\"")
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        try? program.evaluate(in: context) // Throws file not found, but we can ignore
        XCTAssertEqual(delegate.imports, ["File1.shape"])
    }

    func testImportWithStringInterpolation() throws {
        let program = try parse("import (\"File\" 1 \".shape\")")
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        try? program.evaluate(in: context) // Throws file not found, but we can ignore
        XCTAssertEqual(delegate.imports, ["File1.shape"])
    }

    func testImportWithStringInterpolationWithoutParens() throws {
        let program = try parse("import \"File\" 1 \".shape\"")
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        try? program.evaluate(in: context) // Throws file not found, but we can ignore
        XCTAssertEqual(delegate.imports, ["File1.shape"])
    }

    // MARK: Command invocation

    func testInvokeCommandInsideExpression() {
        let program = "print print 4"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'print'")
            guard case .unknownSymbol("print", _) = error?.type else {
                XCTFail()
                return
            }
        }
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
                .missingArgument(for: "lathe", index: 0, type: "path or block"), at: range
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
                .missingArgument(for: "group", index: 0, type: "mesh or block"), at: range
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
        XCTAssertEqual(
            scene.children.first?.type,
            .extrude([.square(), .circle()], along: [])
        )
    }

    func testInvokeExtrudeWithSingleArgumentInsideExpression() throws {
        let program = "extrude text \"foo\""
        let scene = try evaluate(parse(program), delegate: nil)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.first?.type, .extrude(Path.text("foo"), along: []))
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
                expected: "path or block",
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
                .missingArgument(for: "text", index: 0, type: "text or block"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testInvokeTextInExpressionWithParensButWrongArgumentType() {
        let program = "print 1 + (text cube)"
        let range = program.range(of: "cube")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "text",
                index: 0,
                expected: "text or block",
                got: "mesh"
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

    func testBlockReturnsGroupedMeshes() throws {
        let program = try parse("""
        define foo {
            cube { size 0.5 }
            cube { size 0.8 }
        }
        foo
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.children.count, 1)
    }

    func testBlockReturningPathInsidePath() throws {
        let program = try parse("""
        define foo path {
            point 0 0
            point 1 0
            point 1 1
        }
        path { foo }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
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
                got: "text"
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
                got: "text"
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
                got: "text"
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

    func testRangeExtendedByStepValue() {
        let program = """
        define range 1 to 5
        print range step 2
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 1, to: 5, step: 2)])
    }

    func testRangeWithStepExtendedByDifferentStepValue() {
        let program = """
        define range 1 to 5 step 3
        print range step 2
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 1, to: 5, step: 2)])
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
                got: "text"
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

    func testForLoopWithRangeVariableAndNoIndex() {
        let program = """
        define range 1 to 3
        for range { print "a" }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["a", "a", "a"])
    }

    func testForLoopWithRangeVariableExtendedByStepValue() {
        let program = """
        define range 1 to 5
        for i in range step 2 { print i }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1, 3, 5])
    }

    func testForLoopWithRangeVariableExtendedByStepValueAndNoIndex() {
        let program = """
        define range 1 to 5
        for range step 2 { print "a" }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["a", "a", "a"])
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
            XCTAssertEqual(error?.hint, "The argument for range should be a range or tuple, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "range",
                index: 0,
                expected: "range or tuple",
                got: "color"
            ), at: range))
        }
    }

    func testPrintTo() {
        let program = """
        define to 5
        print to
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            guard case .unexpectedToken(_, expected: "end value") = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPrintToInParens() {
        let program = """
        define to 5
        print (to)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    // MARK: If/else

    func testIfTrue() {
        let program = "if true { print true }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testIfFalse() {
        let program = "if false { print true }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
    }

    func testIfFalseElse() {
        let program = "if false { print true } else { print false }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testIfColor() {
        let program = "if red { print i }"
        let range = program.range(of: "red")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for condition should be a boolean, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "condition",
                index: 0,
                expected: "boolean",
                got: "color"
            ), at: range))
        }
    }

    func testIfNot() {
        let program = "if not 3 < 1 { print true }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    // MARK: Math functions

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
                got: "text"
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

    // MARK: Numeric comparison

    func testGT() {
        let program = "print 5 > 1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testGT2() {
        let program = "print 5 > 6"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testGT3() {
        let program = "print 5 > 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testGTE() {
        let program = "print 2 >= 1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testGTE2() {
        let program = "print 2 >= 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testGTE3() {
        let program = "print -2 >= -2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testLT() {
        let program = "print 1 < 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testLT2() {
        let program = "print 5 < 4"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testLT3() {
        let program = "print -2 < -2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testLTE() {
        let program = "print 1 <= 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testLTE2() {
        let program = "print 5 <= 4"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testLTE3() {
        let program = "print -2 <= -2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    // MARK: Equality

    func testNumbersEqual() {
        let program = "print 5 = 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testNumbersEqual2() {
        let program = "print 5 = 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testNumbersUnequal() {
        let program = "print 5 <> 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testNumbersUnequal2() {
        let program = "print 5 <> 4"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testStringsEqual() {
        let program = "print \"foo\" = \"foo\""
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testStringsEqual2() {
        let program = "print \"foo\" = \"bar\""
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testStringsUnequal() {
        let program = "print \"foo\" <> \"foo\""
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testStringsUnequal2() {
        let program = "print \"foo\" <> \"bar\""
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testTuplesEqual() {
        let program = "print 1 2 3 = 1 2 3"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1, 2, false, 2, 3])
    }

    func testTuplesEqual2() {
        let program = "print (1 2 3) = (1 2 3)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testFunctionResultsEqual() {
        let program = "print min(1 2) = 1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testMismatchedTypesEqual() {
        let program = "print \"foo\" = 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false])
    }

    func testMismatchedTypesUnequal() {
        let program = "print \"foo\" <> 5"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    // MARK: Boolean algebra

    func testLogicalAnd() {
        let program = """
        print true and true
        print true and false
        print false and true
        print false and false
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, false, false, false])
    }

    func testLogicalOr() {
        let program = """
        print true or true
        print true or false
        print false or true
        print false or false
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, true, false])
    }

    func testChainedLogicOperators() {
        let program = """
        print 1 > 3 or 1 < 3 and 2 = 2
        print 1 = 1 and 2 = 2 or false
        print false and true and true
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, false])
    }

    func testPrintOr() {
        let program = """
        define or 5
        print or
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            guard case .unexpectedToken(_, expected: "operand") = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPrintOrInParens() {
        let program = """
        define or 5
        print (or)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testNotVsComparisonOperators() {
        let program = """
        print not 1 > 3
        print not 1 < 3
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, false])
    }

    func testNotVsEquality() {
        let program = """
        print not true = false
        print not true <> false
        print not 5 = 6
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, false, true])
    }

    func testNotVsBooleanOperators() {
        let program = """
        print not true or false
        print not true or true
        print not true and true
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false, true, false])
    }

    func testNotVsParens() {
        let program = """
        print (not true) = false
        print not(true) = false
        print true = (not false)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, true])
    }

    func testPrintNot() {
        let program = """
        define not 5
        print not
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testMisspelledAndOperator() {
        let program = "print true AND false"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.suggestion, "and")
            guard case .unknownSymbol("AND", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testMisspelledOrOperator() {
        let program = "print true OR false"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.suggestion, "or")
            guard case .unknownSymbol("OR", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testLogicalOrShortCircuits() {
        let program = """
        define foo() {
            print "foo"
            true
        }
        print foo() or foo()
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["foo", true])
    }

    func testLogicalAndShortCircuits() {
        let program = """
        define foo() {
            print "foo"
            false
        }
        print foo() and foo()
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["foo", false])
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
            XCTAssertNotEqual(error?.suggestion, "red")
            guard case .unknownMember("red", of: "tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testEmptyTupleColorLookup() {
        let program = "print ().blue"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'blue'")
            XCTAssertNotEqual(error?.suggestion, "blue")
            guard case .unknownMember("blue", of: "tuple", _) = error?.type else {
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
        XCTAssertEqual(delegate.log.first as? Double ?? 0, 0.2, accuracy: epsilon)
    }

    func testTupleOrdinalLookup() {
        let program = "define col 1 0.5\nprint col.second"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log.first as? Double ?? 0, 0.5, accuracy: epsilon)
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

    func testRecursiveLookupInBlockDefinition() {
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

    func testRecursiveLookupInFunctionDefinition() {
        let program = """
        define foo() {
            foo()
        }
        foo
        """
        let range = program.range(of: "foo()", range: program.range(of: "{\n    foo()"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.range, range)
            guard case .assertionFailure("Too much recursion")? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRecursionWhenCallingBlock() {
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

    func testRecursionWhenCallingFunction() {
        let program = """
        define foo() {
            cube {
                position foo
            }
        }
        foo()
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

    // MARK: Custom functions

    func testCustomFunctionDoesntInheritChildrenOfParentScope() {
        let program = """
        sphere
        define foo(a b) { a + b }
        print foo(1 2)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3])
    }

    func testCustomFunctionInheritsSymbolsFromParentScope() {
        let program = """
        define c 3
        define foo(a b) { a + b + c }
        print foo(1 2)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [6])
    }

    func testCustomFunctionDoesntOverrideSymbolsFromParentScope() {
        let program = """
        define c 3
        define foo() {
            define c 4
        }
        foo()
        print c
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3])
    }

    func testCustomFunctionCanUseGlobalsymbols() {
        let program = """
        define foo(a b) { a + b + cos(pi) }
        print foo(1 2)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    func testCustomFunctionCanAffectMaterial() {
        let program = """
        define foo() { color 1 0 0 }
        foo()
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testCustomFunctionCanAffectTransform() throws {
        let program = try parse("""
        define foo() { translate 1 }
        foo()
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.childTransform.offset, Vector(1, 0, 0))
    }

    func testValidUseOfPointInCustomFunction() {
        let program = """
        define foo(x y) { point x y }
        path {
            foo(1 0)
            foo(1 1)
            foo(0 1)
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvalidUseOfPointInCustomFunction() {
        let program = """
        define foo(x y) { point x y }
        foo(1 0)
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil))
    }

    // MARK: Text command

    func testNumberConvertedToText() {
        let program = """
        text 5
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testNumberConvertedToTextInsidePrintCommand() {
        let program = """
        print text 5
        print text "5"
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        #if canImport(CoreText)
        XCTAssert(delegate.log.first is Path)
        XCTAssertEqual(delegate.log.count, 2)
        XCTAssertEqual(delegate.log.first, delegate.log.last)
        #endif
    }

    func testNumberConvertedToTextInBlock() {
        let program = """
        print text { 5 2 }
        print text { "5 2" }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        #if canImport(CoreText)
        XCTAssert(delegate.log.first is Path)
        guard delegate.log.count == 4 else {
            XCTFail()
            return
        }
        XCTAssertEqual(delegate.log[0], delegate.log[2])
        XCTAssertEqual(delegate.log[1], delegate.log[3])
        #endif
    }

    func testNumericLiteralFollowedByText() {
        let program = """
        text { 5 "foo" }
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        XCTAssertEqual(context.children.count, 4)
        #endif
    }

    func testNumericVariableFollowedByText() {
        let program = """
        define apples 5
        text { apples "foo" }
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        XCTAssertEqual(context.children.count, 4)
        #endif
    }

    func testUnbracedTextCoalesced() {
        let program = """
        define apples 1
        text apples "111"
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 4)
        XCTAssertEqual(chars.first?.bounds.min.y, chars.last?.bounds.min.y)
        #endif
    }

    func testFontOutsideText() {
        let program = """
        text "a"
        font "Courier"
        text "a"
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 2)
        XCTAssertNotEqual(chars.first?.bounds.size, chars.last?.bounds.size)
        #endif
    }

    func testFontOutsideTextFunction() {
        let program = """
        define aText {
            text "a"
        }
        aText
        font "Courier"
        aText
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 2)
        XCTAssertNotEqual(chars.first?.bounds.size, chars.last?.bounds.size)
        #endif
    }

    func testFontOutsideTextBlock() {
        let program = """
        text { "a" }
        font "Courier"
        text { "a" }
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 2)
        XCTAssertNotEqual(chars.first?.bounds.size, chars.last?.bounds.size)
        #endif
    }

    func testFontOutsideTextBlockFunction() {
        let program = """
        define aText {
            text { "a" }
        }
        aText
        font "Courier"
        aText
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 2)
        XCTAssertNotEqual(chars.first?.bounds.size, chars.last?.bounds.size)
        #endif
    }

    func testFontInsideTextBlock() {
        let program = """
        text {
            "a"
            font "Courier"
            "a"
        }
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        #if canImport(CoreText)
        let chars = context.children.compactMap { $0.value as? Geometry }
        XCTAssertEqual(chars.count, 2)
        XCTAssertNotEqual(chars.first?.bounds.size, chars.last?.bounds.size)
        #endif
    }

    // MARK: SVGPath command

    func testSVGPath() throws {
        let program = try parse("fill svgpath \"M150 0 L75 200 225 200 Z\"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        guard case let .fill(paths) = geometry.type else {
            XCTFail()
            return
        }
        XCTAssertEqual(paths.first?.points.count, 4)
    }

    // MARK: Lights

    func testDefaultLight() throws {
        let program = try parse("light")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        let light = try XCTUnwrap(geometry.light)
        XCTAssertEqual(light.color, .white)
        XCTAssertFalse(light.hasPosition)
        XCTAssertFalse(light.hasOrientation)
    }

    func testAmbientLight() throws {
        let program = try parse("light { color yellow }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        let light = try XCTUnwrap(geometry.light)
        XCTAssertEqual(light.color, .yellow)
        XCTAssertFalse(light.hasPosition)
        XCTAssertFalse(light.hasOrientation)
    }

    func testDirectionalLight() throws {
        let program = try parse("""
        light {
            color yellow
            orientation 0.5
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        guard case let .light(light) = geometry.type else {
            XCTFail()
            return
        }
        XCTAssertEqual(light.color, .yellow)
        XCTAssertFalse(light.hasPosition)
        XCTAssert(light.hasOrientation)
        XCTAssertEqual(geometry.transform, .init(rotation: .roll(.halfPi)))
    }

    func testPointLight() throws {
        let program = try parse("""
        light {
            color yellow
            position 1
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        let light = try XCTUnwrap(geometry.light)
        XCTAssertEqual(light.color, .yellow)
        XCTAssert(light.hasPosition)
        XCTAssertFalse(light.hasOrientation)
        XCTAssertEqual(geometry.transform, .init(offset: .init(1, 0, 0)))
    }

    func testSpotlight() throws {
        let program = try parse("""
        light {
            color yellow
            position 1
            orientation 0.5
        }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        let light = try XCTUnwrap(geometry.light)
        XCTAssertEqual(light.color, .yellow)
        XCTAssert(light.hasPosition)
        XCTAssert(light.hasOrientation)
        XCTAssertEqual(geometry.transform, .init(
            offset: .init(1, 0, 0),
            rotation: .roll(.halfPi)
        ))
    }

    func testLightWithColour() throws {
        let program = try parse("light { colour yellow }")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        let light = try XCTUnwrap(geometry.light)
        XCTAssertEqual(light.color, .yellow)
    }

    // MARK: Debug command

    func testDebugCube() throws {
        let program = try parse("debug cube")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssert((context.children.first?.value as? Geometry)?.debug == true)
    }

    func testDebugText() throws {
        let program = try parse("debug extrude text \"M\"")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssert((context.children.first?.value as? Geometry)?.debug == true)
    }

    func testDebugColorCommand() throws {
        let program = "debug color #f00"
        let range = program.range(of: "color")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "debug",
                index: 0,
                expected: "mesh or block",
                got: "color"
            ), at: range))
        }
    }

    func testColorDebugColor() throws {
        let program = """
        define r #f00
        color debug r
        """
        let range = program.range(of: "r", range: program.range(of: "debug r"))!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "debug",
                index: 0,
                expected: "mesh or block",
                got: "color"
            ), at: range))
        }
    }

    // MARK: Empty arguments

    func testCallVoidCommandWithoutArgs() throws {
        let program = """
        define foo {
            rnd
        }
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallVoidCommandWithEmptyParens() throws {
        let program = """
        define foo {
            rnd()
        }
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallVoidCommandWithEmptyBlock() throws {
        let program = """
        define foo {
            rnd {}
        }
        print foo
        """
        let range = program.range(of: "{}")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "rnd",
                index: 0,
                expected: "void",
                got: "block"
            ), at: range))
        }
    }

    func testCallVoidFunctionWithoutArgs() throws {
        let program = """
        define foo rnd
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallVoidFunctionWithEmptyParens() throws {
        let program = """
        define foo rnd()
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallVoidFunctionWithEmptyBlock() throws {
        let program = """
        define foo rnd {}
        print foo
        """
        let range = program.range(of: "{}")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "rnd",
                index: 0,
                expected: "void",
                got: "block"
            ), at: range))
        }
    }

    func testCallCustomFunctionWithoutArguments() {
        let program = """
        define foo() { 2 + 3 }
        print foo
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testCallCustomFunctionWithEmptyArguments() {
        let program = """
        define foo() { 2 + 3 }
        print foo()
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testCallCustomFunctionWithEmptyBlock() {
        let program = """
        define foo() { 2 + 3 }
        print foo {}
        """
        let range = program.range(of: "{}")!
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "foo",
                index: 0,
                expected: "void",
                got: "block"
            ), at: range))
        }
    }

    func testCallBlockWithoutArgs() throws {
        let program = """
        define foo {
            sphere
        }
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallBlockWithEmptyParens() throws {
        let program = """
        define foo {
            sphere
        }
        print foo()
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCallBlockWithEmptyBlock() throws {
        let program = """
        define foo {
            sphere
        }
        print foo {}
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    // MARK: Static type

    func testNumericLiteralType() throws {
        XCTAssertEqual(try expressionType("5"), .number)
    }

    func testArithmeticExpressionType() {
        XCTAssertEqual(try expressionType("1 + 2"), .number)
    }

    func testArithmeticExpressionType2() {
        XCTAssertEqual(try expressionType("(1 + 2) * 3"), .number)
    }

    func testBooleanLiteral() {
        XCTAssertEqual(try expressionType("true"), .boolean)
    }

    func testBooleanExpression() {
        XCTAssertEqual(try expressionType("1 < 2"), .boolean)
    }

    func testStringLiteralType() {
        XCTAssertEqual(try expressionType("\"foo\""), .string)
    }

    func testTupleExpressionType() throws {
        XCTAssertEqual(try expressionType("1 5"), .tuple)
    }

    func testTupleExpressionType2() throws {
        XCTAssertEqual(try expressionType("(1 5)"), .tuple)
    }

    func testTupleExpressionType3() {
        XCTAssertEqual(try expressionType("(pi 5)"), .tuple)
    }

    func testFunctionExpressionType() {
        XCTAssertNil(try expressionType("(cos pi)")) // TODO: number
    }

    func testFunctionExpressionType2() {
        XCTAssertNil(try expressionType("cos(pi)")) // TODO: number
    }
}
