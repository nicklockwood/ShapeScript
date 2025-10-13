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
    do {
        try program.evaluate(in: context)
    } catch let error as RuntimeError {
        switch error.type {
        case .fileNotFound, .unusedValue:
            break
        default:
            throw error
        }
    }
    return try program.statements.last?.staticType(in: context) ?? .void
}

private func symbol(for name: String? = nil, in definition: String) throws -> Symbol? {
    let program = try parse(definition)
    let context = EvaluationContext(source: "", delegate: nil)
    try program.evaluate(in: context)
    if let name {
        return context.symbol(for: name)
    }
    guard case let .define(identifier, _) = program.statements.last?.type else {
        return nil
    }
    return context.symbol(for: identifier.name)
}

private func functionType(
    for name: String? = nil,
    in definition: String,
    file: StaticString = #file,
    line: UInt = #line
) throws -> FunctionType {
    guard case let .function(functionType, _) = try symbol(for: name, in: definition) else {
        XCTFail("Function definition not found", file: file, line: line)
        return (.any, .any)
    }
    return functionType
}

private func blockType(
    for name: String? = nil,
    in definition: String,
    file: StaticString = #file,
    line: UInt = #line
) throws -> BlockType {
    guard case let .block(blockType, _) = try symbol(for: name, in: definition) else {
        XCTFail("Block definition not found", file: file, line: line)
        return .init([:], [:], .any, .any)
    }
    return blockType
}

private func evaluate(
    _ source: String,
    as type: ValueType = .any,
    file: StaticString = #file,
    line: UInt = #line
) throws -> Value {
    var lines = source.split(separator: "\n")
    lines[lines.count - 1] = "define foo_ \(lines[lines.count - 1])"
    let source = lines.joined(separator: "\n")
    let program = try parse(source)
    guard case let .define(_, definition) = program.statements.last?.type,
          case let .expression(expression) = definition.type
    else {
        XCTFail("Expression not found", file: file, line: line)
        return .void
    }
    let delegate = TestDelegate()
    let context = EvaluationContext(source: source, delegate: delegate)
    try program.evaluate(in: context)
    return try expression.evaluate(as: type, for: "", in: context)
}

final class TypesystemTests: XCTestCase {
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

    func testArithmeticExpressionType3() {
        XCTAssertEqual(try expressionType("\"1\" + 2"), .number)
    }

    func testVectorExpressionType() {
        XCTAssertEqual(try expressionType("(1 2) * 3"), .list(.number))
    }

    func testVectorExpressionType2() {
        XCTAssertEqual(try expressionType("2 + (3 4)"), .list(.number))
    }

    func testVectorExpressionType3() {
        XCTAssertEqual(try expressionType("(\"1\" \"2\") * 3"), .list(.number))
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
        // Note: interpreted as list instead of tuple to improve option inference
        XCTAssertEqual(try expressionType("1 5"), .list(.number))
    }

    func testNumericTupleExpressionType2() throws {
        // TODO: seems like we can do something better here?
        XCTAssertEqual(try expressionType("(pi 5)"), .list(.any))
    }

    func testNumericTupleExpressionType3() throws {
        XCTAssertEqual(try expressionType("(1 5)"), .list(.number))
    }

    func testMixedTupleExpressionType() throws {
        // TODO: should this be a tuple or color list instead?
        XCTAssertEqual(try expressionType("1 red"), .list(.any))
    }

    func testBlockExpressionType() {
        XCTAssertEqual(try expressionType("cube"), .mesh)
    }

    func testBlockExpressionType2() {
        XCTAssertEqual(try expressionType("cube { size 1 }"), .mesh)
    }

