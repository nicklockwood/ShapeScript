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
                    index: Identifier(name: "i", range: iRange),
                    from: Expression(type: .number(1), range: range1),
                    to: Expression(type: .number(2), range: range2),
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
                    index: nil,
                    from: Expression(type: .number(1), range: range1),
                    to: Expression(type: .number(2), range: range2),
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
            XCTAssertEqual(error?.hint, "Expected starting index.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "starting index"
            )))
        }
    }

    func testForLoopWithInvalidIndex() {
        let input = "for 5 in {}"
        let inRange = input.range(of: "in")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected identifier 'in'")
            XCTAssertEqual(error?.hint, "Expected 'to'.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .identifier("in"), range: inRange),
                expected: "'to'"
            )))
        }
    }

    func testForLoopWithoutIndexOrCondition() {
        let input = "for {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected starting index.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "starting index"
            )))
        }
    }

    func testForLoopWithoutTo() {
        let input = "for 1 {}"
        let braceRange = input.range(of: "{")!
        XCTAssertThrowsError(try parse(input)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            XCTAssertEqual(error?.message, "Unexpected opening brace")
            XCTAssertEqual(error?.hint, "Expected 'to'.")
            XCTAssertEqual(error, ParserError(.unexpectedToken(
                Token(type: .lbrace, range: braceRange),
                expected: "'to'"
            )))
        }
    }
}
