//
//  TypesystemTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 19/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private func expressionType(_ expression: String) throws -> ValueType {
    let lines = expression.split(separator: "\n")
    let source = "\(lines.dropLast().joined(separator: "\n"))\ndefine foo_ \(lines.last!)"
    let program = try parse(source)
    guard case let .define(_, definition) = program.statements.last?.type,
          case let .expression(expression) = definition.type
    else {
        XCTFail()
        return .any
    }
    let context = EvaluationContext(source: "", delegate: nil)
    try program.evaluate(in: context)
    return try expression.staticType(in: context)
}

private func evaluate(_ expression: String, as type: ValueType) throws -> Value {
    let program = try parse("define foo \(expression)")
    guard case let .define(_, definition) = program.statements.last?.type,
          case let .expression(expression) = definition.type
    else {
        XCTFail()
        return .void
    }
    let context = EvaluationContext(source: "", delegate: nil)
    return try expression.evaluate(as: type, for: "", in: context)
}

class TypesystemTests: XCTestCase {
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

    func testNumericTupleExpressionType() throws {
        XCTAssertEqual(try expressionType("1 5"), .list(.number))
    }

    func testNumericTupleExpressionType2() throws {
        XCTAssertEqual(try expressionType("pi 5"), .list(.number))
    }

    func testNumericTupleExpressionType3() throws {
        XCTAssertEqual(try expressionType("(1 5)"), .list(.number))
    }

    func testNumericTupleExpressionType4() {
        XCTAssertEqual(try expressionType("(pi 5)"), .list(.number))
    }

    func testMixedTupleExpressionType() throws {
        XCTAssertEqual(try expressionType("1 red"), .list(.any))
    }

    func testBlockExpressionType() {
        XCTAssertEqual(try expressionType("cube"), .mesh)
    }

    func testBlockExpressionType2() {
        XCTAssertEqual(try expressionType("cube { size 1 }"), .mesh)
    }

    func testFunctionExpressionType() {
        XCTAssertEqual(try expressionType("rnd"), .number)
    }

    func testFunctionExpressionType2() {
        XCTAssertEqual(try expressionType("(cos pi)"), .number)
    }

    func testFunctionExpressionType3() {
        XCTAssertEqual(try expressionType("cos(pi)"), .number)
    }

