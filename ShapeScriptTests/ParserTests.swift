//
//  ParserTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 07/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

class ParserTests: XCTestCase {
    // MARK: Operators

    func testLeftAssociativity() {
        let input = "print 1 - 2 + 3"
        let printRange = input.range(of: "print")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "print", range: printRange),
                    Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .minus,
                                    Expression(type: .number(2), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .plus,
                            Expression(type: .number(3), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )
                ),
                range: printRange.lowerBound ..< range3.upperBound
            ),
        ]))
    }

    func testOperatorPrecedence() {
        let input = "color 1 * 2 + 3"
        let colorRange = input.range(of: "color")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "color", range: colorRange),
                    Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .times,
                                    Expression(type: .number(2), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .plus,
                            Expression(type: .number(3), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )
                ),
                range: colorRange.lowerBound ..< range3.upperBound
            ),
        ]))
    }

    func testOperatorPrecedence2() {
        let input = "color 1 / 2 * 3"
        let colorRange = input.range(of: "color")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "color", range: colorRange),
                    Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .divide,
                                    Expression(type: .number(2), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .times,
                            Expression(type: .number(3), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )
                ),
                range: colorRange.lowerBound ..< range3.upperBound
            ),
        ]))
    }

    func testNotOperatorPrecedence() {
        let input = "not a = b"
        let notRange = input.range(of: "not")!
        let aRange = input.range(of: "a")!
        let bRange = input.range(of: "b")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .expression(Expression(type: .tuple([
                    Expression(type: .identifier("not"), range: notRange),
                    Expression(
                        type: .infix(
                            Expression(type: .identifier("a"), range: aRange),
                            .equal,
                            Expression(type: .identifier("b"), range: bRange)
                        ),
                        range: aRange.lowerBound ..< input.endIndex
                    ),
                ]), range: input.startIndex ..< input.endIndex)),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testNotOperatorPrecedence2() {
        let input = "not a = not b"
        let notRange = input.range(of: "not")!
        let aRange = input.range(of: "a")!
        let notRange2 = input.range(of: "not", range: input.range(of: "not b")!)!
        let bRange = input.range(of: "b")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .expression(Expression(type: .tuple([
                    Expression(type: .identifier("not"), range: notRange),
                    Expression(
                        type: .infix(
                            Expression(type: .identifier("a"), range: aRange),
                            .equal,
                            Expression(type: .tuple([
                                Expression(type: .identifier("not"), range: notRange2),
                                Expression(type: .identifier("b"), range: bRange),
                            ]), range: notRange2.lowerBound ..< bRange.upperBound)
                        ),
                        range: aRange.lowerBound ..< input.endIndex
                    ),
                ]), range: input.startIndex ..< input.endIndex)),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testPrintNot() {
        let input = "print not"
        let printRange = input.range(of: "print")!
        let notRange = input.range(of: "not")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "print", range: printRange),
                    Expression(type: .identifier("not"), range: notRange)
                ),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testUnterminatedInfixExpression() {
        let input = "define foo 1 +"
        let range = input.endIndex ..< input.endIndex
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected operand.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: range),
                expected: "operand"
            )))
        }
    }

    func testInfixExpressionSplitOverTwoLines() {
        let input = """
        define foo 1 +
            bar
        """
        let range = input.range(of: "\n")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of line")
            XCTAssertEqual(error?.hint, "Expected operand.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .linebreak, range: range),
                expected: "operand"
            )))
        }
    }

    func testComparisonOperatorChaining() {
        let input = "print 1 < 2 < 3"
        let range = input.range(of: "<", range: input.range(of: "< 3")!)!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected operator '<'")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .infix(.lt), range: range),
                expected: nil
            )))
        }
    }

    func testEqualityOperatorChaining() {
        let input = "print 1 = 2 = 3"
        let range = input.range(of: "=", range: input.range(of: "= 3")!)!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected operator '='")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .infix(.equal), range: range),
                expected: nil
            )))
        }
    }

    func testCommandVsOperatorPrecedence() {
        let input = "print (a + b) * c"
        let printRange = input.range(of: "print")!
        let tupleRange = input.range(of: "(a + b)")!
        let aRange = input.range(of: "a")!
        let bRange = input.range(of: "b")!
        let cRange = input.range(of: "c")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "print", range: printRange),
                    Expression(type: .infix(
                        Expression(type: .tuple([
                            Expression(type: .infix(
                                Expression(type: .identifier("a"), range: aRange),
                                .plus,
                                Expression(type: .identifier("b"), range: bRange)
                            ), range: aRange.lowerBound ..< bRange.upperBound),
                        ]), range: tupleRange),
                        .times,
                        Expression(type: .identifier("c"), range: cRange)
                    ), range: tupleRange.lowerBound ..< input.endIndex)
                ),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testCommandVsOperatorPrecedence2() {
        let input = "print (a + b) c"
        let printRange = input.range(of: "print")!
        let tupleRange = input.range(of: "(a + b)")!
        let aRange = input.range(of: "a")!
        let bRange = input.range(of: "b")!
        let cRange = input.range(of: "c")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "print", range: printRange),
                    Expression(type: .tuple([
                        Expression(type: .tuple([
                            Expression(type: .infix(
                                Expression(type: .identifier("a"), range: aRange),
                                .plus,
                                Expression(type: .identifier("b"), range: bRange)
                            ), range: aRange.lowerBound ..< bRange.upperBound),
                        ]), range: tupleRange),
                        Expression(type: .identifier("c"), range: cRange),
                    ]), range: tupleRange.lowerBound ..< input.endIndex)
                ),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testCommandVsOperatorPrecedence3() {
        let input = "point (a + b) c"
        let pointRange = input.range(of: "point")!
        let tupleRange = input.range(of: "(a + b)")!
        let aRange = input.range(of: "a")!
        let bRange = input.range(of: "b")!
        let cRange = input.range(of: "c")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(
                    Identifier(name: "point", range: pointRange),
                    Expression(type: .tuple([
                        Expression(type: .tuple([
                            Expression(type: .infix(
                                Expression(type: .identifier("a"), range: aRange),
                                .plus,
                                Expression(type: .identifier("b"), range: bRange)
                            ), range: aRange.lowerBound ..< bRange.upperBound),
                        ]), range: tupleRange),
                        Expression(type: .identifier("c"), range: cRange),
                    ]), range: tupleRange.lowerBound ..< input.endIndex)
                ),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testFunctionVsOperatorPrecedence() {
        let input = "floor(a + b) * c"
        let floorRange = input.range(of: "floor")!
        let tupleRange = input.range(of: "(a + b)")!
        let aRange = input.range(of: "a")!
        let bRange = input.range(of: "b")!
        let cRange = input.range(of: "c")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .expression(Expression(type: .infix(
                    Expression(type: .tuple([
                        Expression(type: .identifier("floor"), range: floorRange),
                        Expression(type: .infix(
                            Expression(type: .identifier("a"), range: aRange),
                            .plus,
                            Expression(type: .identifier("b"), range: bRange)
                        ), range: aRange.lowerBound ..< bRange.upperBound),
                    ]), range: floorRange.lowerBound ..< tupleRange.upperBound),
                    .times,
                    Expression(type: .identifier("c"), range: cRange)
                ), range: input.startIndex ..< input.endIndex)),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    // NOTE: this should be treated as a command, but because of parsing
    // limitations gets interpreted as a tuple and must be disambiguated later
    func testLengthOptionTreatedAsTupleExpression() {
        let input = "foo { length 40 }"
        let fooRange = input.range(of: "foo")!
        let lengthRange = input.range(of: "length")!
        let numberRange = input.range(of: "40")!
        let bodyRange = input.range(of: "{ length 40 }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(
                Expression(
                    type: .block(
                        Identifier(name: "foo", range: fooRange),
                        Block(statements: [
                            Statement(
                                type: .expression(Expression(
                                    type: .tuple([
                                        Expression(type: .identifier("length"), range: lengthRange),
                                        Expression(type: .number(40), range: numberRange),
                                    ]),
                                    range: lengthRange.lowerBound ..< numberRange.upperBound
                                )),
                                range: lengthRange.lowerBound ..< numberRange.upperBound
                            ),
                        ], range: bodyRange)
                    ),
                    range: fooRange.lowerBound ..< bodyRange.upperBound
                )
            ), range: fooRange.lowerBound ..< bodyRange.upperBound),
        ]))
    }

    // MARK: Parentheses

    func testMultilineParentheses() {
        let input = """
        define matrix (
            (1 2 3)
            (4 5 6)
            (7 8 9)
        )
        """
        XCTAssertNoThrow(try parse(input))
    }

    func testEmptyTuple() {
        let input = "define void ()"
        XCTAssertNoThrow(try parse(input))
    }

    func testEmptyCommandArguments() {
        let input = "foo()"
        let fooRange = input.range(of: "foo")!
        let parensRange = input.range(of: "()")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .command(
                Identifier(name: "foo", range: fooRange),
                Expression(type: .tuple([]), range: parensRange)
            ), range: fooRange.lowerBound ..< parensRange.upperBound),
        ]))
    }

    func testEmptyFunctionArguments() {
        let input = "print bar()"
        let printRange = input.range(of: "print")!
        let barRange = input.range(of: "bar")!
        let parensRange = input.range(of: "()")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .command(
                Identifier(name: "print", range: printRange),
                Expression(type: .tuple([
                    Expression(type: .identifier("bar"), range: barRange),
                ]), range: barRange.lowerBound ..< parensRange.upperBound)
            ), range: printRange.lowerBound ..< parensRange.upperBound),
        ]))
    }

    func testUnterminatedParenthesis() {
        let input = "define foo (1 2 3"
        let range = input.endIndex ..< input.endIndex
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected closing paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: range),
                expected: "closing paren"
            )))
        }
    }

    func testUnterminatedParenthesisFollowedByForOnSameLine() {
        let input = "define foo ( for 1 to 10 {}"
        let range = input.range(of: "for")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
            XCTAssertEqual(error?.hint, "Expected expression.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .keyword(.for), range: range),
                expected: "expression"
            )))
        }
    }

    func testUnterminatedParenthesisFollowedByForOnNextLine() {
        let input = """
        define foo (1 2 3
        for i in foo {}
        """
        let range = input.range(of: "for")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
            XCTAssertEqual(error?.hint, "Expected closing paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .keyword(.for), range: range),
                expected: "closing paren"
            )))
        }
    }

    func testUnterminatedMultilineParenthesisFollowedByForOnNextLine() {
        let input = """
        define foo (
            1 2 3
            4 5 6
        for i in foo {}
        """
        let range = input.range(of: "for")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
            XCTAssertEqual(error?.hint, "Expected closing paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .keyword(.for), range: range),
                expected: "closing paren"
            )))
        }
    }

    func testUnterminatedMultilineParenthesisFollowedByBlock() {
        let input = """
        define foo (
            1 2 3
            4 5 6
        cube {
            size 1
        }
        """
        let range = input.endIndex ..< input.endIndex
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected closing paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: range),
                expected: "closing paren"
            )))
        }
    }

    // MARK: Ranges

    func testRange() {
        let input = "define foo 1 to 2"
        let defineRange = input.range(of: "define")!
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .infix(
                            Expression(type: .number(1), range: range1),
                            .to,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: range1.lowerBound ..< range2.upperBound
                    )))
                ),
                range: defineRange.lowerBound ..< range2.upperBound
            ),
        ]))
    }

    func testRangeWithStep() {
        let input = "define foo 1 to 5 step 2"
        let defineRange = input.range(of: "define")!
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "5")!
        let range3 = input.range(of: "2")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .to,
                                    Expression(type: .number(5), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .step,
                            Expression(type: .number(2), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )))
                ),
                range: defineRange.lowerBound ..< range3.upperBound
            ),
        ]))
    }

    func testRangeWithMissingUpperBound() {
        let input = "define foo 1 to"
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected end value.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: input.endIndex ..< input.endIndex),
                expected: "end value"
            )))
        }
    }

    func testRangeWithMultipleStepValues() {
        let input = "define range 1 to 5 step 1 step 2"
        let range = input.range(of: "step", range: input.range(of: "step 2")!)!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'step'")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("step"), range: range),
                expected: nil
            )))
        }
    }

    // MARK: Expression statement

    func testLiteralExpressionStatement() {
        let input = "1 + 2"
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(Expression(type: .infix(
                Expression(type: .number(1), range: range1),
                .plus,
                Expression(type: .number(2), range: range2)
            ), range: range)), range: range),
        ]))
    }

    func testIdentifierExpressionStatement() {
        let input = "foo + 2"
        let range1 = input.range(of: "foo")!
        let range2 = input.range(of: "2")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(Expression(type: .infix(
                Expression(type: .identifier("foo"), range: range1),
                .plus,
                Expression(type: .number(2), range: range2)
            ), range: range)), range: range),
        ]))
    }

    func testRangeExpressionStatement() {
        let input = "foo to 2"
        let range1 = input.range(of: "foo")!
        let range2 = input.range(of: "2")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(Expression(type: .infix(
                Expression(type: .identifier("foo"), range: range1),
                .to,
                Expression(type: .number(2), range: range2)
            ), range: range)), range: range),
        ]))
    }

    func testStepExpressionStatement() {
        let input = "foo step 2"
        let range1 = input.range(of: "foo")!
        let range2 = input.range(of: "2")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(Expression(type: .infix(
                Expression(type: .identifier("foo"), range: range1),
                .step,
                Expression(type: .number(2), range: range2)
            ), range: range)), range: range),
        ]))
    }

    func testNonStepExpressionStatement() {
        let input = "foo step"
        let range1 = input.range(of: "foo")!
        let range2 = input.range(of: "step")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .command(
                Identifier(name: "foo", range: range1),
                Expression(type: .identifier("step"), range: range2)
            ), range: range),
        ]))
    }

    func testAndExpressionStatement() {
        let input = "foo and true"
        let range1 = input.range(of: "foo")!
        let range2 = input.range(of: "true")!
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(Expression(type: .infix(
                Expression(type: .identifier("foo"), range: range1),
                .and,
                Expression(type: .identifier("true"), range: range2)
            ), range: range)), range: range),
        ]))
    }

    // MARK: For loops

    func testForLoopWithIndex() {
        let input = "for i in 1 to 2 {}"
        let forRange = input.range(of: "for")!
        let iRange = input.range(of: "i")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    Identifier(name: "i", range: iRange),
                    in: Expression(
                        type: .infix(
                            Expression(type: .number(1), range: range1),
                            .to,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: range1.lowerBound ..< range2.upperBound
                    ),
                    Block(statements: [], range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutIndex() {
        let input = "for 1 to 2 {}"
        let forRange = input.range(of: "for")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    nil,
                    in: Expression(
                        type: .infix(
                            Expression(type: .number(1), range: range1),
                            .to,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: range1.lowerBound ..< range2.upperBound
                    ),
                    Block(statements: [], range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutCondition() {
        let input = "for i in {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected range.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "range"
            )))
        }
    }

    func testForLoopWithInvalidIndex() {
        let input = "for 5 in {}"
        let inRange = input.range(of: "in")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'in'")
            XCTAssertEqual(error?.hint, "Expected loop body.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("in"), range: inRange),
                expected: "loop body"
            )))
        }
    }

    func testForLoopWithoutIndexOrCondition() {
        let input = "for {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected index or range.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "index or range"
            )))
        }
    }

    func testForLoopWithTupleWithoutParens() {
        let input = "for i in 3 1 4 1 5 { print i }"
        let range = input.range(of: "1")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected numeric literal")
            XCTAssertEqual(error?.hint, "Expected loop body.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .number(1), range: range),
                expected: "loop body"
            )))
        }
    }

    func testForLoopWithMissingClosingBrace() {
        let input = "for 1 to 10 {"
        let range = input.endIndex ..< input.endIndex
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected closing brace.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: range),
                expected: "closing brace"
            )))
        }
    }

    func testForLoopWithBlockExpression() {
        let input = "for i in cube { size 2 } { print i }"
        let range = input.range(of: "{", range: input.range(of: "{ print")!)!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertNil(error?.hint)
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: range),
                expected: nil
            )))
        }
    }

    // MARK: If/else

    func testIfStatement() {
        let input = "if foo {}"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: bodyRange),
                    else: nil
                ),
                range: ifRange.lowerBound ..< bodyRange.upperBound
            ),
        ]))
    }

    func testIfFollowedByAnotherIf() {
        let input = """
        if foo {}
        if bar { }
        """
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let if2Range = input.range(of: "if", range: input.range(of: "if bar")!)!
        let barRange = input.range(of: "bar")!
        let body2Range = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: bodyRange),
                    else: nil
                ),
                range: ifRange.lowerBound ..< bodyRange.upperBound
            ),
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("bar"), range: barRange),
                    Block(statements: [], range: body2Range),
                    else: nil
                ),
                range: if2Range.lowerBound ..< body2Range.upperBound
            ),
        ]))
    }

    func testIfElseStatement() {
        let input = "if foo {} else { }"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let elseBodyRange = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: bodyRange),
                    else: Block(statements: [], range: elseBodyRange)
                ),
                range: ifRange.lowerBound ..< elseBodyRange.upperBound
            ),
        ]))
    }

    func testIfElseIfStatement() {
        let input = "if foo {} else if bar { }"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let elseBodyRange = input.range(of: "if bar { }")!
        let if2Range = input.range(of: "if", range: elseBodyRange)!
        let barRange = input.range(of: "bar")!
        let body2Range = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: bodyRange),
                    else: Block(statements: [
                        Statement(
                            type: .ifelse(
                                Expression(type: .identifier("bar"), range: barRange),
                                Block(statements: [], range: body2Range),
                                else: nil
                            ),
                            range: if2Range.lowerBound ..< body2Range.upperBound
                        ),
                    ], range: elseBodyRange)
                ),
                range: ifRange.lowerBound ..< body2Range.upperBound
            ),
        ]))
    }

    func testIfWithElseOnNewLine() {
        let input = """
        if foo {}
        else { }
        """
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let elseBodyRange = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: bodyRange),
                    else: Block(statements: [], range: elseBodyRange)
                ),
                range: ifRange.lowerBound ..< elseBodyRange.upperBound
            ),
        ]))
    }

    func testIfStatementWithoutCondition() {
        let input = "if {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected condition.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "condition"
            )))
        }
    }

    func testIfStatementWithoutElse() {
        let input = "if foo {} {}"
        let braceRange = input.range(of: "{", range: input.range(of: "} {")!)!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: nil
            )))
        }
    }

    func testIfWithMisspelledElse() {
        let input = "if foo {} els {}"
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'els'")
            XCTAssertEqual(error?.hint, "Did you mean 'else'?")
        }
    }

    func testIfStatementWithMisspelledOrOperator() {
        let input = "if foo nor bar {}"
        let norRange = input.range(of: "nor")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'nor'")
            XCTAssertEqual(error?.hint, "Did you mean 'or'?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("nor"), range: norRange),
                expected: "if body"
            )))
        }
    }

    func testIfStatementWithMisspelledAndOperator() {
        let input = "if foo AND bar {}"
        let norRange = input.range(of: "AND")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'AND'")
            XCTAssertEqual(error?.hint, "Did you mean 'and'?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("AND"), range: norRange),
                expected: "if body"
            )))
        }
    }

    // MARK: Switch/case

    func testEmptySwitch() {
        let input = """
        switch foo {
        }
        """
        let switchRange = input.range(of: "switch")!
        let fooRange = input.range(of: "foo")!
        let endBraceRange = input.range(of: "}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .switchcase(
                    Expression(type: .identifier("foo"), range: fooRange),
                    [],
                    else: nil
                ),
                range: switchRange.lowerBound ..< endBraceRange.upperBound
            ),
        ]))
    }

    func testCaseAfterElse() {
        let input = """
        switch 1 {
        else
            print "foo"
        case 1
            print "bar"
        }
        """
        let caseRange = input.range(of: "case")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.type, .unexpectedToken(
                Token(type: .identifier("case"), range: caseRange),
                expected: "closing brace"
            ))
            // TODO: Improve this error hint
            XCTAssertEqual(error?.hint, "Expected closing brace.")
        }
    }

    func testSwitchCaseWithoutPattern() {
        let input = """
        switch 1 {
        case
            print "foo"
        }
        """
        let caseRange = input.range(of: "case")!
        let eolRange = caseRange.upperBound ..< input.index(after: caseRange.upperBound)
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.type, .unexpectedToken(
                Token(type: .linebreak, range: eolRange),
                expected: "pattern"
            ))
        }
    }

    func testSwitchStatementOutsideCaseError() {
        let input = """
        switch 1 {
            print "foo"
        }
        """
        let printRange = input.range(of: "print")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            guard case .unexpectedToken(
                Token(type: .identifier("print"), range: printRange),
                expected: "case statement"
            ) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Blocks

    func testTupleInBlock() {
        let input = "text { 1 2 }"
        let textRange = input.range(of: "text")!
        let tupleRange = input.range(of: "1 2")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let bodyRange = input.range(of: "{ 1 2 }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .expression(
                Expression(
                    type: .block(
                        Identifier(name: "text", range: textRange),
                        Block(statements: [
                            Statement(type: .expression(
                                Expression(type: .tuple([
                                    Expression(type: .number(1), range: range1),
                                    Expression(type: .number(2), range: range2),
                                ]),
                                range: tupleRange)
                            ), range: tupleRange),
                        ], range: bodyRange)
                    ),
                    range: textRange.lowerBound ..< bodyRange.upperBound
                )
            ), range: textRange.lowerBound ..< bodyRange.upperBound),
        ]))
    }

    // MARK: Functions

    func testFunctionDeclaration() {
        let input = "define foo(a b) { a + b }"
        let defineRange = input.range(of: "define")!
        let fooRange = input.range(of: "foo")!
        let aRange1 = input.range(of: "a")!
        let bRange1 = input.range(of: "b")!
        let bodyRange = input.range(of: "{ a + b }")!
        let sumRange = input.range(of: "a + b")!
        let aRange2 = input.range(of: "a", range: bodyRange)!
        let bRange2 = input.range(of: "b", range: bodyRange)!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .function([
                        Identifier(name: "a", range: aRange1),
                        Identifier(name: "b", range: bRange1),
                    ], Block(
                        statements: [
                            Statement(type: .expression(
                                Expression(type: .infix(
                                    Expression(type: .identifier("a"), range: aRange2),
                                    .plus,
                                    Expression(type: .identifier("b"), range: bRange2)
                                ),
                                range: sumRange)
                            ), range: sumRange),
                        ],
                        range: bodyRange
                    )))
                ),
                range: defineRange.lowerBound ..< bodyRange.upperBound
            ),
        ]))
    }

    // MARK: Comments

    func testBlockCommentDoesntMessUpLineCalculation() {
        let input = """
        /*
            a comment
        */
        if foo AND bar {
            print foo
        }
        """
        XCTAssertThrowsError(try parse(input)) { error in
            guard let error = try? XCTUnwrap(error as? ParserError),
                  let range = error.range?.lowerBound
            else {
                return
            }
            XCTAssertEqual(error.message, "Unexpected token 'AND'")
            XCTAssertEqual(input.line(at: range), 4)
        }
    }
}
