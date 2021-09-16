//
//  ShapeScriptTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 07/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

class LexerTests: XCTestCase {
    // MARK: whitespace

    func testLeadingSpace() {
        let input = " abc"
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTrailingSpace() {
        let input = "abc "
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTrailingSpaceBeforeLinebreak() {
        let input = "abc \n"
        let tokens: [TokenType] = [.identifier("abc"), .linebreak, .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTrailingSpaceAfterLinebreak() {
        let input = "abc\n "
        let tokens: [TokenType] = [.identifier("abc"), .linebreak, .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testMultipleTrailingLinebreaks() {
        let input = "abc \n \n "
        let tokens: [TokenType] = [.identifier("abc"), .linebreak, .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testCRLFTreatedAsSingleCharacter() {
        let input = "abc\r\n"
        let tokens: [TokenType] = [.identifier("abc"), .linebreak, .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    // MARK: identifiers

    func testLetters() {
        let input = "abc dfe"
        let tokens: [TokenType] = [.identifier("abc"), .identifier("dfe"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testLettersNumbersAndUnderscore() {
        let input = "a123_4b"
        let tokens: [TokenType] = [.identifier("a123_4b"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInvalidIdentifier() {
        let input = "a123$4b"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("$4b"))
        }
    }

    func testLeadingUnderscore() {
        let input = "_a\n\ndefine foo 5"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("_a"))
        }
    }

    // MARK: numbers

    func testZero() {
        let input = "0"
        let tokens: [TokenType] = [.number(0), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testDigit() {
        let input = "5"
        let tokens: [TokenType] = [.number(5), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testMultidigit() {
        let input = "50"
        let tokens: [TokenType] = [.number(50), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testLeadingZero() {
        let input = "05"
        let tokens: [TokenType] = [.number(5), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testDecimal() {
        let input = "0.5"
        let tokens: [TokenType] = [.number(0.5), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testLeadingDecimalPoint() {
        let input = ".56"
        let tokens: [TokenType] = [.number(0.56), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTrailingDecimalPoint() {
        let input = "56."
        let tokens: [TokenType] = [.number(56), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTooManyDecimalPoints() {
        let input = "0.5.6"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidNumber("0.5.6"))
        }
    }

    // MARK: strings

    func testSimpleString() {
        let input = """
        "foo"
        """
        let tokens: [TokenType] = [.string("foo"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringWithSpace() {
        let input = """
        "foo bar"
        """
        let tokens: [TokenType] = [.string("foo bar"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringWithEscapedQuotes() {
        let input = """
        "\\"foo\\""
        """
        let tokens: [TokenType] = [.string("\"foo\""), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringWithEscapedNewline() {
        let input = """
        "foo\\nbar"
        """
        let tokens: [TokenType] = [.string("foo\nbar"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringEndingWithEscapedNewline() {
        let input = """
        "foo\\n"
        """
        let tokens: [TokenType] = [.string("foo\n"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringWithMultipleEscapedNewlines() {
        let input = """
        "foo\\n\\n\\nbar"
        """
        let tokens: [TokenType] = [.string("foo\n\n\nbar"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testStringWithInvalidEscapeSequence() {
        let input = """
        "foo\\'bar"
        """
        let range = input.range(of: "\\'")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error, LexerError(.unexpectedToken("\\'"), at: range))
        }
    }

    func testUnterminatedStringLiteral() {
        let input = """
        "foo
        """
        let range = input.range(of: "\"foo")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error, LexerError(.unterminatedString, at: range))
        }
    }

    func testUnterminatedStringLiteralFollowedByLinebreak() {
        let input = """
        "foo

        """
        let range = input.range(of: "\"foo")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error, LexerError(.unterminatedString, at: range))
        }
    }

    func testUnterminatedStringLiteralEndingInEscape() {
        let input = """
        "foo\\
        """
        let range = input.range(of: "\"foo\\")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error, LexerError(.unterminatedString, at: range))
        }
    }

    func testUnterminatedStringLiteralFollowedByEscapedLinebreak() {
        let input = """
        "foo\\

        """
        let range = input.range(of: "\"foo\\")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error, LexerError(.unterminatedString, at: range))
        }
    }

    // MARK: colors

    func test0DigitColor() {
        let input = "#"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("#"))
        }
    }

    func test1DigitColor() {
        let input = "#A"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("A"))
        }
    }

    func test2DigitColor() {
        let input = "#12"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("12"))
        }
    }

    func test3DigitColor() {
        let input = "#abc"
        let tokens: [TokenType] = [.hexColor("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func test4DigitColor() {
        let input = "#123F"
        let tokens: [TokenType] = [.hexColor("123F"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func test5DigitColor() {
        let input = "#12345"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("12345"))
        }
    }

    func test6DigitColor() {
        let input = "#1A2B3C"
        let tokens: [TokenType] = [.hexColor("1A2B3C"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func test7DigitColor() {
        let input = "#1A2B3C4"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("1A2B3C4"))
        }
    }

    func test8DigitColor() {
        let input = "#1A2B3C4D"
        let tokens: [TokenType] = [.hexColor("1A2B3C4D"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func test9DigitColor() {
        let input = "#1A2B3C4D5"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("1A2B3C4D5"))
        }
    }

    func testInvalidColor() {
        let input = "#123Z"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .invalidColor("123Z"))
        }
    }

    // MARK: operators

    func testPrefixExpression() {
        let input = "-1"
        let tokens: [TokenType] = [.prefix(.minus), .number(1), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInfixExpressionWithoutSpaces() {
        let input = "1+2"
        let tokens: [TokenType] = [.number(1), .infix(.plus), .number(2), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInfixExpressionWithSpaces() {
        let input = "1 + 2"
        let tokens: [TokenType] = [.number(1), .infix(.plus), .number(2), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInfixThenPrefixExpressionWithoutSpaces() {
        let input = "1+-2"
        let tokens: [TokenType] = [.number(1), .infix(.plus), .prefix(.minus), .number(2), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInfixThenPrefixExpressionWithSpaces() {
        let input = "1 + -2"
        let tokens: [TokenType] = [.number(1), .infix(.plus), .prefix(.minus), .number(2), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTupleWithPrefixOperator() {
        let input = "1 -2"
        let tokens: [TokenType] = [.number(1), .prefix(.minus), .number(2), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    // MARK: member access

    func testMemberLookupOnIdentifier() {
        let input = "a.x"
        let tokens: [TokenType] = [.identifier("a"), .dot, .identifier("x"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testMemberLookupOnExpression() {
        let input = "(1 2 3).x"
        let tokens: [TokenType] = [
            .lparen,
            .number(1),
            .number(2),
            .number(3),
            .rparen,
            .dot,
            .identifier("x"),
            .eof,
        ]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testMemberLookupWithLeadingSpace() {
        let input = "a .b"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("."))
        }
    }

    func testMemberLookupWithTrailingSpace() {
        let input = "a. b"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("."))
        }
    }

    // MARK: lineRange

    func testLineRangeOfIndexAtStartOfInput() {
        let input = "foo"
        let range = input.lineRange(at: input.startIndex)
        XCTAssertEqual(range, input.startIndex ..< input.endIndex)
    }

    func testLineRangeOfIndexAtEndOfInput() {
        let input = "foo"
        let range = input.lineRange(at: input.endIndex)
        XCTAssertEqual(range, input.startIndex ..< input.endIndex)
    }

    func testLineRangeOfIndexAtStartOfLine() {
        let input = "foo\nbar"
        let index = input.firstIndex(of: "b")!
        let range = input.lineRange(at: index)
        XCTAssertEqual(range, index ..< input.endIndex)
    }

    func testLineRangeOfIndexAtEndOfLine() {
        let input = "foo\nbar\nbaz"
        let index = input.lastIndex(of: "\n")!
        let range = input.lineRange(at: index)
        XCTAssertEqual(range, input.firstIndex(of: "b")! ..< index)
    }

    // MARK: lineAndColumn

    func testLineAndColumnAtStartOfInput() {
        let input = "foo"
        let lc = input.lineAndColumn(at: input.startIndex)
        XCTAssertEqual(lc.line, 1)
        XCTAssertEqual(lc.column, 1)
    }

    func testLineAndColumnAtEndOfLine() {
        let input = "foo\nbar\nbaz"
        let index = input.lastIndex(of: "\n")!
        let lc = input.lineAndColumn(at: index)
        XCTAssertEqual(lc.line, 2)
        XCTAssertEqual(lc.column, 4)
    }

    func testLineAndColumnAtCRLFEndOfLine() {
        let input = "foo\r\nbar\r\nbaz"
        let index = input.lastIndex(of: "\r\n")!
        let lc = input.lineAndColumn(at: index)
        XCTAssertEqual(lc.line, 2)
        XCTAssertEqual(lc.column, 4)
    }
}
