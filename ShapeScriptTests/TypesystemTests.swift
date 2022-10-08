//
//  TypesystemTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 19/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private func expressionType(_ source: String) throws -> ValueType {
    let program = try parse(source)
    let context = EvaluationContext(source: "", delegate: nil)
    try? program.evaluate(in: context)
    return try program.statements.last?.staticType(in: context) ?? .void
}

private func functionType(_ definition: String) throws -> FunctionType {
    let program = try parse(definition)
    let context = EvaluationContext(source: "", delegate: nil)
    try program.evaluate(in: context)
    guard case let .define(identifier, _) = program.statements.last?.type,
          case let .function(functionType, _) = context.symbol(for: identifier.name)
    else {
        XCTFail()
        return (.any, .any)
    }
    return functionType
}

private func functionType(for name: String, in definition: String) throws -> FunctionType {
    let program = try parse(definition)
    let context = EvaluationContext(source: "", delegate: nil)
    try program.evaluate(in: context)
    guard case let .function(functionType, _) = context.symbol(for: name) else {
        XCTFail()
        return (.any, .any)
    }
    return functionType
}

private func evaluate(_ source: String, as type: ValueType) throws -> Value {
    var lines = source.split(separator: "\n")
    lines[lines.count - 1] = "define foo_ \(lines[lines.count - 1])"
    let source = lines.joined(separator: "\n")
    let program = try parse(source)
    guard case let .define(_, definition) = program.statements.last?.type,
          case let .expression(expression) = definition.type
    else {
        XCTFail()
        return .void
    }
    let delegate = TestDelegate()
    let context = EvaluationContext(source: source, delegate: delegate)
    try program.evaluate(in: context)
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
        XCTAssertEqual(try expressionType("(pi 5)"), .list(.number))
    }

    func testNumericTupleExpressionType3() throws {
        XCTAssertEqual(try expressionType("(1 5)"), .list(.number))
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
        """), .list(.any)) // TODO: .list(.number)
    }

    func testCustomFunctionReturnType() {
        XCTAssertEqual(try expressionType("""
        define foo() { 5 + 1 }
        foo
        """), .number)
    }

    func testCustomFunctionReturnType2() {
        XCTAssertEqual(try expressionType("""
        define foo(bar) { bar + 1 }
        foo(1)
        """), .number)
    }

    func testCustomFunctionReturnType3() {
        XCTAssertEqual(try expressionType("""
        define foo(bar baz) { bar < baz }
        (foo 1 2)
        """), .boolean)
    }

    func testPropertySetterReturnsVoid() {
        XCTAssertEqual(try expressionType("""
        define foo() { color red }
        foo()
        """), .void)
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

    // MARK: Function parameter inference

    func testInferSimpleFunctionParameter() throws {
        let type = try functionType("define foo(bar) { bar + 1 }")
        XCTAssertEqual(type.parameterType, .tuple([.number]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testInferSimpleFunctionParameters() throws {
        let type = try functionType("define foo(bar baz) { bar + baz }")
        XCTAssertEqual(type.parameterType, .tuple([.number, .number]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testInferFunctionParameterInBlock() throws {
        let type = try functionType("""
        define foo(bar) {
            cube {
                color bar
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.color]))
        XCTAssertEqual(type.returnType, .mesh)
    }

    func testComplexNestedFunctionParameters() throws {
        let type = try functionType("""
        define foo(bar) { bar + 1 }
        define bar(baz quux) {
            foo(baz) + 1
            print quux
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.number, .list(.any)]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testConditionalFunctionParameter() throws {
        let type = try functionType("""
        define foo(bar) {
            if bar {
                "hello"
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.boolean]))
        XCTAssertEqual(type.returnType, .union([.string, .void]))
    }

    func testConditionalFunctionParameter2() throws {
        let type = try functionType("""
        define foo(bar) {
            if bar < 3 {
                "hello"
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.number]))
        XCTAssertEqual(type.returnType, .union([.string, .void]))
    }

    func testConditionalFunctionParameters() throws {
        let type = try functionType("""
        define foo(bar baz) {
            if bar = baz {
                bar + 1
            } else {
                print baz
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.number, .list(.any)]))
        XCTAssertEqual(type.returnType, .union([.number, .void]))
    }

    func testConditionalFunctionParameters2() throws {
        let type = try functionType("""
        define foo(bar baz) {
            if bar > 1 {
                print bar + 1
            } else {
                print not baz
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.number, .any]))
        XCTAssertEqual(type.returnType, .void)
    }

    func testConditionalFunctionParameters3() throws {
        let type = try functionType("""
        define foo(bar baz) {
            if baz > 1 {
                print bar
            } else {
                print bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.union([.number, .list(.any)]), .number]))
        XCTAssertEqual(type.returnType, .void)
    }

    func testConditionalFunctionParameters4() throws {
        let type = try functionType("""
        define foo(bar) {
            if true {
                print bar + 1
                texture bar
            } else {
                print bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.union([.number, .texture])]))
        XCTAssertEqual(type.returnType, .void)
    }

    func testErrorThrowingArgumentHasCorrectRange() throws {
        let name = "Nope.jpg"
        let program = try parse("""
        define foo(bar baz) {
            if baz {
                texture bar
            }
        }
        foo("\(name)" true)
        """)
        let range = program.source.range(of: "\"\(name)\"")
        let context = EvaluationContext(source: "", delegate: nil)
        XCTAssertThrowsError(try program.evaluate(in: context)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .fileNotFound(for: name, at: nil))
            XCTAssertEqual(error?.range, range)
        }
    }

    func testFunctionWithForwardReferenceToConstant() throws {
        let type = try functionType(for: "foo", in: """
        define foo() {
            bar
        }
        define bar 3
        """)
        XCTAssertEqual(type.parameterType, .void)
        XCTAssertEqual(type.returnType, .number)
    }

    func testFunctionWithForwardReferenceToFunction() throws {
        let type = try functionType(for: "foo", in: """
        define foo() {
            bar
        }
        define bar() {
            3
        }
        """)
        XCTAssertEqual(type.parameterType, .void)
        XCTAssertEqual(type.returnType, .number)
    }

    func testFunctionWithNestedForwardReferenceToFunction() throws {
        let type = try functionType(for: "foo", in: """
        define foo() {
            bar
        }
        define bar() {
            baz
        }
        define baz() {
            3
        }
        """)
        XCTAssertEqual(type.parameterType, .void)
        // TODO: this should actually be a number
        XCTAssertEqual(type.returnType, .any)
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

    func testCastTextureToString() throws {
        let url = TestDelegate().resolveURL(for: "Stars1.jpg")
        let texture = Texture.file(name: "Stars1.jpg", url: url)
        XCTAssert(Value.texture(texture).isConvertible(to: .string))
        XCTAssertEqual(try evaluate("""
        texture "Stars1.jpg"
        define foo texture
        foo
        """, as: .string), .string(url.path))
    }

    func testCastNestedTupleArguments() throws {
        let type = ValueType.tuple([.list(.string), .string])
        XCTAssert(Value(Value("foo", "bar"), "baz").isConvertible(to: type))
        XCTAssertEqual(try evaluate("(\"foo\" \"bar\") \"baz\"", as: type),
                       [["foo", "bar"], "baz"])
    }
}
