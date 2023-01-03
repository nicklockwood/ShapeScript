//
//  ParserTests.swift
//  SCADLibTests
//
//  Created by Nick Lockwood on 03/01/2023.
//

@testable import SCADLib
import XCTest

class ParserTests: XCTestCase {
    // MARK: Operators

    func testLeftAssociativity() {
        let input = "foo = 1 - 2 + 3;"
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
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
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testOperatorPrecedence() {
        let input = "foo = 1 * 2 + 3;"
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
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
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testOperatorPrecedence2() {
        let input = "foo = 1 / 2 * 3;"
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
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
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testUnterminatedInfixExpression() {
        let input = "foo = 1 +"
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
        foo = 1 +
            bar;
        """
        XCTAssertNoThrow(try parse(input))
    }

    func testComparisonOperatorChaining() {
        let input = "foo = 1 < 2 < 3;"
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .lt,
                                    Expression(type: .number(2), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .lt,
                            Expression(type: .number(3), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testEqualityOperatorChaining() {
        let input = "foo = 1 == 2 == false;"
        let fooRange = input.range(of: "foo")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "false")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .infix(
                            Expression(
                                type: .infix(
                                    Expression(type: .number(1), range: range1),
                                    .equal,
                                    Expression(type: .number(2), range: range2)
                                ),
                                range: range1.lowerBound ..< range2.upperBound
                            ),
                            .equal,
                            Expression(type: .boolean(false), range: range3)
                        ),
                        range: range1.lowerBound ..< range3.upperBound
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    // MARK: Parentheses

    func testParenthesizedExpression() {
        let input = "foo = (1 + 2);"
        let fooRange = input.range(of: "foo")!
        let expressionRange = input.range(of: "(1 + 2)")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .infix(
                            Expression(type: .number(1), range: range1),
                            .plus,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: expressionRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testTuple() {
        let input = "foo = (1, 2);"
        let commaRange = input.range(of: ",")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected comma")
            XCTAssertEqual(error?.hint, "Expected closing paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .comma, range: commaRange),
                expected: "closing paren"
            )))
        }
    }

    func testEmptyTuple() {
        let input = "foo = ();"
        let parenRange = input.range(of: ")")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing paren")
            XCTAssertEqual(error?.hint, "Expected expression.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rparen, range: parenRange),
                expected: "expression"
            )))
        }
    }

    // MARK: Commands

    func testEmptyCommandArguments() {
        let input = "foo();"
        let fooRange = input.range(of: "foo")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .command(Identifier(name: "foo", range: fooRange), []),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    // MARK: Functions

    func testEmptyFunctionArguments() {
        let input = "foo = bar();"
        let fooRange = input.range(of: "foo")!
        let barRange = input.range(of: "bar")!
        let parensRange = input.range(of: "()")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(type: .define(
                Identifier(name: "foo", range: fooRange),
                Definition(type: .expression(Expression(type: .call(
                    Expression(type: .identifier("bar"), range: barRange), []
                ), range: barRange.lowerBound ..< parensRange.upperBound)))
            ), range: fooRange.lowerBound ..< input.endIndex),
        ]))
    }

//    func testUnterminatedParenthesis() {
//        let input = "define foo (1 2 3"
//        let range = input.endIndex ..< input.endIndex
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected end of file")
//            XCTAssertEqual(error?.hint, "Expected closing paren.")
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .eof, range: range),
//                expected: "closing paren"
//            )))
//        }
//    }
//
//    func testUnterminatedParenthesisFollowedByForOnSameLine() {
//        let input = "define foo ( for 1 to 10 {}"
//        let range = input.range(of: "for")!
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
//            XCTAssertEqual(error?.hint, "Expected expression.")
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .keyword(.for), range: range),
//                expected: "expression"
//            )))
//        }
//    }
//
//    func testUnterminatedParenthesisFollowedByForOnNextLine() {
//        let input = """
//        define foo (1 2 3
//        for i in foo {}
//        """
//        let range = input.range(of: "for")!
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
//            XCTAssertEqual(error?.hint, "Expected closing paren.")
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .keyword(.for), range: range),
//                expected: "closing paren"
//            )))
//        }
//    }
//
//    func testUnterminatedMultilineParenthesisFollowedByForOnNextLine() {
//        let input = """
//        define foo (
//            1 2 3
//            4 5 6
//        for i in foo {}
//        """
//        let range = input.range(of: "for")!
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected keyword 'for'")
//            XCTAssertEqual(error?.hint, "Expected closing paren.")
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .keyword(.for), range: range),
//                expected: "closing paren"
//            )))
//        }
//    }
//
//    func testUnterminatedMultilineParenthesisFollowedByBlock() {
//        let input = """
//        define foo (
//            1 2 3
//            4 5 6
//        cube {
//            size 1
//        }
//        """
//        let range = input.endIndex ..< input.endIndex
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected end of file")
//            XCTAssertEqual(error?.hint, "Expected closing paren.")
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .eof, range: range),
//                expected: "closing paren"
//            )))
//        }
//    }

    // MARK: Ranges

    func testRange() {
        let input = "foo = [1:2];"
        let fooRange = input.range(of: "foo")!
        let rangeRange = input.range(of: "[1:2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .range(
                            Expression(type: .number(1), range: range1),
                            nil,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: rangeRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testRangeWithStep() {
        let input = "foo = [1:2:5];"
        let fooRange = input.range(of: "foo")!
        let rangeRange = input.range(of: "[1:2:5]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "5")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .range(
                            Expression(type: .number(1), range: range1),
                            Expression(type: .number(2), range: range2),
                            Expression(type: .number(5), range: range3)
                        ),
                        range: rangeRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testRangeWithMissingIncrementOrUpperBound() {
        let input = "foo = [1:];"
        let bracketRange = input.range(of: "]")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing bracket")
            XCTAssertEqual(error?.hint, "Expected upper bound or increment.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rbracket, range: bracketRange),
                expected: "upper bound or increment"
            )))
        }
    }

    func testRangeWithMissingUpperBound() {
        let input = "foo = [1:2:];"
        let bracketRange = input.range(of: "]")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing bracket")
            XCTAssertEqual(error?.hint, "Expected upper bound.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rbracket, range: bracketRange),
                expected: "upper bound"
            )))
        }
    }

    func testRangeWithMissingIncrement() {
        let input = "foo = [1::2];"
        let range = input.range(of: "::")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.message, "Unexpected token '::'")
            XCTAssertEqual(error, LexerError(.unexpectedToken("::"), at: range))
        }
    }

    func testRangeWithTooManyValues() {
        let input = "foo = [1:2:3:4];"
        let range = input.range(of: ":", range: input.range(of: ":4"))!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected colon")
            XCTAssertEqual(error?.hint, "Expected closing bracket.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .colon, range: range),
                expected: "closing bracket"
            )))
        }
    }

    // MARK: Vectors

    func testVector() {
        let input = "foo = [1,2];"
        let fooRange = input.range(of: "foo")!
        let vectorRange = input.range(of: "[1,2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .vector([
                            Expression(type: .number(1), range: range1),
                            Expression(type: .number(2), range: range2),
                        ]),
                        range: vectorRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testVectorWithOneElement() {
        let input = "foo = [1];"
        let fooRange = input.range(of: "foo")!
        let vectorRange = input.range(of: "[1]")!
        let range1 = input.range(of: "1")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .vector([
                            Expression(type: .number(1), range: range1),
                        ]),
                        range: vectorRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testEmptyVector() {
        let input = "foo = [];"
        let fooRange = input.range(of: "foo")!
        let vectorRange = input.range(of: "[]")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .vector([]),
                        range: vectorRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testNestedVector() {
        let input = "foo = [[1,2],3];"
        let fooRange = input.range(of: "foo")!
        let outerRange = input.range(of: "[[1,2],3]")!
        let innerRange = input.range(of: "[1,2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .vector([
                            Expression(type: .vector([
                                Expression(type: .number(1), range: range1),
                                Expression(type: .number(2), range: range2),
                            ]), range: innerRange),
                            Expression(type: .number(3), range: range3),
                        ]),
                        range: outerRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testNestedVector2() {
        let input = "foo = [1,[2,3]];"
        let fooRange = input.range(of: "foo")!
        let outerRange = input.range(of: "[1,[2,3]]")!
        let innerRange = input.range(of: "[2,3]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let range3 = input.range(of: "3")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .expression(Expression(
                        type: .vector([
                            Expression(type: .number(1), range: range1),
                            Expression(type: .vector([
                                Expression(type: .number(2), range: range2),
                                Expression(type: .number(3), range: range3),
                            ]), range: innerRange),
                        ]),
                        range: outerRange
                    )))
                ),
                range: fooRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    // MARK: For loops

    func testForLoopWithRange() {
        let input = "for (i = [1:2]) {}"
        let forRange = input.range(of: "for")!
        let iRange = input.range(of: "i")!
        let rangeRange = input.range(of: "[1:2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    Identifier(name: "i", range: iRange),
                    in: Expression(
                        type: .range(
                            Expression(type: .number(1), range: range1),
                            nil,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: rangeRange
                    ),
                    Statement(type: .block([]), range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithVector() {
        let input = "for (i = [1,2]) {}"
        let forRange = input.range(of: "for")!
        let iRange = input.range(of: "i")!
        let vectorRange = input.range(of: "[1,2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    Identifier(name: "i", range: iRange),
                    in: Expression(
                        type: .vector([
                            Expression(type: .number(1), range: range1),
                            Expression(type: .number(2), range: range2),
                        ]),
                        range: vectorRange
                    ),
                    Statement(type: .block([]), range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithIdentifier() {
        let input = "for (i = foo) {}"
        let forRange = input.range(of: "for")!
        let iRange = input.range(of: "i")!
        let fooRange = input.range(of: "foo")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    Identifier(name: "i", range: iRange),
                    in: Expression(type: .identifier("foo"), range: fooRange),
                    Statement(type: .block([]), range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutIndex() {
        let input = "for ([1:2]) {}"
        let forRange = input.range(of: "for")!
        let rangeRange = input.range(of: "[1:2]")!
        let range1 = input.range(of: "1")!
        let range2 = input.range(of: "2")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    nil,
                    in: Expression(
                        type: .range(
                            Expression(type: .number(1), range: range1),
                            nil,
                            Expression(type: .number(2), range: range2)
                        ),
                        range: rangeRange
                    ),
                    Statement(type: .block([]), range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutCondition() {
        let input = "for (i) {}"
        let parenRange = input.range(of: ")")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing paren")
            XCTAssertEqual(error?.hint, "Expected assignment operator.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rparen, range: parenRange),
                expected: "assignment operator"
            )))
        }
    }

    func testForLoopWithoutCondition2() {
        let input = "for (i =) {}"
        let parenRange = input.range(of: ")")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing paren")
            XCTAssertEqual(error?.hint, "Expected range expression.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rparen, range: parenRange),
                expected: "range expression"
            )))
        }
    }

    func testForLoopWithInvalidIndex() {
        let input = "for (5 = [1]) {}"
        let assignRange = input.range(of: "=")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected assignment operator")
            XCTAssertEqual(error?.hint, "Did you mean '=='?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .assign, range: assignRange),
                expected: "closing paren"
            )))
        }
    }

    func testForLoopWithoutIndexOrCondition() {
        let input = "for () {}"
        let forRange = input.range(of: "for")!
        let parenRange = input.range(of: ")")!
        let blockRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .forloop(
                    nil,
                    in: Expression(
                        type: .undefined,
                        range: parenRange.lowerBound ..< parenRange.lowerBound
                    ),
                    Statement(type: .block([]), range: blockRange)
                ),
                range: forRange.lowerBound ..< blockRange.upperBound
            ),
        ]))
    }

    func testForLoopWithoutParensOrCondition() {
        let input = "for {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected opening paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "opening paren"
            )))
        }
    }

    func testForLoopWithMissingClosingBrace() {
        let input = "for (i=[1:10]) {"
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

//    func testForLoopWithBlockExpression() {
//        let input = "for i in cube { size 2 } { print i }"
//        let range = input.range(of: "{", range: input.range(of: "{ print")!)!
//        XCTAssertThrowsError(try parse(input)) { error in
//            let error = try? XCTUnwrap(error as? ParserError)
//            XCTAssertEqual(error?.message, "Unexpected opening brace")
//            XCTAssertNil(error?.hint)
//            XCTAssertEqual(error, ParserError(.unexpectedToken(
//                Token(type: .lbrace, range: range),
//                expected: nil
//            )))
//        }
//    }

    // MARK: If/else

    func testIfStatement() {
        let input = "if (foo) {}"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Statement(type: .block([]), range: bodyRange),
                    else: nil
                ),
                range: ifRange.lowerBound ..< bodyRange.upperBound
            ),
        ]))
    }

    func testIfFollowedByAnotherIf() {
        let input = """
        if (foo) {}
        if( bar ) { }
        """
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let if2Range = input.range(of: "if", range: input.range(of: "if(")!)!
        let barRange = input.range(of: "bar")!
        let body2Range = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Statement(type: .block([]), range: bodyRange),
                    else: nil
                ),
                range: ifRange.lowerBound ..< bodyRange.upperBound
            ),
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("bar"), range: barRange),
                    Statement(type: .block([]), range: body2Range),
                    else: nil
                ),
                range: if2Range.lowerBound ..< body2Range.upperBound
            ),
        ]))
    }

    func testIfElseStatement() {
        let input = "if (foo) {} else { }"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let elseBodyRange = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Statement(type: .block([]), range: bodyRange),
                    else: Statement(type: .block([]), range: elseBodyRange)
                ),
                range: ifRange.lowerBound ..< elseBodyRange.upperBound
            ),
        ]))
    }

    func testIfElseIfStatement() {
        let input = "if (foo) {} else if (bar ) { }"
        let ifRange = input.range(of: "if")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "{}")!
        let elseBodyRange = input.range(of: "if (bar ) { }")!
        let barRange = input.range(of: "bar")!
        let body2Range = input.range(of: "{ }")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .ifelse(
                    Expression(type: .identifier("foo"), range: fooRange),
                    Statement(type: .block([]), range: bodyRange),
                    else: Statement(type: .ifelse(
                        Expression(type: .identifier("bar"), range: barRange),
                        Statement(type: .block([]), range: body2Range),
                        else: nil
                    ), range: elseBodyRange)
                ),
                range: ifRange.lowerBound ..< body2Range.upperBound
            ),
        ]))
    }

    func testIfWithElseOnNewLine() {
        let input = """
        if ( foo) {}
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
                    Statement(type: .block([]), range: bodyRange),
                    else: Statement(type: .block([]), range: elseBodyRange)
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
            XCTAssertEqual(error?.hint, "Expected opening paren.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "opening paren"
            )))
        }
    }

    func testIfStatementWithEmptyCondition() {
        let input = "if () {}"
        let parenRange = input.range(of: ")")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected closing paren")
            XCTAssertEqual(error?.hint, "Expected condition.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .rparen, range: parenRange),
                expected: "condition"
            )))
        }
    }

    func testIfStatementWithMisspelledOrOperator() {
        let input = "if (foo or bar) {}"
        let orRange = input.range(of: "or")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'or'")
            XCTAssertEqual(error?.hint, "Did you mean '||'?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("or"), range: orRange),
                expected: "closing paren"
            )))
        }
    }

    func testIfStatementWithMisspelledAndOperator() {
        let input = "if (foo AND bar) {}"
        let andRange = input.range(of: "AND")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected token 'AND'")
            XCTAssertEqual(error?.hint, "Did you mean '&&'?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("AND"), range: andRange),
                expected: "closing paren"
            )))
        }
    }

    func testIfStatementWithWrongEqualsOperator() {
        let input = "if (foo = bar) {}"
        let eqRange = input.range(of: "=")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected assignment operator")
            XCTAssertEqual(error?.hint, "Did you mean '=='?")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .assign, range: eqRange),
                expected: "closing paren"
            )))
        }
    }

    // MARK: Blocks

//    func testTupleInBlock() {
//        let input = "text { 1 2 }"
//        let textRange = input.range(of: "text")!
//        let tupleRange = input.range(of: "1 2")!
//        let range1 = input.range(of: "1")!
//        let range2 = input.range(of: "2")!
//        let bodyRange = input.range(of: "{ 1 2 }")!
//        XCTAssertEqual(try parse(input), Program(source: input, statements: [
//            Statement(type: .expression(
//                Expression(
//                    type: .block(
//                        Identifier(name: "text", range: textRange),
//                        Block(statements: [
//                            Statement(type: .expression(
//                                Expression(type: .tuple([
//                                    Expression(type: .number(1), range: range1),
//                                    Expression(type: .number(2), range: range2),
//                                ]),
//                                range: tupleRange)
//                            ), range: tupleRange),
//                        ], range: bodyRange)
//                    ),
//                    range: textRange.lowerBound ..< bodyRange.upperBound
//                )
//            ), range: textRange.lowerBound ..< bodyRange.upperBound),
//        ]))
//    }

    // MARK: Functions

    func testFunctionDeclaration() {
        let input = "function foo(a, b) = a + b;"
        let functionRange = input.range(of: "function")!
        let fooRange = input.range(of: "foo")!
        let aRange1 = input.range(of: "a")!
        let bRange1 = input.range(of: "b")!
        let bodyRange = input.range(of: "a + b")!
        let aRange2 = input.range(of: "a", range: bodyRange)!
        let bRange2 = input.range(of: "b", range: bodyRange)!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .function([
                        Identifier(name: "a", range: aRange1),
                        Identifier(name: "b", range: bRange1),
                    ], Expression(type: .infix(
                        Expression(type: .identifier("a"), range: aRange2),
                        .plus,
                        Expression(type: .identifier("b"), range: bRange2)
                    ), range: bodyRange)))
                ),
                range: functionRange.lowerBound ..< input.endIndex
            ),
        ]))
    }

    func testFunctionWithNoParameters() {
        let input = "function foo() = 5;"
        let functionRange = input.range(of: "function")!
        let fooRange = input.range(of: "foo")!
        let bodyRange = input.range(of: "5")!
        XCTAssertEqual(try parse(input), Program(source: input, statements: [
            Statement(
                type: .define(
                    Identifier(name: "foo", range: fooRange),
                    Definition(type: .function([], Expression(
                        type: .number(5),
                        range: bodyRange
                    )))
                ),
                range: functionRange.lowerBound ..< input.endIndex
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
            XCTAssertEqual(error.message, "Unexpected token 'foo'")
            XCTAssertEqual(input.line(at: range), 4)
        }
    }
}
