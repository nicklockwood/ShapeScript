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

final class InterpreterTests: XCTestCase {
    // MARK: Random numbers

    func testRandomSeedTruncation() {
        let random = RandomSequence(seed: Double(Int.max))
        XCTAssert(random.seed < Double(Int.max))
    }

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
        define wheel { circle }
        wheel { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(first.name, "Foo")
        guard case .path = first.type else {
            XCTFail()
            return
        }
    }

    func testExtrudeNamedPath() throws {
        let program = try parse("""
        define wheel { circle }
        extrude wheel { name "Foo" }
        """)
        let scene = try evaluate(program, delegate: nil)
        let first = try XCTUnwrap(scene.children.first)
        guard case .extrude = first.type else {
            XCTFail()
            return
        }
    }

    func testSetNumberBlockName() throws {
        let program = try parse("""
        define foo {
            42
        }
        print foo { name "Foo" }
        """)
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'name'")
            XCTAssertEqual(error?.hint, "The 'name' property is not available in this context.")
        }
    }

    func testSetTupleBlockName() throws {
        let program = try parse("""
        define foo {
            "bar"
            42
        }
        print foo { name "Foo" }
        """)
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'name'")
            XCTAssertEqual(error?.hint, "The 'name' property is not available in this context.")
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

    func testOverrideGlobalFunction() {
        let program = """
        define cos(foo) { print "hello" }
        cube { cos(5) }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["hello"])
    }

    func testNoOverridePathFunction() {
        let program = """
        define point(foo) { print "hello" }
        path { point 1 0 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
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

    func testOptionReferencedInDefine() {
        let program = """
        define foo {
            option bar 5
            define baz bar/2
        }
        foo { bar 6 }
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
            XCTAssertEqual(
                error?.hint,
                "The 'option' command is not available in this context. Did you mean 'define'?"
            )
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

    func testOptionDoesntShadowDefineInCallerScope() {
        let program = """
        define foo {
            option x 0
            print x
        }

        define bar {
            define x 5
            foo { x x }
        }

        bar
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testDefineInCallerScopeDoesntShadowOptionInBlock() {
        let program = """
        define foo {
            option bar 1
            print bar
        }

        foo

        define bar 2
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testOptionShadowsGlobalFunction() throws {
        let program = try parse("""
        define blob {
            option length 2
            cube { size length }
        }
        blob
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.transform.scale, .init(size: 2))
    }

    func testOptionShadowsGlobalFunction2() throws {
        let program = try parse("""
        define blob {
            option length 2
            cube { size length }
        }
        blob { length 3 }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.transform.scale, .init(size: 3))
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

    func testDefineNotPassedToCustomCommand() {
        let program = """
        define foo {
            option baz 2
            print baz
        }
        foo { define baz 5 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    func testDefineNotPassedToBuiltInCommand() {
        let program = """
        define foo polygon {
            define sides 7
        }
        // should match default of 5 sides
        print foo.points.count - 1
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

    func testConditionalOptionPassedToCommand() {
        let program = """
        define foo polygon {
            if true {
                sides 7
            }
        }
        print foo.points.count - 1
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [7])
    }

    func testConditionalOptionPassedToCustomCommand() {
        let program = """
        define foo {
            option baz 1
            print baz
        }
        foo {
            if true {
                baz 5
            }
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
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

    func testOptionDefaultValueIsIdempotent() {
        let program = """
        define bar() {
            print "bar"
            5
        }
        define foo {
            define baz bar()
            option quux baz
            print quux
        }
        foo { quux 6 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["bar", 6]) // bar only called once, not twice
    }

    func testOptionCanReferenceOtherOption() {
        let program = """
        define foo {
            option bar 5
            option baz bar
            print baz
        }
        foo { bar 6 }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [6])
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

    func testOptionNameSuggestedForTypoInBlock() {
        let program = """
        extrude { alon square }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("alon", _)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssertEqual(error?.suggestion, "along")
        }
    }

    func testOptionNameSuggestedForTypoInCustomBlock() {
        let program = """
        define foo {
            option bar 0
        }
        foo { baa 1 }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("baa", _)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssertEqual(error?.suggestion, "bar")
        }
    }

    func testAlternativeNotSuggestedWhenValidSymbolUsedInInvalidContext() {
        let program = """
        define foo sphere
        foo { detail 1 }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("detail", _)? = error?.type else {
                XCTFail()
                return
            }
            XCTAssertNil(error?.suggestion)
        }
    }

    func testShadowedColorInheritedByBlock() throws {
        let program = """
        define black 1 0 0
        union {
            color black
            cube
        }
        """
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.material.color, Color(1, 0, 0))
    }

    // MARK: Position

    func testCumulativePosition() throws {
        let program = """
        translate 1 0 0
        cube { position 1 0 0 }
        """
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.transform.translation.x, 2)
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
        let range = try XCTUnwrap(program.range(of: "foo", range: XCTUnwrap(program.range(of: "position foo"))))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "position",
                expected: "vector",
                got: "tuple"
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
        let range = try XCTUnwrap(program.range(of: "7"))
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
        let range = try XCTUnwrap(program.range(of: "0.9"))
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
        let range = try XCTUnwrap(program.range(of: "foo", range: XCTUnwrap(program.range(of: "color foo"))))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "color", expected: "color", got: "list of numbers"
            ), at: range))
        }
    }

    func testSetColorWithColorAlphaTuple() throws {
        let program = """
        color (1 0 0) 0.5
        print color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color(1, 0, 0, 0.5)])
    }

    func testSetColorWithColorAlphaTuple2() throws {
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

    func testSetColorWithTupleWithTooManyElements() throws {
        let program = """
        color (1 0 0) 0.5 0.2
        print color
        """
        let range = try XCTUnwrap(program.range(of: "0.2"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "color", max: 2), at: range
            ))
        }
    }

    func testSetColorWithTupleConstantWithTooManyElements() throws {
        let program = """
        define foo (1 0 0) 0.5 0.2
        color foo
        print color
        """
        let range = try XCTUnwrap(program.range(of: "foo", range: XCTUnwrap(program.range(of: "color foo"))))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .typeMismatch(for: "color", expected: "color", got: "tuple"), at: range
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

    func testSetColorOptionSpecifiedAsTupleWithConstant() throws {
        let program = try parse("""
        define foo {
            option c 0 1
            color c
            cube
        }
        foo { c red }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    func testSetColorOptionSpecifiedAsTupleWithTuple() throws {
        let program = try parse("""
        define foo {
            option c 0 1
            color c
            cube
        }
        foo { c 1 0 0 }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    func testSetColorOptionSpecifiedAsConstantWithTuple() throws {
        let program = try parse("""
        define foo {
            option c green
            color c
            cube
        }
        foo { c 1 0 0 }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, .red)
    }

    func testSetColorOptionSpecifiedAsTupleWithColorAlphaTuple() throws {
        let program = try parse("""
        define foo {
            option c 0 1
            color c
            cube
        }
        foo { c red 0.5 }
        """)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssertEqual(geometry.material.color, Color.red.withAlpha(0.5))
    }

    func testSetNonColorWithColorConstant() throws {
        let program = try parse("""
        define foo {
            option c "foo"
            color c
            cube
        }
        foo { c red }
        """)
        let range = try XCTUnwrap(program.source.range(of: "red"))
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "c", expected: "string", got: "color"
            ), at: range))
        }
    }

    func testSetNonColorWithColorAlphaTuple() throws {
        let program = try parse("""
        define foo {
            option c "foo"
            color c
            cube
        }
        foo { c red 0.5 }
        """)
        let range = try XCTUnwrap(program.source.range(of: "red 0.5"))
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "c", expected: "string", got: "color"
            ), at: range))
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
        XCTAssertEqual(geometry.path?.points.first?.color, .red)
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
        let path = try XCTUnwrap(geometry.path)
        XCTAssertEqual(path.points.first?.color, .red)
        XCTAssertEqual(path.points.last?.color, .blue)
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
        let path = try XCTUnwrap(geometry.path)
        XCTAssertEqual(path.subpaths.first?.points.first?.color, .red)
        XCTAssertEqual(path.subpaths.last?.points.first?.color, .green)
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
        XCTAssertEqual(line1.path?.points.first?.color, .red)
        let line2 = try XCTUnwrap(context.children.last?.value as? Geometry)
        XCTAssertEqual(line2.path?.points.first?.color, .blue)
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
        )])
    }

    func testSetTextureWithNonExistentImage() throws {
        let program = """
        texture "Nope.jpg"
        print texture
        """
        let range = try XCTUnwrap(program.range(of: "\"Nope.jpg\""))
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            #if targetEnvironment(simulator) || !os(iOS)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope.jpg", at: testsDirectory.appendingPathComponent("Nope.jpg")
            ), at: range))
            #else
            XCTAssertEqual(error, RuntimeError(.fileAccessRestricted(
                for: "Nope.jpg", at: testsDirectory
            ), at: range))
            #endif
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

    // MARK: Material

    func testDefaultMaterial() {
        let program = """
        print color
        print material.color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.white, .white])
    }

    func testColorMaterial() {
        let program = """
        material {
            color (1 0 0)
        }
        print color
        print material.color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red, .red])
    }

    func testStoredMaterial() {
        let program = """
        define foo material {
            color (1 0 0)
        }
        print color
        print foo.color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.white, .red])
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
        let range = try XCTUnwrap(program.range(of: "0.9"))
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
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
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 1
        )])
    }

    func testSetBackgroundTextureWithNonExistentImage() throws {
        let program = """
        background "Nope.jpg"
        print background
        """
        let range = try XCTUnwrap(program.range(of: "\"Nope.jpg\""))
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            #if targetEnvironment(simulator) || !os(iOS)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope.jpg", at: testsDirectory.appendingPathComponent("Nope.jpg")
            ), at: range))
            #else
            XCTAssertEqual(error, RuntimeError(.fileAccessRestricted(
                for: "Nope.jpg", at: testsDirectory
            ), at: range))
            #endif
        }
    }

    func testSetBackgroundTextureWithNonExistentInterpolatedPath() throws {
        let program = """
        background "Nope" 1 ".jpg"
        print background
        """
        let range = try XCTUnwrap(program.range(of: "\"Nope\" 1 \".jpg\""))
        let delegate = TestDelegate()
        XCTAssertThrowsError(try evaluate(parse(program), delegate: delegate)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            #if targetEnvironment(simulator) || !os(iOS)
            XCTAssertEqual(error, RuntimeError(.fileNotFound(
                for: "Nope1.jpg", at: testsDirectory.appendingPathComponent("Nope1.jpg")
            ), at: range))
            #else
            XCTAssertEqual(error, RuntimeError(.fileAccessRestricted(
                for: "Nope1.jpg", at: testsDirectory
            ), at: range))
            #endif
            XCTAssertEqual(error?.range, range)
        }
    }

    func testSetBackgroundTextureToEmptyString() throws {
        let program = """
        background ""
        print background
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.clear])
    }

    func testBackgroundSetter() throws {
        let program = try parse("background red")
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.background, .color(.red))
    }

    func testBackgroundGetter() throws {
        let program = try parse("background")
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .missingArgument(
                for: "background",
                type: .colorOrTexture
            ))
        }
    }

    func testBackgroundInDefine() throws {
        let program = try parse("""
        background red
        define bg background
        print bg
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.background, .color(.red))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testReturnBackgroundFromBlock() throws {
        let program = try parse("""
        define bg { background }
        background red
        print bg
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.background, .color(.red))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testSetBackgroundInFunction() throws {
        let program = try parse("""
        define bg(color) {
            background color
            background
        }
        print bg(red)
        """)
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        XCTAssertNoThrow(try program.evaluate(in: context))
        XCTAssertEqual(context.background, .color(.red))
        XCTAssertEqual(delegate.log, [Color.red])
    }

    func testCameraBackground() throws {
        let program = """
        background red
        camera { background blue }
        background green
        """
        let scene = try evaluate(parse(program), delegate: nil)
        let camera = try XCTUnwrap(scene.cameras.first)
        XCTAssertEqual(camera.camera?.background, .color(.blue))
    }

    func testCameraBackgroundShadowing() throws {
        let program = """
        background red
        camera {
            background background 0.5
        }
        """
        let scene = try evaluate(parse(program), delegate: nil)
        let camera = try XCTUnwrap(scene.cameras.first)
        XCTAssertEqual(camera.camera?.background, .color(Color.red.withAlpha(0.5)))
    }

    func testCameraBackgroundNotInherited() throws {
        let program = """
        background red
        camera {}
        """
        let scene = try evaluate(parse(program), delegate: nil)
        let camera = try XCTUnwrap(scene.cameras.first)
        XCTAssertNil(camera.camera?.background)
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
        let range = try XCTUnwrap(program.source.range(of: "\"foo\""))
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
        let range = try XCTUnwrap(program.source.range(of: "\"\""))
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
        let range = try XCTUnwrap(program.source.range(of: "\" \""))
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

    func testImportExpression() throws {
        let program = try parse("define foo import \"File1.shape\"")
        let delegate = TestDelegate()
        let context = EvaluationContext(source: program.source, delegate: delegate)
        try? program.evaluate(in: context) // Throws file not found, but we can ignore
        XCTAssertEqual(delegate.imports, ["File1.shape"])
    }

    // MARK: Command invocation

    func testInvokeCustomVoidFunctionInsideExpression() {
        let program = """
        define foo() {}
        print foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokeCustomVoidFunctionWithParamInsideExpression() {
        let program = """
        define foo(bar) {}
        print foo(3)
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCommandParameterPrecedence() throws {
        let program = """
        define foo(bar) {}
        print (4 + 5) / 3
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3])
    }

    func testFunctionWithDuplicateArgumentName() throws {
        let program = """
        define foo(a a) { a + a }
        print foo(1 2)
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Duplicate function parameter 'a'")
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
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "lathe", type: "path or block"), at: range
            ))
        }
    }

    func testInvokeGroupWithoutBlock() {
        let program = "group"
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "group", type: "mesh or block"), at: range
            ))
        }
    }

    func testInvokeExtrudeWithSingleArgument() throws {
        let program = "extrude square"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .extrude([.square()], .default))
    }

    func testInvokeExtrudeWithSingleArgumentInParens() throws {
        let program = "extrude(square)"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .extrude([.square()], .default))
    }

    func testInvokeExtrudeWithMultipleArguments() throws {
        let program = "extrude square circle"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(
            scene.children.first?.type,
            .extrude([.square(), .circle()], .default)
        )
    }

    func testInvokeExtrudeWithSingleArgumentInsideExpression() throws {
        let program = "extrude text \"foo\""
        let scene = try evaluate(parse(program), delegate: nil)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.first?.type, .extrude(Path.text("foo"), .default))
        #endif
    }

    func testInvokeExtrudeWithSingleArgumentOfWrongType() throws {
        let program = "extrude sphere"
        let range = try XCTUnwrap(program.range(of: "sphere"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for 'extrude' should be a path or block, not a mesh.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "extrude",
                expected: "path or block",
                got: "mesh"
            ), at: range))
        }
    }

    func testInvokeXorWithMultipleArguments() throws {
        let program = "xor cube sphere"
        let scene = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(scene.children.first?.type, .xor)
        XCTAssertEqual(scene.children.first?.children.map(\.type), [
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

    func testInvokeTextInExpressionWithoutParens() throws {
        let program = "print 1 + text \"foo\""
        let range = try XCTUnwrap(program.range(of: "text"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "text", type: "text or block"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testInvokeTextInExpressionWithParensButWrongArgumentType() throws {
        let program = "print 1 + (text cube)"
        let range = try XCTUnwrap(program.range(of: "cube"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "text",
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
        let range = try XCTUnwrap(program.range(of: "cube"))
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

    func testExtrudeAlongNumber() throws {
        let program = """
        extrude {
            square { size 0.01 }
            along 2
        }
        """
        let range = try XCTUnwrap(program.range(of: "2"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for 'along' should be a path, not a number.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "along",
                expected: "path",
                got: "number"
            ), at: range))
        }
    }

    func testExtrudeAlongPathAndNumber() throws {
        let program = """
        extrude {
            square { size 0.01 }
            along square 2
        }
        """
        let range = try XCTUnwrap(program.range(of: "2"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            // TODO: this message isn't really ideal - need different handling for paths arguments
            XCTAssertEqual(error?.hint, "The second argument for 'along' should be a path, not a number.")
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
        define foo {
            path {
                point 0 0
                point 1 0
                point 1 1
            }
        }
        path { foo }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testBlockThatReturnsMeshIsTransformable() throws {
        let program = try parse("""
        define foo {
            cube
        }
        foo {
            orientation 0.5
            position 1
        }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testBlockThatReturnsPathIsTransformable() throws {
        let program = try parse("""
        define foo {
            text "hello"
        }
        foo {
            orientation 0.5
            position 1
        }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testBlockThatReturnsStringIsNotTransformable() throws {
        let program = try parse("""
        define foo {
            "hello"
        }
        print foo {
            orientation 0.5
            position 1
        }
        """)
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'orientation'")
            XCTAssertEqual(error?.hint, "The 'orientation' property is not available in this context.")
        }
    }

    func testBlockWithoutChildrenDoesNotSupportChildTransforms() throws {
        let program = try parse("""
        define foo {
            cube
        }
        foo {
            rotate 0.5
            translate 1
        }
        """)
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'rotate'")
            XCTAssertEqual(error?.hint, """
            The 'rotate' command is not available in this context. Did you mean 'orientation'?
            """)
        }
    }

    func testBlockWithNumericChildrenDoesNotSupportChildTransforms() throws {
        let program = try parse("""
        define foo {
            children + 3
        }
        foo {
            rotate 0.5
            translate 1
        }
        """)
        XCTAssertThrowsError(try evaluate(program, delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'rotate'")
            XCTAssertEqual(error?.hint, "The 'rotate' command is not available in this context.")
        }
    }

    func testBlockWithChildShapesSupportsChildTransforms() throws {
        let program = try parse("""
        define foo {
            union children
        }
        foo {
            rotate 0.5
            translate 1
            cube
        }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testBlockWithChildPointsSupportsChildTransforms() throws {
        let program = try parse("""
        define foo {
            path {
                children
            }
        }
        foo {
            color red
            point 0 0
            translate 1
            curve 0 0
            translate 0 1
            point 0 0
        }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testBlockWithUnknownChildTypesSupportsChildTransforms() throws {
        let program = try parse("""
        define foo {
            children
        }
        foo {
            rotate 0.5
            translate 1
        }
        """)
        XCTAssertNoThrow(try evaluate(program, delegate: nil))
    }

    func testNestedBlockPosition() throws {
        let program = try parse("""
        define foo {
            cylinder {
                size (10 + 0.1 * 2)  20
                position 0  (20 / 2)
            }
            cylinder {
                size (10 * 1.5 + 0.1 * 2)  (20 / 2)
                position 0  (20 - 20 / 4)
            }
        }

        define bar {
            foo {
                position 17
            }
            foo {
                position 0
            }
        }

        bar {
            position 0  0  (108 / 2)
        }
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

    func testRangeWithNonNumericStartValue() throws {
        let program = "define range \"foo\" to 10"
        let range = try XCTUnwrap(program.range(of: "\"foo\""))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "to",
                index: 0,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithNonNumericEndValue() throws {
        let program = "define range 1 to \"bar\""
        let range = try XCTUnwrap(program.range(of: "\"bar\""))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "to",
                index: 1,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithNonNumericStepValue() throws {
        let program = "define range 1 to 5 step \"foo\""
        let range = try XCTUnwrap(program.range(of: "\"foo\""))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The right operand for 'step' should be a number, not a string.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "step",
                index: 1,
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testRangeWithZeroStepValue() throws {
        let program = "define range 1 to 5 step 0"
        let range = try XCTUnwrap(program.range(of: "0"))
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

    // MARK: Partial ranges

    func testPartialRange() {
        let program = """
        define range from 5
        print range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 5, to: nil)])
    }

    func testPartialRangeWithStep() {
        let program = """
        define range from 5 step 2
        print range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [RangeValue(from: 5, to: nil, step: 2)])
    }

    func testPartialRangeWithNegativeStep() {
        let program = """
        define range from 2 step -1
        define values 1 2 3 4
        print values[range]
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3, 2, 1])
    }

    func testValuesInNegativePartialRange() {
        let program = """
        define range from 5 step -1
        print 5 in range
        print 0 in range
        print 6 in range
        print -5000 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, false, true])
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

    func testForLoopWithNonRangeExpression() throws {
        let program = "for 1 { print i }"
        let range = try XCTUnwrap(program.range(of: "1"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "loop bounds",
                expected: "range or list",
                got: "number"
            ), at: range))
        }
    }

    func testForLoopWithNonRangeExpression2() throws {
        let program = "for i in \"foo\" { print i }"
        let range = try XCTUnwrap(program.range(of: "\"foo\""))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "loop bounds",
                expected: "range or list",
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

    func testForLoopWithColorProperty() throws {
        let program = "for i in color { print i }"
        let range = try XCTUnwrap(program.range(of: "color"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The loop bounds should be a range or list, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "loop bounds",
                expected: "range or list",
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

    func testForLoopRangePrecision() {
        for i in 1 ... 100 {
            let program = """
            define a \(i)
            define b 8
            define c (b/a)
            for i in 1 to b + (1 - c) step c {
                print(i)
            }
            """
            let delegate = TestDelegate()
            XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
            XCTAssertEqual(delegate.log.count, i)
        }
    }

    func testValueInRange() {
        let program = """
        define range -1 to 4
        print 1.5 in range
        print -1 in range
        print 4.0001 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, false])
    }

    func testValueInReverseRange() {
        let program = """
        define range 4 to 0
        print 1 in range
        print -1 in range
        print -4.0001 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false, false, false])
    }

    func testValueInNegativeRange() {
        let program = """
        define range 0 to -4
        print 1 in range
        print -1 in range
        print -4.0001 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false, false, false])
    }

    func testValueInRangeWithStep() {
        let program = """
        define range 0 to 4 step 1
        print 1.5 in range
        print 1 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [false, true])
    }

    func testValueInFloatRangeWithStep() {
        let program = """
        define range 0.5 to 4 step 1
        print 1.5 in range
        print 1 in range
        print 3.5 in range
        print 4 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, false, true, false])
    }

    func testValueInNegativeRangeWithStep() {
        let program = """
        define range 0 to -4 step -1
        print 0 in range
        print 1 in range
        print -1 in range
        print -4 in range
        print -4.0001 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, false, true, true, false])
    }

    func testValueInRangeWithFractionalStep() {
        let program = """
        define range 0 to 4 step 0.5
        print 1.5 in range
        print 1 in range
        print 0.49 in range
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true, true, false])
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

    func testIfColor() throws {
        let program = "if red { print i }"
        let range = try XCTUnwrap(program.range(of: "red"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The if condition should be a boolean, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "if condition",
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

    func testIfInRange() {
        let program = "if 1 in 0 to 4 { print true }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testIfInTuple() {
        let program = "if 3 in (1 2 3) { print true }"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testIfKeyInObject() {
        let program = """
        define foo object {
            a 1
            b 2
        }
        if "a" in foo { print true }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    func testIfKeyInVector() {
        let program = """
        define vector 1 2 3
        if "x" in vector { print true }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    // MARK: Switch/case

    func testSwitchCase() {
        let program = """
        switch 3 {
        case 1
            print("a")
        case 3
            print("b")
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["b"])
    }

    func testSwitchCaseNoElse() {
        let program = """
        switch 5 {
        case 1
            print("a")
        case 3
            print("b")
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
    }

    func testSwitchCaseElse() {
        let program = """
        switch 1 {
        case 1
            print("a")
        case 3
            print("b")
        else
            print("c")
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["a"])
    }

    func testSwitchCaseElse2() {
        let program = """
        switch 5 {
        case 1
            print("a")
        case 3
            print("b")
        else
            print("c")
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["c"])
    }

    func testSwitchCaseGrouping() {
        let program = """
        switch 4 {
        case 1 2
            print("a")
        case 3 4 5
            print("b")
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["b"])
    }

    func testSwitchTruthTable() {
        let program = """
        define values (
            (false false)
            (true false)
            (false true)
            (true true)
        )
        for value in values {
            switch value {
            case (false false)
                print 1
            case (true false)
                print 2
            case (false true)
                print 3
            case (true true)
                print 4
            }
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1, 2, 3, 4])
    }

    func testEmptySwitch() {
        let program = """
        switch 1 {
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [])
    }

    func testSwitchDefaultSyntaxError() {
        let program = """
        switch 1 {
        case 1
            print "1"
        case 2
            print "2"
        default
            print "?"
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("default", _) = error?.type else {
                XCTFail()
                return
            }
            XCTAssertEqual(error?.hint, "Did you mean 'else'?")
        }
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
                .missingArgument(for: "cos", type: "angle in radians"), at: range
            ))
        }
    }

    func testInvokeMonadicFunctionWithTwoArgs() throws {
        let program = "print cos 1 2"
        let range = try XCTUnwrap(program.range(of: "2"))
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
                .missingArgument(for: "pow", type: "number"), at: range
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

    func testInvokeDyadicFunctionWithThreeArgs() throws {
        let program = "print pow 1 2 3"
        let range = try XCTUnwrap(program.range(of: "3"))
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

    func testInvokeFunctionInExpressionWithoutParens() throws {
        let program = "print 1 + sqrt 9"
        let range = try XCTUnwrap(program.range(of: "sqrt"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "sqrt", type: "number"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButWrongArgumentType() throws {
        let program = "print 1 + (sqrt \"a\")"
        let range = try XCTUnwrap(program.range(of: "\"a\""))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "sqrt",
                expected: "number",
                got: "string"
            ), at: range))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument() throws {
        let program = "print 1 + (pow 1)"
        let range = try XCTUnwrap(program.range(of: ")"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 1, type: "number"),
                at: range.lowerBound ..< range.lowerBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButMissingArgument2() throws {
        let program = "print 1 + pow(1)"
        let range = try XCTUnwrap(program.range(of: ")"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "pow", index: 1, type: "number"),
                at: range.lowerBound ..< range.lowerBound
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument() throws {
        let program = "print 1 + (pow 1 2 3)"
        let range = try XCTUnwrap(program.range(of: "3"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "pow", max: 2), at: range
            ))
        }
    }

    func testInvokeFunctionInExpressionWithParensButExtraArgument2() throws {
        let program = "print 1 + pow(1 2 3)"
        let range = try XCTUnwrap(program.range(of: "3"))
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

    func testMinWithThreeArgs() {
        let program = "print min 1 2 -1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1])
    }

    func testMinWithOneArg() {
        let program = "print min 1"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testMinWithNoArgs() throws {
        let program = "print min"
        let range = try XCTUnwrap(program.range(of: "min"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "min", type: "number"),
                at: range.upperBound ..< range.upperBound
            ))
        }
    }

    func testMinWithEmptyTuple() {
        let program = """
        define foo ()
        print min foo
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0])
    }

    func testMaxFunction() {
        let program = "print max 1 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    func testSignFunction() {
        let program = """
        print sign -10
        print sign 7.5
        print sign 0
        print sign -0
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1, 1, 0, 0])
    }

    func testFunctionAmbiguity() {
        let program = "print -cos(pi) + sin(pi)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-cos(Double.pi) + sin(.pi)])
    }

    func testFunctionAmbiguity2() {
        let program = """
        define a 1
        define b 2
        print -a (pi) + b (pi)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1, Double.pi + 2, Double.pi])
    }

    func testFunctionAmbiguity3() {
        let program = """
        define a 1
        print -a (pi)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1, Double.pi])
    }

    func testFunctionAmbiguity4() {
        let program = """
        define a 0.999999
        define b 1000
        define trunc() {
            floor(a * b) / b
        }
        print floor(a * b) / b
        print (floor a * b) / b
        print trunc()
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.999, 0.999, 0.999])
    }

    func testFunctionAmbiguity5() {
        let program = """
        define foo {
            option length 120
            print length
        }
        foo {
            length 40
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [40])
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

    func testGeometriesEqual() {
        let program = """
        define a cube
        define b cube
        print a = b
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [true])
    }

    // MARK: Math operators

    func testNegateNumericExpression() {
        let program = """
        print -(1 + 2)
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-3.0])
    }

    func testNegateNumericStringExpression() {
        let program = """
        print -(\"1\" + \"2\")
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-3.0])
    }

    func testNegateNumericString() {
        let program = """
        print -\"42\"
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-42.0])
    }

    func testCoerceNumericString() {
        let program = """
        print +\"42\"
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [42.0])
    }

    func testCoerceNumericStringExpression() {
        let program = """
        print +(\"1\" + \"2\")
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3.0])
    }

    func testModuloOperator() {
        let program = """
        print 3 % 3
        print 5 % 2
        print 5 % 3
        print 7 % 2
        print -7 % 2
        print -5 % 3
        print -5 % -3
        print 3 % 1.5
        print -4.5 % 1.25
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0, 1, 2, 1, -1, -2, -2, 0, -0.75])
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

    // MARK: Vector algebra

    func testNumericTupleNegation() {
        let program = "print -(1 0 -2)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1.0, 0, 2.0])
    }

    func testNumericStringTupleNegation() {
        let program = "print -(\"1\" \"0\" \"-2\")"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-1.0, 0, 2.0])
    }

    func testNumericStringTupleCoercion() {
        let program = "print +(\"1\" \"0\" \"-2\")"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0, 0, -2.0])
    }

    func testNumericTupleScalarMultiply() {
        let program = "print (1 0 -2) * 3"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3.0, 0, -6.0])
    }

    func testNumericTupleMultiply() {
        let program = "print (1 0 -2) * (2 3 4)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2.0, 0, -8.0])
    }

    func testNumericTupleMultiplyShorten() {
        let program = "print (1 0 -2) * (2 3)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2.0, 0])
    }

    func testNumericTupleMultiplyNoWiden() {
        let program = "print (1 0) * (2 3 4)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2.0, 0])
    }

    func testNumericTupleScalarDivide() {
        let program = "print (-1 3) / 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-0.5, 1.5])
    }

    func testNumericStringTupleScalarMultiply() {
        let program = "print (\"1\" \"-2\") * \"3\""
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3.0, -6.0])
    }

    func testNonNumericStringTupleScalarMultiply() throws {
        let program = "print (\"foo\" \"bar\") * 3"
        let range = try XCTUnwrap(program.range(of: "(\"foo\" \"bar\")"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "*",
                index: 0,
                expected: "number, texture, or vector",
                got: "list of strings"
            ), at: range))
        }
    }

    func testTextureIntensityMultiply() throws {
        let program = """
        texture "Stars1.jpg" * 0.5
        print texture
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Texture.file(
            name: "Stars1.jpg", url: testsDirectory.appendingPathComponent("Stars1.jpg"), intensity: 0.5
        )])
    }

    func testNumericTupleScalarAdd() {
        let program = "print (-1 3) + 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0, 5.0])
    }

    func testNumericTupleAdd() {
        let program = "print (-1 3) + (2 1)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0, 4.0])
    }

    func testNumericTupleSubtract() {
        let program = "print (-1 3) - (2 1)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [-3.0, 2.0])
    }

    func testNumericTupleAddNoShorten() {
        let program = "print (-1 3 2) + (2 1)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0, 4.0, 2.0])
    }

    func testNumericTupleAddNoWiden() {
        let program = "print (-1 3) + (2 1 2)"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0, 4.0])
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

    func testCustomFunctionDoesntInheritSymbolsFromCallerScope() {
        let program = """
        define foo(a b) { a + b + c }
        define bar {
            define c 3
            print foo(1 2)
        }
        bar
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownSymbol("c", options: _) = error?.type else {
                XCTFail()
                return
            }
        }
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
        XCTAssertEqual(context.childTransform.translation, .init(1, 0, 0))
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
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected symbol 'point'")
            XCTAssertEqual(error?.hint, "The 'point' command is not available in this context.")
            guard case .unknownSymbol("point", options: _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testCallFunctionBeforeDeclaration() {
        let program = """
        foo 5
        define foo(x) { x }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Forward reference")
            XCTAssertEqual(error?.hint, "The symbol 'foo' was used before it was defined.")
            guard case .forwardReference("foo")? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testReferenceFunctionBeforeDeclaration() {
        let program = """
        define bar(x) { foo(x) }
        define foo(x) { x }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testNestedFunctionReferenceBeforeDeclaration() {
        let program = """
        define foo() {
            define bar { baz }
            define baz { 5 }
            bar
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testCustomFunctionDoesntDoubleApplyTransform() {
        let program = """
        define foo() {
            mesh {
                polygon{
                    point 1 0
                    point 0.5 1
                    point 0 0
                }
            }
        }
        translate 1
        foo
        """
        let context = EvaluationContext(source: program, delegate: nil)
        XCTAssertNoThrow(try parse(program).evaluate(in: context))
        let mesh = context.children.first?.value as? Geometry
        XCTAssertEqual(mesh?.transform.translation, .init(1, 0, 0))
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
        XCTAssertEqual(geometry.transform, .init(translation: .init(1, 0, 0)))
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
            rotation: .roll(.halfPi),
            translation: .init(1, 0, 0)
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
        let range = try XCTUnwrap(program.range(of: "color"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for 'debug' should be a mesh or block, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "debug",
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
        let range = try XCTUnwrap(program.range(of: "r", range: program.range(of: "debug r")))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for 'debug' should be a mesh or block, not a color.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "debug",
                expected: "mesh or block",
                got: "color"
            ), at: range))
        }
    }

    func testDebugMixedTuple() throws {
        let program = """
        debug fill square 1
        """
        let range = try XCTUnwrap(program.range(of: "1"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The second argument for 'fill' should be a path, not a number.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "fill",
                index: 1,
                expected: "path",
                got: "number"
            ), at: range))
        }
    }

    // MARK: Empty arguments

    func testPrintNothing() {
        let program = "print"
        let range = program.endIndex ..< program.endIndex
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error?.hint, "The 'print' command expects an argument.")
            XCTAssertEqual(error, RuntimeError(
                .missingArgument(for: "print", type: "any"),
                at: range
            ))
        }
    }

    func testPrintEmptyTuple() {
        let program = "print ()"
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

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
        let range = try XCTUnwrap(program.range(of: "{}"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected argument")
            XCTAssertEqual(error?.hint, "The 'rnd' function does not expect any arguments.")
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "rnd", max: 0),
                at: range
            ))
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

    func testCallVoidFunctionWithEmptyParensInTuple() throws {
        let program = """
        seed 1
        print rnd() rnd()
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.23645552527159452, 0.3692706737201661])
    }

    func testCallVoidFunctionWithEmptyBlock() throws {
        let program = """
        define foo rnd {}
        print foo
        """
        let range = try XCTUnwrap(program.range(of: "{}"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected argument")
            XCTAssertEqual(error?.hint, "The 'rnd' function does not expect any arguments.")
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "rnd", max: 0),
                at: range
            ))
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

    func testCallCustomFunctionWithEmptyBlock() throws {
        let program = """
        define foo() { 2 + 3 }
        print foo {}
        """
        let range = try XCTUnwrap(program.range(of: "{}"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unexpected argument")
            XCTAssertEqual(error?.hint, "The 'foo' symbol does not expect any arguments.")
            XCTAssertEqual(error, RuntimeError(
                .unexpectedArgument(for: "foo", max: 0),
                at: range
            ))
        }
    }

    func testCallNonVoidCustomFunctionWithEmptyBlock() throws {
        let program = """
        define foo(bar) { bar + 3 }
        print foo {}
        """
        let range = try XCTUnwrap(program.range(of: "{}"))
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, "The argument for 'foo' should be a number or vector, not a block.")
            XCTAssertEqual(error, RuntimeError(.typeMismatch(
                for: "foo",
                expected: "number or vector",
                got: "block"
            ), at: range))
        }
    }

    func testCallPropertyWithEmptyBlock() {
        let program = """
        define foo cube
        print foo {}
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
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

    func testCallStdlibBlockWithEmptyParens() throws {
        let program = "cube()"
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
}