    func testCustomBlockReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo { 5 }
        foo
        """), .number)
    }

    func testCustomBlockExpressionReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo { 5 + 1 }
        foo
        """), .number)
    }

    func testCustomBlockDefineReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            define bar "hello"
            bar
        }
        foo
        """), .string)
    }

    func testCustomBlockOptionReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            option bar "hello"
            bar
        }
        foo { bar "goodbye" }
        """), .string)
    }

    func testCustomBlockCallReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            define bar "hello"
            bar
        }
        define bar {
            define baz foo()
            "dog" baz
        }
        bar
        """), .list(.string))
    }

    func testCustomBlockConditionalReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            option bar true
            if bar {
                "Hello"
            } else {
                55
            }
        }
        foo { bar true }
        """), .union([.string, .number]))
    }

    func testCustomBlockLoopReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            option count 1
            for i in 1 to count {
                i
            }
        }
        foo { count 5 }
        """), .list(.number))
    }

    func testCustomBlockRecursiveReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo {
            option count 1
            if count > 0 {
                count
                foo { count count - 1 }
            }
        }
        foo { count 5 }
        """), .union([.list(.any), .void])) // TODO: .list(.number)
    }

    func testColorPropertyMemberType() {
        XCTAssertEqual(try expressionType("color.red"), .number)
    }

    func testBlockMemberType() {
        XCTAssertEqual(try expressionType("cube.bounds"), .bounds)
    }

    func testCustomConstantMemberType() {
        XCTAssertEqual(try expressionType("""
        define foo red
        foo.green
        """), .number)
    }

    func testCustomBlockResultMemberType() {
        XCTAssertEqual(try expressionType("""
        define foo { cube }
        foo.bounds
        """), .bounds)
    }

    func testCustomFunctionResultMemberType() {
        XCTAssertEqual(try expressionType("""
        define foo() { red }
        foo.blue
        """), .number)
    }

    // MARK: Type unions

    func testTypeUnionIsOrderIndependent() {
        let type = ValueType.union([.string, .number])
        XCTAssertEqual(type, .union([.number, .string]))
    }

    func testSimpleTypeUnion() {
        let type = ValueType.string.union(.number)
        XCTAssertEqual(type, .union([.string, .number]))
    }

    func testSubtypeUnion() {
        let type = ValueType.string.union(.any)
        XCTAssertEqual(type, .any)
    }

    func testSubtypeUnion2() {
        let type = ValueType.any.union(.number)
        XCTAssertEqual(type, .any)
    }

    func testSimpleTypeUnionWithUnion() {
        var type = ValueType.string.union(.number)
        type.formUnion(.boolean)
        XCTAssertEqual(type, .union([.string, .number, .boolean]))
    }

    func testMergeSimpleTypeUnions() {
        var type = ValueType.union([.string, .number])
        type.formUnion(.union([.number, .boolean]))
        XCTAssertEqual(type, .union([.string, .number, .boolean]))
    }

    func testMergeTypeUnionsWithSubtypes() {
        var type = ValueType.union([.number, .any])
        type.formUnion(.union([.number, .boolean]))
        XCTAssertEqual(type, .any)
    }

    // MARK: Type conversion

    func testCastNumberToNumberTuple() {
        XCTAssert(Value(1).isConvertible(to: .tuple([.number])))
        XCTAssertEqual(try evaluate("1", as: .tuple([.number])), [.number(1)])
    }

    func testCastNumberToNumberList() {
        XCTAssert(Value(1).isConvertible(to: .list(.number)))
        XCTAssertEqual(try evaluate("1", as: .list(.number)), [.number(1)])
    }

    func testCastNumberToColor() {
        XCTAssert(Value(1).isConvertible(to: .color))
        XCTAssertEqual(try evaluate("1", as: .color), .color(.white))
    }

    func testCastNumberToColorList() {
        XCTAssert(Value(1).isConvertible(to: .list(.color)))
        XCTAssertEqual(try evaluate("1", as: .list(.color)), [.color(.white)])
    }

    func testCastNumericCoupletToColor() {
        XCTAssert(Value(1, 0.5).isConvertible(to: .color))
        XCTAssertEqual(try evaluate("1 0.5", as: .color),
                       .color(Color.white.withAlpha(0.5)))
    }

    func testCastNumericTripletToColor() {
        XCTAssert(Value(1, 0.5, 0.1).isConvertible(to: .color))
        XCTAssertEqual(try evaluate("1 0.5 0.1", as: .color),
                       .color(Color(1, 0.5, 0.1)))
    }

    func testCastNumericQuadrupletToColor() {
        XCTAssert(Value(1, 0.5, 0.1, 0.2).isConvertible(to: .color))
        XCTAssertEqual(try evaluate("1 0.5 0.1 0.2", as: .color),
                       .color(Color(1, 0.5, 0.1, 0.2)))
    }

    func testCastNumericQuintupletToColor() {
        XCTAssertFalse(Value(1, 0.5, 0.1, 0.2, 0.3).isConvertible(to: .color))
        XCTAssertThrowsError(try evaluate("1 0.5 0.1 0.2 0.3", as: .color)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .unexpectedArgument(for: "", max: 4))
        }
    }

    func testCastEmptyTupleToColor() {
        XCTAssertFalse(Value([]).isConvertible(to: .color))
        XCTAssertThrowsError(try evaluate("()", as: .color)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "", index: 0, expected: "color", got: "tuple"
            ))
        }
    }

    func testCastColorWithAlphaToColor() {
        XCTAssert(Value(.color(.red), 0.5).isConvertible(to: .color))
        XCTAssertEqual(try evaluate("red 0.5", as: .color),
                       .color(Color.red.withAlpha(0.5)))
    }

    func testCastColorToNumberList() {
        XCTAssert(Value.color(.red).isConvertible(to: .list(.number)))
        XCTAssertEqual(try evaluate("red", as: .list(.number)), [1, 0, 0, 1])
    }

    func testCastColorWithAlphaToNumberList() {
        XCTAssert(Value(.color(.red), 0.5).isConvertible(to: .list(.number)))
        XCTAssertEqual(try evaluate("red 0.5", as: .list(.number)),
                       [1, 0, 0, 0.5])
    }

    func testCastNumericCoupletToNumberList() {
        XCTAssert(Value(1, 0.5).isConvertible(to: .list(.number)))
        XCTAssertEqual(try evaluate("1 0.5", as: .list(.number)), [1, 0.5])
    }

    func testCastNumericCoupletToAnyList() {
        XCTAssert(Value(1, 0.5).isConvertible(to: .list(.any)))
        XCTAssertEqual(try evaluate("1 0.5", as: .list(.any)), [1, 0.5])
    }

    func testCastMixedTupleToStringList() {
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: .list(.string)))
        XCTAssertEqual(try evaluate("\"foo\" 0.5 true", as: .list(.string)),
                       ["foo", "0.5", "true"])
    }

    func testCastNumericCoupletToNumberTuple() {
        let type = ValueType.tuple([.number, .number])
        XCTAssert(Value(1, 0.5).isConvertible(to: type))
        XCTAssertEqual(try evaluate("1 0.5", as: type), [1, 0.5])
    }

    func testCastNumericCoupletToAnyTuple() {
        let type = ValueType.tuple([.any, .any])
        XCTAssert(Value(1, 0.5).isConvertible(to: type))
        XCTAssertEqual(try evaluate("1 0.5", as: type), [1, 0.5])
    }

    func testCastMixedTupleToMixedTuple() {
        let type = ValueType.tuple([.string, .number, .boolean])
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: type))
        XCTAssertEqual(try evaluate("\"foo\" 0.5 true", as: type),
                       ["foo", 0.5, true])
    }

    func testCastMixedTupleToStringTuple() {
        let type = ValueType.tuple([.string, .string, .string])
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: type))
        XCTAssertEqual(try evaluate("\"foo\" 0.5 true", as: type),
                       ["foo", "0.5", "true"])
    }

    func testCastMixedTupleToString() {
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: .string))
        XCTAssertEqual(try evaluate("\"foo\" 0.5 true", as: .string),
                       "foo0.5 true")
    }

    func testCastMixedNestedTupleToString() {
        XCTAssert(Value("foo", Value(0.5, 1), "bar", true).isConvertible(to: .string))
        XCTAssertEqual(try evaluate("\"foo\" (0.5 1) \"bar\" true", as: .string),
                       "foo0.5 1bartrue")
    }
}