    func testBlockExpressionType3() {
        XCTAssertEqual(try expressionType("square"), .path)
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

    func testEmptyTupleCountType() {
        XCTAssertEqual(try expressionType("""
        define foo ()
        foo.count
        """), .number)
    }

    func testUnionMemberType() {
        XCTAssertEqual(try expressionType("""
        define foo () {
            if rnd > 0.5 {
                (1 2 1)
            } else {
                "#f00"
            }
        }
        foo.blue
        """), .number)
    }

    func testPolygonsMemberType() {
        XCTAssertEqual(try expressionType("""
        cube.polygons
        """), .list(.polygon))
    }

    func testPolygonPointsMemberType() {
        XCTAssertEqual(try expressionType("""
        cube.polygons.first.points
        """), .list(.point))
    }

    func testPointColorMemberType() {
        XCTAssertEqual(try expressionType("""
        (square { color red }).points.first.color
        """), .optional(.color))
    }

    func testPointColorMemberType2() {
        XCTAssertEqual(try expressionType("""
        square.points.first.color
        """), .optional(.color))
    }

    func testPointCurvedMemberType() {
        XCTAssertEqual(try expressionType("""
        square.points.first.isCurved
        """), .boolean)
    }

    func testImportShapeType() {
        XCTAssertEqual(try expressionType("""
        import "foo.shape"
        """), .any)
    }

    func testImportModelType() {
        XCTAssertEqual(try expressionType("""
        import "foo.obj"
        """), .mesh)
    }

    func testImportModelType2() {
        XCTAssertEqual(try expressionType("""
        define foo {
            import "foo.obj"
        }
        foo
        """), .mesh)
    }

    func testImportTextType() {
        XCTAssertEqual(try expressionType("""
        import "foo.txt"
        """), .string)
    }

    func testImportJSONType() {
        XCTAssertEqual(try expressionType("""
        import "foo.json"
        """), .any)
    }

    // MARK: Function parameter inference

    func testInferSimpleFunctionParameter() throws {
        let type = try functionType(in: "define foo(bar) { bar + 1 }")
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testInferSimpleFunctionParameters() throws {
        let type = try functionType(in: "define foo(bar baz) { bar + baz }")
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector, .numberOrVector]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testInferFunctionParameterInBlock() throws {
        let type = try functionType(in: """
        define foo(bar) {
            cube {
                color bar
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.color]))
        XCTAssertEqual(type.returnType, .mesh)
    }

    func testInferFunctionParameterUsedInImport() throws {
        let type = try functionType(in: """
        define foo(bar) {
            import bar
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.string]))
        XCTAssertEqual(type.returnType, .any)
    }

    func testComplexNestedFunctionParameters() throws {
        let type = try functionType(in: """
        define foo(bar) { bar + 1 }
        define bar(baz quux) {
            foo(baz) + 1
            print quux
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector, .list(.any)]))
        XCTAssertEqual(type.returnType, .number)
    }

    func testConditionalFunctionParameter() throws {
        let type = try functionType(in: """
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
        let type = try functionType(in: """
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
        let type = try functionType(in: """
        define foo(bar baz) {
            if bar = baz {
                bar + 1
            } else {
                print baz
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector, .list(.any)]))
        XCTAssertEqual(type.returnType, .union([.number, .void]))
    }

    func testConditionalFunctionParameters2() throws {
        let type = try functionType(in: """
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
        let type = try functionType(in: """
        define foo(bar baz) {
            if baz > 1 {
                print bar
            } else {
                print bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.union([.number, .radians, .list(.any)]), .number]))
        XCTAssertEqual(type.returnType, .void)
    }

    func testConditionalFunctionParameters4() throws {
        let type = try functionType(in: """
        define foo(bar) {
            if true {
                print bar + 1
                texture bar
            } else {
                print bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.union([.numberOrVector, .texture]).simplified()]))
        XCTAssertEqual(type.returnType, .void)
    }

    func testFunctionParameterInferenceInsideTuple() throws {
        let type = try functionType(in: """
        define foo(bar baz) {
            (bar and baz 2)
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.boolean, .boolean]))
    }

    func testFunctionParameterInferenceInsideMember() throws {
        let type = try functionType(in: """
        define foo(bar) {
            (bar + 3 2).count
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector]))
    }

    func testFunctionParameterInferenceInsideSubscript() throws {
        let type = try functionType(in: """
        define foo(bar baz) {
            (-bar 2)[baz]
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector, .union([.number, .string])]))
    }

