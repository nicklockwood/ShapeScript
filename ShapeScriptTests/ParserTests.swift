//
//  ParserTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 07/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

final class ParserTests: XCTestCase {
    // MARK: Operators

    func testLeftAssociativity() throws {
        let input = "print 1 - 2 + 3"
        let printRange = try XCTUnwrap(input.range(of: "print"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range3 = try XCTUnwrap(input.range(of: "3"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testOperatorPrecedence() throws {
        let input = "color 1 * 2 + 3"
        let colorRange = try XCTUnwrap(input.range(of: "color"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range3 = try XCTUnwrap(input.range(of: "3"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testOperatorPrecedence2() throws {
        let input = "color 1 / 2 * 3"
        let colorRange = try XCTUnwrap(input.range(of: "color"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range3 = try XCTUnwrap(input.range(of: "3"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testNotOperatorPrecedence() throws {
        let input = "not a = b"
        let notRange = try XCTUnwrap(input.range(of: "not"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .expression(.tuple([
                    Expression(type: .identifier("not"), range: notRange),
                    Expression(
                        type: .infix(
                            Expression(type: .identifier("a"), range: aRange),
                            .equal,
                            Expression(type: .identifier("b"), range: bRange)
                        ),
                        range: aRange.lowerBound ..< input.endIndex
                    ),
                ])),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testNotOperatorPrecedence2() throws {
        let input = "not a = not b"
        let notRange = try XCTUnwrap(input.range(of: "not"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let notRange2 = try XCTUnwrap(input.range(of: "not", range: XCTUnwrap(input.range(of: "not b"))))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .expression(.tuple([
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
                ])),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    func testPrintNot() throws {
        let input = "print not"
        let printRange = try XCTUnwrap(input.range(of: "print"))
        let notRange = try XCTUnwrap(input.range(of: "not"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testInfixExpressionSplitOverTwoLines() throws {
        let input = """
        define foo 1 +
            bar
        """
        let range = try XCTUnwrap(input.range(of: "\n"))
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

    func testComparisonOperatorChaining() throws {
        let input = "print 1 < 2 < 3"
        let range = try XCTUnwrap(input.range(of: "<", range: XCTUnwrap(input.range(of: "< 3"))))
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected operator '<'")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .infix(.lt), range: range),
                expected: nil
            )))
        }
    }

    func testEqualityOperatorChaining() throws {
        let input = "print 1 = 2 = 3"
        let range = try XCTUnwrap(input.range(of: "=", range: XCTUnwrap(input.range(of: "= 3"))))
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected operator '='")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .infix(.equal), range: range),
                expected: nil
            )))
        }
    }

    func testCommandVsOperatorPrecedence() throws {
        let input = "print (a + b) * c"
        let printRange = try XCTUnwrap(input.range(of: "print"))
        let tupleRange = try XCTUnwrap(input.range(of: "(a + b)"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        let cRange = try XCTUnwrap(input.range(of: "c"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testCommandVsOperatorPrecedence2() throws {
        let input = "print (a + b) c"
        let printRange = try XCTUnwrap(input.range(of: "print"))
        let tupleRange = try XCTUnwrap(input.range(of: "(a + b)"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        let cRange = try XCTUnwrap(input.range(of: "c"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testCommandVsOperatorPrecedence3() throws {
        let input = "point (a + b) c"
        let pointRange = try XCTUnwrap(input.range(of: "point"))
        let tupleRange = try XCTUnwrap(input.range(of: "(a + b)"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        let cRange = try XCTUnwrap(input.range(of: "c"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testFunctionVsOperatorPrecedence() throws {
        let input = "floor(a + b) * c"
        let floorRange = try XCTUnwrap(input.range(of: "floor"))
        let tupleRange = try XCTUnwrap(input.range(of: "(a + b)"))
        let aRange = try XCTUnwrap(input.range(of: "a"))
        let bRange = try XCTUnwrap(input.range(of: "b"))
        let cRange = try XCTUnwrap(input.range(of: "c"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .expression(.infix(
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
                )),
                range: input.startIndex ..< input.endIndex
            ),
        ]))
    }

    /// NOTE: this should be treated as a command, but because of parsing
    /// limitations gets interpreted as a tuple and must be disambiguated later
    func testLengthOptionTreatedAsTupleExpression() throws {
        let input = "foo { length 40 }"
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let lengthRange = try XCTUnwrap(input.range(of: "length"))
        let numberRange = try XCTUnwrap(input.range(of: "40"))
        let bodyRange = try XCTUnwrap(input.range(of: "{ length 40 }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.block(
                Identifier(name: "foo", range: fooRange),
                Block(statements: [
                    Statement(
                        type: .expression(.tuple([
                            Expression(type: .identifier("length"), range: lengthRange),
                            Expression(type: .number(40), range: numberRange),
                        ])),
                        range: lengthRange.lowerBound ..< numberRange.upperBound
                    ),
                ], range: bodyRange)
            )), range: fooRange.lowerBound ..< bodyRange.upperBound),
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

    func testEmptyCommandArguments() throws {
        let input = "foo()"
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let parensRange = try XCTUnwrap(input.range(of: "()"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .command(
                Identifier(name: "foo", range: fooRange),
                Expression(type: .tuple([]), range: parensRange)
            ), range: fooRange.lowerBound ..< parensRange.upperBound),
        ]))
    }

    func testEmptyFunctionArguments() throws {
        let input = "print bar()"
        let printRange = try XCTUnwrap(input.range(of: "print"))
        let barRange = try XCTUnwrap(input.range(of: "bar"))
        let parensRange = try XCTUnwrap(input.range(of: "()"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testUnterminatedParenthesisFollowedByForOnSameLine() throws {
        let input = "define foo ( for 1 to 10 {}"
        let range = try XCTUnwrap(input.range(of: "for"))
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

    func testUnterminatedParenthesisFollowedByForOnNextLine() throws {
        let input = """
        define foo (1 2 3
        for i in foo {}
        """
        let range = try XCTUnwrap(input.range(of: "for"))
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

    func testUnterminatedMultilineParenthesisFollowedByForOnNextLine() throws {
        let input = """
        define foo (
            1 2 3
            4 5 6
        for i in foo {}
        """
        let range = try XCTUnwrap(input.range(of: "for"))
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

    func testRange() throws {
        let input = "define foo 1 to 2"
        let defineRange = try XCTUnwrap(input.range(of: "define"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testRangeWithStep() throws {
        let input = "define foo 1 to 5 step 2"
        let defineRange = try XCTUnwrap(input.range(of: "define"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "5"))
        let range3 = try XCTUnwrap(input.range(of: "2"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testRangeWithMultipleStepValues() throws {
        let input = "define range 1 to 5 step 1 step 2"
        let range = try XCTUnwrap(input.range(of: "step", range: XCTUnwrap(input.range(of: "step 2"))))
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

    func testLiteralExpressionStatement() throws {
        let input = "1 + 2"
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.infix(
                Expression(type: .number(1), range: range1),
                .plus,
                Expression(type: .number(2), range: range2)
            )), range: range),
        ]))
    }

    func testIdentifierExpressionStatement() throws {
        let input = "foo + 2"
        let range1 = try XCTUnwrap(input.range(of: "foo"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.infix(
                Expression(type: .identifier("foo"), range: range1),
                .plus,
                Expression(type: .number(2), range: range2)
            )), range: range),
        ]))
    }

    func testRangeExpressionStatement() throws {
        let input = "foo to 2"
        let range1 = try XCTUnwrap(input.range(of: "foo"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.infix(
                Expression(type: .identifier("foo"), range: range1),
                .to,
                Expression(type: .number(2), range: range2)
            )), range: range),
        ]))
    }

    func testStepExpressionStatement() throws {
        let input = "foo step 2"
        let range1 = try XCTUnwrap(input.range(of: "foo"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.infix(
                Expression(type: .identifier("foo"), range: range1),
                .step,
                Expression(type: .number(2), range: range2)
            )), range: range),
        ]))
    }

    func testNonStepExpressionStatement() throws {
        let input = "foo step"
        let range1 = try XCTUnwrap(input.range(of: "foo"))
        let range2 = try XCTUnwrap(input.range(of: "step"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .command(
                Identifier(name: "foo", range: range1),
                Expression(type: .identifier("step"), range: range2)
            ), range: range),
        ]))
    }

    func testAndExpressionStatement() throws {
        let input = "foo and true"
        let range1 = try XCTUnwrap(input.range(of: "foo"))
        let range2 = try XCTUnwrap(input.range(of: "true"))
        let range = range1.lowerBound ..< range2.upperBound
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.infix(
                Expression(type: .identifier("foo"), range: range1),
                .and,
                Expression(type: .identifier("true"), range: range2)
            )), range: range),
        ]))
    }

    // MARK: For loops

    func testForLoopWithIndex() throws {
        let input = "for i in 1 to 2 {}"
        let forRange = try XCTUnwrap(input.range(of: "for"))
        let iRange = try XCTUnwrap(input.range(of: "i"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let blockRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testForLoopWithoutIndex() throws {
        let input = "for 1 to 2 {}"
        let forRange = try XCTUnwrap(input.range(of: "for"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let blockRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testForLoopWithParensAroundConditione() throws {
        let input = "for (i in foo) {}"
        let forRange = try XCTUnwrap(input.range(of: "for"))
        let iRange = try XCTUnwrap(input.range(of: "i"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let blockRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .forloop(
                    Identifier(name: "i", range: iRange),
                    in: Expression(type: .identifier("foo"), range: fooRange),
                    Block(statements: [], range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithParenthesizedTuple() throws {
        let input = "for (1 2 3) {}"
        let forRange = try XCTUnwrap(input.range(of: "for"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let range3 = try XCTUnwrap(input.range(of: "3"))
        let tupleRange = try XCTUnwrap(input.range(of: "(1 2 3)"))
        let blockRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .forloop(
                    nil,
                    in: Expression(type: .tuple([
                        Expression(type: .number(1), range: range1),
                        Expression(type: .number(2), range: range2),
                        Expression(type: .number(3), range: range3),
                    ]), range: tupleRange),
                    Block(statements: [], range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutCondition() throws {
        let input = "for i in {}"
        let braceRange = try XCTUnwrap(input.range(of: "{"))
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

    func testForLoopWithInvalidIndex() throws {
        let input = "for 5 in foo {}"
        let indexRange = try XCTUnwrap(input.range(of: "5"))
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected numeric literal")
            XCTAssertEqual(error?.hint, "Expected loop index.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .number(5), range: indexRange),
                expected: "loop index"
            )))
        }
    }

    func testForLoopWithoutIndexOrCondition() throws {
        let input = "for {}"
        let braceRange = try XCTUnwrap(input.range(of: "{"))
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

    func testForLoopWithTupleWithoutParens() throws {
        let input = "for i in 3 1 4 1 5 { print i }"
        let range = try XCTUnwrap(input.range(of: "1"))
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

    func testForLoopWithBlockExpression() throws {
        let input = "for i in cube { size 2 } { print i }"
        let range = try XCTUnwrap(input.range(of: "{", range: XCTUnwrap(input.range(of: "{ print"))))
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

    func testIfStatement() throws {
        let input = "if foo {}"
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testIfFollowedByAnotherIf() throws {
        let input = """
        if foo {}
        if bar { }
        """
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        let if2Range = try XCTUnwrap(input.range(of: "if", range: XCTUnwrap(input.range(of: "if bar"))))
        let barRange = try XCTUnwrap(input.range(of: "bar"))
        let body2Range = try XCTUnwrap(input.range(of: "{ }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testIfElseStatement() throws {
        let input = "if foo {} else { }"
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        let elseBodyRange = try XCTUnwrap(input.range(of: "{ }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testIfElseIfStatement() throws {
        let input = "if foo {} else if bar { }"
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        let elseBodyRange = try XCTUnwrap(input.range(of: "if bar { }"))
        let if2Range = try XCTUnwrap(input.range(of: "if", range: elseBodyRange))
        let barRange = try XCTUnwrap(input.range(of: "bar"))
        let body2Range = try XCTUnwrap(input.range(of: "{ }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testIfWithElseOnNewLine() throws {
        let input = """
        if foo {}
        else { }
        """
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        let elseBodyRange = try XCTUnwrap(input.range(of: "{ }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testIfStatementWithoutCondition() throws {
        let input = "if {}"
        let braceRange = try XCTUnwrap(input.range(of: "{"))
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

    func testIfStatementWithoutElse() throws {
        let input = "if foo {} {}"
        let braceRange = try XCTUnwrap(input.range(of: "{", range: XCTUnwrap(input.range(of: "} {"))))
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

    func testIfStatementWithMisspelledOrOperator() throws {
        let input = "if foo nor bar {}"
        let norRange = try XCTUnwrap(input.range(of: "nor"))
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

    func testIfStatementWithMisspelledAndOperator() throws {
        let input = "if foo AND bar {}"
        let norRange = try XCTUnwrap(input.range(of: "AND"))
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

    func testIfIn() throws {
        let input = "if foo in bar {}"
        let ifRange = try XCTUnwrap(input.range(of: "if"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let barRange = try XCTUnwrap(input.range(of: "bar"))
        let bodyRange = try XCTUnwrap(input.range(of: "{}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .infix(
                        Expression(type: .identifier("foo"), range: fooRange),
                        .in,
                        Expression(type: .identifier("bar"), range: barRange)
                    ), range: fooRange.lowerBound ..< barRange.upperBound),
                    Block(statements: [], range: bodyRange),
                    else: nil
                ),
                range: ifRange.lowerBound ..< bodyRange.upperBound
            ),
        ]))
    }

    // MARK: Switch/case

    func testEmptySwitch() throws {
        let input = """
        switch foo {
        }
        """
        let switchRange = try XCTUnwrap(input.range(of: "switch"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let endBraceRange = try XCTUnwrap(input.range(of: "}"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
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

    func testCaseAfterElse() throws {
        let input = """
        switch 1 {
        else
            print "foo"
        case 1
            print "bar"
        }
        """
        let caseRange = try XCTUnwrap(input.range(of: "case"))
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

    func testSwitchCaseWithoutPattern() throws {
        let input = """
        switch 1 {
        case
            print "foo"
        }
        """
        let caseRange = try XCTUnwrap(input.range(of: "case"))
        let eolRange = caseRange.upperBound ..< input.index(after: caseRange.upperBound)
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.type, .unexpectedToken(
                Token(type: .linebreak, range: eolRange),
                expected: "pattern"
            ))
        }
    }

    func testSwitchStatementOutsideCaseError() throws {
        let input = """
        switch 1 {
            print "foo"
        }
        """
        let printRange = try XCTUnwrap(input.range(of: "print"))
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

    func testSwitchStatementWithDefault() {
        let input = """
        switch 1 {
        default
            print "foo"
        }
        """
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.hint, "Did you mean 'else'?")
        }
    }

    // MARK: Blocks

    func testTupleInBlock() throws {
        let input = "text { 1 2 }"
        let textRange = try XCTUnwrap(input.range(of: "text"))
        let tupleRange = try XCTUnwrap(input.range(of: "1 2"))
        let range1 = try XCTUnwrap(input.range(of: "1"))
        let range2 = try XCTUnwrap(input.range(of: "2"))
        let bodyRange = try XCTUnwrap(input.range(of: "{ 1 2 }"))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(type: .expression(.block(
                Identifier(name: "text", range: textRange),
                Block(statements: [
                    Statement(type: .expression(.tuple([
                        Expression(type: .number(1), range: range1),
                        Expression(type: .number(2), range: range2),
                    ])), range: tupleRange),
                ], range: bodyRange)
            )), range: textRange.lowerBound ..< bodyRange.upperBound),
        ]))
    }

    // MARK: Functions

    func testFunctionDeclaration() throws {
        let input = "define foo(a b) { a + b }"
        let defineRange = try XCTUnwrap(input.range(of: "define"))
        let fooRange = try XCTUnwrap(input.range(of: "foo"))
        let aRange1 = try XCTUnwrap(input.range(of: "a"))
        let bRange1 = try XCTUnwrap(input.range(of: "b"))
        let bodyRange = try XCTUnwrap(input.range(of: "{ a + b }"))
        let sumRange = try XCTUnwrap(input.range(of: "a + b"))
        let aRange2 = try XCTUnwrap(input.range(of: "a", range: bodyRange))
        let bRange2 = try XCTUnwrap(input.range(of: "b", range: bodyRange))
        XCTAssertEqual(try parse(input), Program(source: input, fileURL: nil, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .function([
                        Identifier(name: "a", range: aRange1),
                        Identifier(name: "b", range: bRange1),
                    ], Block(statements: [
                        Statement(type: .expression(.infix(
                            Expression(type: .identifier("a"), range: aRange2),
                            .plus,
                            Expression(type: .identifier("b"), range: bRange2)
                        )), range: sumRange),
                    ], range: bodyRange)))
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
