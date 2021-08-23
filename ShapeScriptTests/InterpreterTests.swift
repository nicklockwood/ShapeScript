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

private class TestDelegate: EvaluationDelegate {
    func importGeometry(for _: URL) throws -> Geometry? {
        preconditionFailure()
    }

    func resolveURL(for _: String) -> URL {
        preconditionFailure()
    }

    var log = [AnyHashable?]()
    func debugLog(_ values: [Any?]) {
        log += values as! [AnyHashable?]
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
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
        guard let first = scene.children.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
        XCTAssert(first.children.isEmpty)
    }

    func testNameInvalidAtRoot() {
        let program = """
        name "Foo"
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("name", _)? = (error as? RuntimeError)?.type else {
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
            guard case .unknownSymbol("name", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
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
            guard case .unknownSymbol("option", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOptionInvalidAtRoot() {
        let program = "option foo 5"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("option", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
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
            guard case .unknownSymbol("position", _)? = (error as? RuntimeError)?.type else {
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
            guard case .unknownSymbol("position", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPositionError() throws {
        let program = """
        define pos 1 0 0
        cube {
            position pos 0
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            XCTAssertEqual((error as? RuntimeError)?.type, .typeMismatch(
                for: "position",
                index: 0,
                expected: "vector",
                got: "vector, number"
            ))
        }
    }

    // MARK: Colors

    func testColorTupleError() throws {
        let program = """
        define foo 1 0 0
        color foo 0.5
        print color
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            XCTAssertEqual((error as? RuntimeError)?.type, .typeMismatch(
                for: "color",
                index: 0,
                expected: "color",
                got: "color, number"
            ))
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("lathe", index: 0, type: "block")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeGroupWithoutBlock() {
        let program = "group"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("group", index: 0, type: "block")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "extrude",
                index: 0,
                expected: "block",
                got: "mesh"
            ))
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .missingArgument(for: "text", index: 0, type: "block"))
        }
    }

    func testInvokeTextInExpressionWithParensButWrongArgumentType() {
        let program = "print 1 + (text 2)"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "text",
                index: 0,
                expected: "block",
                got: "number"
            ))
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
            along 1
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "along",
                index: 0,
                expected: "path",
                got: "number"
            ))
        }
    }

    func testExtrudeAlongPathAndNumber() {
        let program = """
        extrude {
            square { size 0.01 }
            along square 1
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "along",
                index: 1,
                expected: "path",
                got: "number"
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

    func testForLoopWithNonNumericStartIndex() {
        let program = "for i in \"foo\" to 10 { print i }"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "start value",
                index: 0,
                expected: "number",
                got: "string"
            ))
        }
    }

    func testForLoopWithNonNumericEndIndex() {
        let program = "for i in 1 to \"bar\" { print i }"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "end value",
                index: 0,
                expected: "number",
                got: "string"
            ))
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("cos", index: 0, type: "number")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeMonadicFunctionWithTwoArgs() {
        let program = "print cos 1 2"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unexpectedArgument("cos", max: 1)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("pow", index: 0, type: "pair")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeDyadicFunctionWithOneArg() {
        let program = "print pow 1"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("pow", index: 1, type: "number")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeDyadicFunctionWithThreeArgs() {
        let program = "print pow 1 2 3"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unexpectedArgument("pow", max: 2)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "sqrt",
                index: 0,
                expected: "number",
                got: "string"
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument() {
        let program = "print 1 + (pow 1)"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .missingArgument(for: "pow", index: 1, type: "number"))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument2() {
        let program = "print 1 + pow(1)"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .missingArgument(for: "pow", index: 1, type: "number"))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument() {
        let program = "print 1 + (pow 1 2 3)"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .unexpectedArgument(for: "pow", max: 2))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument2() {
        let program = "print 1 + pow(1 2 3)"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .unexpectedArgument(for: "pow", max: 2))
        }
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

    func testTupleNonexistentLookup() {
        let program = "print (1 2).foo"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("foo", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testColorWidthLookup() {
        let program = "color 1 0.5\nprint color.width"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("width", _)? = (error as? RuntimeError)?.type else {
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
}