    func testFunctionParameterInferenceInsideNestedDefine() throws {
        let type = try functionType(in: """
        define foo(bar) {
            define baz bar + 1
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector]))
    }

    func testFunctionParameterInferenceInsideNestedFunctionDefine() throws {
        let type = try functionType(in: """
        define foo(bar) {
            define baz() {
                bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector]))
    }

    func testFunctionParameterInferenceInsideNestedBlockDefine() throws {
        let type = try functionType(in: """
        define foo(bar) {
            define baz() {
                bar + 1
            }
        }
        """)
        XCTAssertEqual(type.parameterType, .tuple([.numberOrVector]))
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

    // MARK: Block type inference

    func testEmptyBlock() throws {
        let type = try blockType(in: """
        define foo {}
        """)
        XCTAssertEqual(type.childTypes, .void)
        XCTAssertEqual(type.returnType, .void)
    }

    func testBlockPrintingChildren() throws {
        let type = try blockType(in: """
        define foo {
            print children
        }
        """)
        XCTAssertEqual(type.childTypes, .any)
        XCTAssertEqual(type.returnType, .void)
    }

    func testBlockWithChildMeshes() throws {
        let type = try blockType(in: """
        define foo {
            union children
        }
        """)
        XCTAssertEqual(type.childTypes, .mesh)
        XCTAssertEqual(type.returnType, .mesh)
    }

    func testBlockWithMixedChildTypes() throws {
        let input = """
        define foo {
            define foo children + 1
            union children
        }
        """
        let type = try blockType(in: input)
        XCTAssertEqual(type.childTypes, .union([.mesh, .numberOrVector]).simplified())
        XCTAssertEqual(type.returnType, .mesh)

        // No arguments
        XCTAssertThrowsError(try evaluate("\(input)\nfoo")) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Missing argument")
            XCTAssertEqual(error?.hint, """
            The 'foo' symbol expects an argument of type mesh, number, vector, or block.
            """)
        }

        // Empty block argument
        XCTAssertEqual(try evaluate("\(input)\nfoo {}").type, .mesh)

        // Empty tuple argument
        XCTAssertEqual(try evaluate("\(input)\nfoo ()").type, .mesh)

        // Mesh argument
        XCTAssertThrowsError(try evaluate("\(input)\nfoo cube")) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, """
            The left operand for '+' should be a number or vector, not a mesh.
            """)
        }

        // Numeric argument
        XCTAssertThrowsError(try evaluate("\(input)\nfoo 1")) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, """
            The argument for 'union' should be a mesh or block, not a number.
            """)
        }
    }

    func testBlockWithIncompatibleChild() throws {
        let input = """
        define foo {
            define objects children cube
            union objects
        }
        """
        let type = try blockType(in: input)
        XCTAssertEqual(type.childTypes, .any)
        XCTAssertEqual(type.returnType, .mesh)
        XCTAssertThrowsError(try evaluate("\(input)\nfoo 1")) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Type mismatch")
            XCTAssertEqual(error?.hint, """
            The argument for 'union' should be a mesh or block, not a tuple.
            """)
        }
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

    func testUnionSubtypeSimplification() {
        XCTAssertEqual(ValueType.union([.number, .any]).simplified(), .any)
        XCTAssertEqual(ValueType.union([.any, .boolean]).simplified(), .any)
        XCTAssertEqual(ValueType.union([.list(.any), .list(.number)]).simplified(), .list(.any))
    }

    func testNestedUnionSimplification() {
        XCTAssertEqual(
            ValueType.union([.boolean, .union([.number, .string])]).simplified(),
            .union([.boolean, .number, .string])
        )
        XCTAssertEqual(
            ValueType.list(.union([.number, .any])).simplified(),
            .list(.any)
        )
        XCTAssertEqual(
            ValueType.tuple([.union([.number, .any]), .union([.any, .boolean])]).simplified(),
            .tuple([.any, .any])
        )
        XCTAssertEqual(
            ValueType.object(["foo": .union([.number, .any]), "bar": .union([.any, .boolean])]).simplified(),
            .object(["foo": .any, "bar": .any])
        )
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

    func testCastVectorToSizeAndViceVersa() {
        XCTAssert(Value.vector(.one).isConvertible(to: .size))
        XCTAssert(Value.size(.one).isConvertible(to: .vector))
        XCTAssertEqual(try evaluate("cube.bounds.size", as: .vector), .vector(.one))
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
        XCTAssertEqual(
            try evaluate("1 0.5", as: .color),
            .color(Color.white.withAlpha(0.5))
        )
    }

    func testCastNumericTripletToColor() {
        XCTAssert(Value(1, 0.5, 0.1).isConvertible(to: .color))
        XCTAssertEqual(
            try evaluate("1 0.5 0.1", as: .color),
            .color(Color(1, 0.5, 0.1))
        )
    }

    func testCastNumericQuadrupletToColor() {
        XCTAssert(Value(1, 0.5, 0.1, 0.2).isConvertible(to: .color))
        XCTAssertEqual(
            try evaluate("1 0.5 0.1 0.2", as: .color),
            .color(Color(1, 0.5, 0.1, 0.2))
        )
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
                for: "", expected: "color", got: "empty tuple"
            ))
        }
    }

    func testCastColorWithAlphaToColor() {
        XCTAssert(Value(.color(.red), 0.5).isConvertible(to: .color))
        XCTAssertEqual(
            try evaluate("red 0.5", as: .color),
            .color(Color.red.withAlpha(0.5))
        )
    }

    func testCastColorToNumberList() {
        XCTAssert(Value.color(.red).isConvertible(to: .list(.number)))
        XCTAssertEqual(try evaluate("red", as: .list(.number)), [1, 0, 0, 1])
    }

    func testCastColorWithAlphaToNumberList() {
        XCTAssert(Value(.color(.red), 0.5).isConvertible(to: .list(.number)))
        XCTAssertEqual(
            try evaluate("red 0.5", as: .list(.number)),
            [1, 0, 0, 0.5]
        )
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
        XCTAssertEqual(
            try evaluate("\"foo\" 0.5 true", as: .list(.string)),
            ["foo", "0.5", "true"]
        )
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
        XCTAssertEqual(
            try evaluate("\"foo\" 0.5 true", as: type),
            ["foo", 0.5, true]
        )
    }

    func testCastMixedTupleToStringTuple() {
        let type = ValueType.tuple([.string, .string, .string])
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: type))
        XCTAssertEqual(
            try evaluate("\"foo\" 0.5 true", as: type),
            ["foo", "0.5", "true"]
        )
    }

    func testCastMixedTupleToString() {
        XCTAssert(Value("foo", 0.5, true).isConvertible(to: .string))
        XCTAssertEqual(
            try evaluate("\"foo\" 0.5 true", as: .string),
            "foo0.5 true"
        )
    }

    func testCastMixedNestedTupleToString() {
        XCTAssert(Value("foo", Value(0.5, 1), "bar", true).isConvertible(to: .string))
        XCTAssertEqual(
            try evaluate("\"foo\" (0.5 1) \"bar\" true", as: .string),
            "foo0.5 1bartrue"
        )
    }

    func testCastTextureToString() throws {
        let url = TestDelegate().resolveURL(for: "Stars1.jpg")
        let texture = Texture.file(name: "Stars1.jpg", url: url, intensity: 1)
        XCTAssert(Value.texture(texture).isConvertible(to: .string))
        XCTAssertEqual(try evaluate("""
        texture "Stars1.jpg"
        define foo texture
        foo
        """, as: .string), .string(url.path))
    }

    func testCastFontToString() throws {
        #if canImport(CoreGraphics)
        XCTAssert(Value.font("times").isConvertible(to: .string))
        XCTAssertEqual(try evaluate("""
        font "EdgeOfTheGalaxyRegular-OVEa6.otf"
        define foo font
        foo
        """, as: .string), .string("Edge of the Galaxy Regular"))
        #endif
    }

    func testCastFontToTexture() throws {
        #if canImport(CoreGraphics)
        XCTAssertFalse(Value.font("times").isConvertible(to: .texture))
        XCTAssertThrowsError(try evaluate("font \"times\"\nfont", as: .texture)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(for: "", index: -1, expected: "texture", got: "font"))
        }
        #endif
    }

    func testCastTextureToFont() throws {
        #if canImport(CoreGraphics)
        let url = TestDelegate().resolveURL(for: "Stars1.jpg")
        let texture = Texture.file(name: "Stars1.jpg", url: url, intensity: 1)
        XCTAssertFalse(Value.texture(texture).isConvertible(to: .font))
        XCTAssertThrowsError(try evaluate("texture \"Stars1.jpg\"\ntexture", as: .font)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(for: "", index: -1, expected: "font", got: "texture"))
        }
        #endif
    }

    func testCastPathToMesh() throws {
        XCTAssert(Value.path(.square()).isConvertible(to: .mesh))
        XCTAssertNotNil(try evaluate("square", as: .mesh))
    }

    func testCastPolygonToPath() throws {
        XCTAssertNotNil(try evaluate("""
        define triangle polygon {
            point 0 0
            point 1 0
            point 1 1
        }
        triangle
        """, as: .path))
    }

    func testCastPolygonToMesh() throws {
        XCTAssertNotNil(try evaluate("""
        define triangle polygon {
            point 0 0
            point 1 0
            point 1 1
        }
        triangle
        """, as: .mesh))
    }

    func testCastStringToInt() throws {
        XCTAssertEqual(try evaluate("\"1\" + 2", as: .any), 3)
        XCTAssertEqual(try evaluate("\"2\" * \"3\"", as: .any), 6)
        XCTAssertEqual(try evaluate("3 - \"4\"", as: .any), -1)
        XCTAssertEqual(try evaluate("+\"5\"", as: .any), 5)
        XCTAssertEqual(try evaluate("-\"7\"", as: .any), -7)
    }

    func testCastStringToDouble() throws {
        XCTAssertEqual(try evaluate("\"1.5\" + \"2.3\"", as: .any), 3.8)
    }

    func testCastStringTupleToVector() throws {
        XCTAssertEqual(try evaluate("\"1.5\" \"2.3\" \"0\"", as: .vector), .vector([1.5, 2.3, 0]))
    }

    func testCastStringToNumberOrList() throws {
        let type = ValueType.union([.list(.any), .number])
        XCTAssertEqual(try evaluate("\"foo\"", as: type), ["foo"])
    }

    func testCastHexStringToColor() throws {
        XCTAssertEqual(try evaluate("\"#f00\"", as: .color), .color(.red))
    }

    func testCastNestedTupleArguments() throws {
        let type = ValueType.tuple([.list(.string), .string])
        XCTAssert(Value(Value("foo", "bar"), "baz").isConvertible(to: type))
        XCTAssertEqual(
            try evaluate("(\"foo\" \"bar\") \"baz\"", as: type),
            [["foo", "bar"], "baz"]
        )
    }

    func testCastObjectToAnyList() {
        let type = ValueType.list(.any)
        let value = Value.object(["foo": "bar", "baz": "quux"])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), [value])
    }

    func testCastObjectToStringTupleList() {
        let type = ValueType.list(.tuple([.string, .string]))
        let value = Value.object(["foo": "bar", "baz": "quux"])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), [["baz", "quux"], ["foo", "bar"]])
    }

    func testCastObjectToStringNumberTupleList() {
        let type = ValueType.list(.tuple([.string, .number]))
        let value = Value.object(["foo": 1, "baz": 2])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), [["baz", 2], ["foo", 1]])
    }

    func testCastObjectToTuple() {
        let type = ValueType.tuple([.tuple([.string, .boolean]), .tuple([.string, .number])])
        let value = Value.object(["foo": 1, "baz": true])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), [["baz", true], ["foo", 1]])
    }

    func testCastValueToOptional() {
        let type = ValueType.optional(.boolean)
        XCTAssert(Value.boolean(true).isConvertible(to: type))
        XCTAssert(Value.void.isConvertible(to: type))
        XCTAssertFalse(Value.number(5).isConvertible(to: type))
        XCTAssertThrowsError(try evaluate("5", as: type)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "",
                index: -1,
                expected: "boolean", // Note: empty tuple not mentioned
                got: "number"
            ))
        }
    }

    func testCastValueToTupleWithOptional() {
        let type = ValueType.tuple([.boolean, .optional(.string)])
        let value = Value.boolean(true)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), [true])
    }

    func testCastSingleElementTupleToList() {
        let type = ValueType.list(.number)
        let value = Value.tuple([5])
        XCTAssertEqual(value.as(type), [5])
    }

    func testCastSingleElementTupleToNumber() {
        let type = ValueType.number
        let value = Value.tuple([5])
        XCTAssertEqual(value.as(type), 5.0)
    }

    func testCastSingleElementTupleToRange() {
        let type = ValueType.range
        let range = RangeValue(from: 5, to: 6)
        let value = Value.tuple([.range(range)])
        XCTAssertEqual(value.as(type), .range(range))
    }

    func testCastSingleElementTupleToRangeOrString() {
        let type = ValueType.union([.range, .string])
        let range = RangeValue(from: 5, to: 6)
        let value = Value.tuple([.range(range)])
        XCTAssertEqual(value.as(type), .range(range))
    }

    func testCastSingleElementTupleToString() {
        let type = ValueType.string
        let value = Value.tuple([5])
        XCTAssertEqual(value.as(type), "5")
    }

    func testCastSingleElementTupleToAny() {
        let type = ValueType.any
        let value = Value.tuple(["foo"])
        XCTAssertEqual(value.as(type), "foo")
    }

    func testCastObjectToMaterial() {
        let type = ValueType.material
        let value = Value.object(["color": .color(.red), "metallicity": .number(0.5)])
        XCTAssertEqual(value.as(type), .material(.init(
            opacity: nil,
            albedo: .color(.red),
            normals: nil,
            metallicity: .color(.init(0.5, 0.5)),
            roughness: nil,
            glow: nil
        )))
    }

    func testCastInvalidObjectToMaterial() {
        let type = ValueType.material
        let value = Value.object(["color": .color(.red), "metalicity": .number(0.5)])
        XCTAssertFalse(value.isConvertible(to: type))
    }

    func testCastObjectToCompatibleObjectType() {
        let type = ValueType.object(["foo": .color, "bar": .string])
        let value = Value.object(["foo": .number(1), "bar": .boolean(true)])
        XCTAssertEqual(value.as(type), .object(["foo": .color(.white), "bar": .string("true")]))
    }

    func testCastObjectToAnyObjectType() {
        let type = ValueType.anyObject
        let value = Value.object(["foo": .color(.red), "bar": .string("baz")])
        XCTAssertEqual(value.as(type), value)
    }

    // MARK: Angle type conversions

    func testCastRadiansToNumber() {
        let type = ValueType.number
        let value = Value.radians(.pi)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .number(.pi))
    }

    func testCastHalfturnsToNumber() {
        let type = ValueType.number
        let value = Value.halfturns(1)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .number(1))
    }

    func testCastNumberToRadians() {
        let type = ValueType.radians
        let value = Value.number(.pi)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .radians(.pi))
    }

    func testCastNumberToHalfturns() {
        let type = ValueType.halfturns
        let value = Value.number(1)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .halfturns(1))
    }

    func testCastRadiansToHalfturns() {
        let type = ValueType.halfturns
        let value = Value.radians(.pi)
        XCTAssertFalse(value.isConvertible(to: type))
        XCTAssertThrowsError(try evaluate("pi", as: .halfturns))
        XCTAssertThrowsError(try evaluate("pi * 2", as: .halfturns))
        XCTAssertThrowsError(try evaluate("pi / 2", as: .halfturns))
    }

    func testRadiansMathTypes() {
        XCTAssertEqual(try evaluate("pi", as: .any), .radians(.pi))
        XCTAssertEqual(try evaluate("-pi", as: .any), .radians(-.pi))
        XCTAssertEqual(try evaluate("pi + pi", as: .any), .radians(.pi + .pi))
        XCTAssertEqual(try evaluate("pi - pi / 2", as: .any), .radians(.pi / 2))
        XCTAssertEqual(try evaluate("pi * 2", as: .any), .radians(.pi * 2))
        XCTAssertEqual(try evaluate("-pi / 2", as: .any), .radians(-.pi / 2))
        XCTAssertEqual(try evaluate("2 * pi / pi", as: .any), .number(2))
        XCTAssertEqual(try evaluate("-(2 * pi) / pi", as: .any), .number(-2))
        XCTAssertEqual(try evaluate("2 * pi * 0.5 + 2 // perimeter", as: .any), .number(.pi + 2))
        XCTAssertEqual(try evaluate("180 / pi", as: .any), .radians(180 / .pi)) // TODO: should this error?
        XCTAssertEqual(try evaluate("pi * pi", as: .any), .number(.pi * .pi)) // TODO: should this error?
    }

    func testDegreesToRadiansExpressions() throws {
        XCTAssertEqual(try evaluate("30 / 180 * pi", as: .radians), .radians(.pi / 6))
        XCTAssertEqual(try evaluate("30 / 180 * pi", as: .number), .number(.pi / 6))
        XCTAssertEqual(try evaluate("""
        define DEG_TO_RAD pi / 180
        30 * DEG_TO_RAD
        """, as: .radians), .radians(.pi / 6))
        XCTAssertEqual(try evaluate("""
        define DEG_TO_RAD pi / 180
        30 * DEG_TO_RAD
        """, as: .number), .number(.pi / 6))
        XCTAssertEqual(try evaluate("""
        define RAD_TO_DEG 1 / pi * 180
        30 / RAD_TO_DEG
        """, as: .radians), .radians(.pi / 6))
    }

    func testRadiansToDegreesExpressions() throws {
        XCTAssertEqual(try evaluate("""
        define RAD_TO_DEG 180 / pi
        pi / 2 * RAD_TO_DEG
        """, as: .number), .number(90))
        XCTAssertEqual(try evaluate("""
        define DEG_TO_RAD pi / 180
        pi * 0.25 / DEG_TO_RAD
        """, as: .number), .number(45))
    }

    // MARK: Rotation type conversions

    func testCastNumberToRotation() {
        let type = ValueType.rotation
        let value = Value.number(0.5)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .rotation(.roll(.halfturns(0.5))))
    }

    func testCastNumberTupleToRotation() {
        let type = ValueType.rotation
        let value = Value.tuple([0, 0.5, 0])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .rotation(.yaw(.halfturns(0.5))))
    }

    func testCastHalfTurnsToRotation() {
        let type = ValueType.rotation
        let value = Value.halfturns(0.5)
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .rotation(.roll(.halfturns(0.5))))
    }

    func testCastHalfturnsTupleToRotation() {
        let type = ValueType.rotation
        let value = Value.tuple([0, 0, .halfturns(0.5)])
        XCTAssert(value.isConvertible(to: type))
        XCTAssertEqual(value.as(type), .rotation(.pitch(.halfturns(0.5))))
    }

    func testCastRadiansToRotation() {
        let type = ValueType.rotation
        let value = Value.radians(.pi / 2)
        XCTAssertFalse(value.isConvertible(to: type))
        XCTAssertThrowsError(try evaluate(parse("rotate pi"), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "rotate",
                index: -1,
                expected: "rotation",
                got: "angle in radians"
            ))
        }
    }

    func testCastRadiansInTupleToRotation() {
        let type = ValueType.rotation
        let value = Value.tuple([0, .radians(.pi / 2), 0])
        XCTAssertFalse(value.isConvertible(to: type))
        XCTAssertThrowsError(try evaluate(parse("rotate pi"), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .typeMismatch(
                for: "rotate",
                index: -1,
                expected: "rotation",
                got: "angle in radians"
            ))
        }
    }

    func testCastVectorToRotation() {
        let type = ValueType.rotation
        let value = Value.vector([0, 0, 0.5])
        XCTAssertFalse(value.isConvertible(to: type))
    }
}
