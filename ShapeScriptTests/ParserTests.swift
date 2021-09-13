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
                        type: .range(
                            from: Expression(type: .number(1), range: range1),
                            to: Expression(type: .number(2), range: range2),
                            step: nil
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
                        type: .range(
                            from: Expression(type: .number(1), range: range1),
                            to: Expression(type: .number(5), range: range2),
                            step: Expression(type: .number(2), range: range3)
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

    func testRangeWithMissingStepValue() {
        let input = "define foo 1 to 5 step"
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected end of file")
            XCTAssertEqual(error?.hint, "Expected step value.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .eof, range: input.endIndex ..< input.endIndex),
                expected: "step value"
            )))
        }
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
                        type: .range(
                            from: Expression(type: .number(1), range: range1),
                            to: Expression(type: .number(2), range: range2),
                            step: nil
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
                        type: .range(
                            from: Expression(type: .number(1), range: range1),
                            to: Expression(type: .number(2), range: range2),
                            step: nil
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
            XCTAssertEqual(error?.message, "Unexpected identifier 'in'")
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
            XCTAssertEqual(error?.hint, "Expected range.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "range"
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
}
