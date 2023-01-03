//
//  LexerTests.swift
//  SCADLibTests
//
//  Created by Nick Lockwood on 03/01/2023.
//

@testable import SCADLib
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
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testTrailingSpaceAfterLinebreak() {
        let input = "abc\n "
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testMultipleTrailingLinebreaks() {
        let input = "abc \n \n "
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testCRLFTreatedAsSingleCharacter() {
        let input = "abc\r\n"
        let tokens: [TokenType] = [.identifier("abc"), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    // MARK: comments

    func testSingleLineComment() {
        let input = "// abc"
        let tokens: [TokenType] = [.eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testConsecutiveSingleLineComments() {
        let input = "// abc\n// xyz"
        let tokens: [TokenType] = [.eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testSingleLineCommentAfterDecimal() {
        let input = "5.// abc"
        let tokens: [TokenType] = [.number(5), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testSingleLineCommentAfterInfixOperator() {
        let input = "5 + // abc"
        let tokens: [TokenType] = [.number(5), .infix(.plus), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testBlockComment() {
        let input = "/* abc\nxyz */"
        let tokens: [TokenType] = [.eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testBlockCommentFollowedBySpace() {
        let input = "/* abc */ "
        let tokens: [TokenType] = [.eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testNestedBlockComments() {
        let input = "foo /* abc /* xyz */ */ bar"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("*/"))
        }
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

    func testInsertPhantomParensForDisambiguation() {
        let input = "-a (b)"
        let tokens: [TokenType] = [
            .prefix(.minus), .lparen, .identifier("a"), .rparen,
            .lparen, .identifier("b"), .rparen, .eof,
        ]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testInsertPhantomParensForDisambiguation2() {
        let input = "a + b (c)"
        let tokens: [TokenType] = [
            .identifier("a"), .infix(.plus),
            .lparen, .identifier("b"), .rparen,
            .lparen, .identifier("c"), .rparen, .eof,
        ]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
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

    func testNegativeInteger() {
        let input = "-56"
        let tokens: [TokenType] = [.prefix(.minus), .number(56), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testNegativeDecimal() {
        let input = "-5.6"
        let tokens: [TokenType] = [.prefix(.minus), .number(5.6), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testNegativeLeadingDecimalPoint() {
        let input = "-.56"
        let tokens: [TokenType] = [.prefix(.minus), .number(0.56), .eof]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
    }

    func testLeadingDecimalPointInParens() {
        let input = "(.56)"
        let tokens: [TokenType] = [.lparen, .number(0.56), .rparen, .eof]
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
            XCTAssertEqual(error, LexerError(.invalidEscapeSequence("\\'"), at: range))
        }
    }

    func testStringWithUnsupportedEscapeSequence() {
        let input = """
        "foo\\rbar"
        """
        let range = input.range(of: "\\r")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "\\n")
            XCTAssertEqual(error, LexerError(.invalidEscapeSequence("\\r"), at: range))
        }
    }

    func testStringWithBasicStyleQuoteEscapeSequence() {
        let input = """
        "foo""bar"
        """
        let range = input.range(of: "\"\"")!
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "\\\"")
            XCTAssertEqual(error, LexerError(.invalidEscapeSequence("\"\""), at: range))
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

    func testMisspelledAssignOperator() {
        let input = "foo := bar"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "=")
            XCTAssertEqual(error?.type, .unexpectedToken(":="))
        }
    }

    func testMisspelledEqualOperator() {
        let input = "print true === false"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "==")
            XCTAssertEqual(error?.type, .unexpectedToken("==="))
        }
    }

    func testMisspelledUnequalOperator() {
        let input = "print true <> false"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "!=")
            XCTAssertEqual(error?.type, .unexpectedToken("<>"))
        }
    }

    func testMisspelledGTEOperator() {
        let input = "print 3 => 1"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, ">=")
            XCTAssertEqual(error?.type, .unexpectedToken("=>"))
        }
    }

    func testMisspelledAndOperator() {
        let input = "print true & false"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "&&")
        }
    }

    func testMisspelledOrOperator() {
        let input = "print true | false"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "||")
            XCTAssertEqual(error?.type, .unexpectedToken("|"))
        }
    }

    func testMisspelledNotOperator() {
        let input = "print ~(true || false)"
        XCTAssertThrowsError(try tokenize(input)) { error in
            let error = try? XCTUnwrap(error as? LexerError)
            XCTAssertEqual(error?.suggestion, "!")
            XCTAssertEqual(error?.type, .unexpectedToken("~"))
        }
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
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken(".b"))
        }
    }

    func testMemberLookupWithTrailingSpace() {
        let input = "a. b"
        XCTAssertThrowsError(try tokenize(input)) { error in
            XCTAssertEqual((error as? LexerError)?.type, .unexpectedToken("."))
        }
    }

    func testMemberLookupOnNumber() {
        let input = "5.a"
        let tokens: [TokenType] = [
            .number(5),
            .dot,
            .identifier("a"),
            .eof,
        ]
        XCTAssertEqual(try tokenize(input).map { $0.type }, tokens)
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
