//
//  Lexer.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 07/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Foundation

// MARK: Public interface

public func tokenize(_ input: String) throws -> [Token] {
    var tokens: [Token] = []
    var scalars = Substring(input).unicodeScalars
    var spaceBefore = true
    _ = scalars.skipWhitespaceAndComments()
    while let token = try scalars.readToken(spaceBefore: spaceBefore) {
        if token.type != .linebreak || tokens.last?.type != .linebreak {
            tokens.append(token)
        }
        spaceBefore = scalars.skipWhitespaceAndComments()
        if !spaceBefore, let lastTokenType = tokens.last?.type {
            switch lastTokenType {
            case .infix, .dot, .lparen, .lbrace, .linebreak:
                spaceBefore = true
            case .identifier, .keyword, .prefix, .number, .string, .rbrace, .rparen, .eof:
                break
            }
        }
    }
    if !scalars.isEmpty {
        let start = scalars.startIndex
        let token = scalars.readToEndOfToken()
        let range = start ..< scalars.startIndex
        throw LexerError(.unexpectedToken(token), at: range)
    }
    tokens.append(Token(type: .eof, range: scalars.startIndex ..< scalars.endIndex))
    return tokens
}

/// Note: only includes keywords that start a command, not joining words
public enum Keyword: String, CaseIterable {
    case define
    case option
    case `for`
    case `import`
}

public enum PrefixOperator: UnicodeScalar {
    case plus = "+"
    case minus = "-"
}

public enum InfixOperator: UnicodeScalar {
    case plus = "+"
    case minus = "-"
    case times = "*"
    case divide = "/"
}

public enum TokenType: Equatable, CustomStringConvertible {
    case linebreak
    case identifier(String)
    case keyword(Keyword)
    case infix(InfixOperator)
    case prefix(PrefixOperator)
    case number(Double)
    case string(String)
    case lbrace
    case rbrace
    case lparen
    case rparen
    case dot
    case eof

    public var description: String {
        switch self {
        case .linebreak: return "end of line"
        case let .identifier(name): return "identifier '\(name)'"
        case let .keyword(keyword): return "keyword '\(keyword)'"
        case let .infix(op): return "operator '\(op.rawValue)'"
        case let .prefix(op): return "prefix operator '\(op.rawValue)'"
        case .number: return "numeric literal"
        case .string: return "string literal"
        case .lbrace: return "opening brace"
        case .rbrace: return "closing brace"
        case .lparen: return "opening paren"
        case .rparen: return "closing paren"
        case .dot: return "dot"
        case .eof: return "end of file"
        }
    }
}

public struct Token: Equatable {
    public let type: TokenType
    public let range: Range<String.Index>
}

public enum LexerErrorType: Equatable {
    case invalidNumber(String)
    case unexpectedToken(String)
    case unterminatedString
}

public struct LexerError: Error, Equatable {
    public let type: LexerErrorType
    public let range: Range<String.Index>

    public var message: String {
        switch type {
        case let .invalidNumber(digits):
            return "Invalid numeric literal '\(digits)'"
        case let .unexpectedToken(token):
            guard token.count < 20, !token.contains("'") else {
                return "Unexpected token"
            }
            return "Unexpected token '\(token)'"
        case .unterminatedString:
            return "Unterminated string literal"
        }
    }

    public var hint: String? {
        switch type {
        case let .invalidNumber(digits):
            if digits.components(separatedBy: ".").count > 2 {
                return "Numbers should contains at most one decimal point."
            }
            return nil
        case .unexpectedToken:
            return nil
        case .unterminatedString:
            return "Try adding a closing \" (double quote) at the end of the line."
        }
    }

    init(_ type: LexerErrorType, at range: Range<String.Index>) {
        self.type = type
        self.range = range
    }
}

public extension String {
    func lineRange(at index: String.Index, includingIndent: Bool = false) -> Range<String.Index> {
        let scalars = unicodeScalars
        var endIndex = scalars.endIndex
        var startIndex = scalars.startIndex
        var i = startIndex
        while i < endIndex {
            let nextIndex = scalars.index(after: i)
            if scalars[i].isLinebreak {
                if i >= index {
                    endIndex = i
                    break
                }
                startIndex = nextIndex
            }
            i = nextIndex
        }
        if !includingIndent {
            while startIndex < endIndex, scalars[startIndex].isWhitespace {
                startIndex = scalars.index(after: startIndex)
            }
        }
        return startIndex ..< endIndex
    }

    func lineAndColumn(at index: String.Index) -> (line: Int, column: Int) {
        var line = 1, column = 1
        let scalars = unicodeScalars
        var i = scalars.startIndex
        assert(index < scalars.endIndex)
        while i < min(index, scalars.endIndex) {
            if scalars[i].isLinebreak {
                line += 1
                column = 1
            } else {
                column += 1
            }
            i = scalars.index(after: i)
        }
        return (line: line, column: column)
    }
}

// MARK: Implementation

private let whitespace = CharacterSet.whitespaces
private let linebreaks = CharacterSet.newlines

private extension UnicodeScalar {
    var isWhitespace: Bool {
        whitespace.contains(self)
    }

    var isLinebreak: Bool {
        linebreaks.contains(self)
    }

    var isWhitespaceOrLinebreak: Bool {
        isWhitespace || isLinebreak
    }
}

private extension Substring.UnicodeScalarView {
    mutating func skipWhitespaceAndComments() -> Bool {
        var wasSpace = false
        while let scalar = first {
            guard scalar.isWhitespace else {
                if scalar == "/" {
                    wasSpace = true
                    let nextIndex = index(after: startIndex)
                    if nextIndex != endIndex, self[nextIndex] == "/" {
                        removeFirst()
                        removeFirst()
                        while let scalar = first, !scalar.isLinebreak {
                            removeFirst()
                        }
                    }
                }
                break
            }
            wasSpace = true
            removeFirst()
        }
        return wasSpace
    }

    mutating func readLineBreak() -> TokenType? {
        guard let scalar = first, scalar.isLinebreak else {
            return nil
        }
        removeFirst()
        return .linebreak
    }

    mutating func readToEndOfToken() -> String {
        var string = ""
        let punctuation = CharacterSet(charactersIn: "/()[]{}")
        if let scalar = popFirst() {
            string.append(Character(scalar))
            if punctuation.contains(scalar) {
                while let scalar = first, punctuation.contains(scalar) {
                    string.append(Character(removeFirst()))
                }
            } else {
                let terminator = whitespace.union(punctuation)
                while let scalar = first, !terminator.contains(scalar) {
                    string.append(Character(removeFirst()))
                }
            }
        }
        return string
    }

    mutating func readOperator(spaceBefore: Bool) -> TokenType? {
        let start = self
        switch popFirst() {
        case "{": return .lbrace
        case "}": return .rbrace
        case "(": return .lparen
        case ")": return .rparen
        case "." where !spaceBefore:
            if let next = first, !next.isWhitespace, !next.isLinebreak {
                return .dot
            }
            self = start
            return nil
        case let scalar?:
            if let op = InfixOperator(rawValue: scalar) {
                guard let next = first else {
                    // technically postfix, but we don't have those
                    return .infix(op)
                }
                if !spaceBefore || next.isWhitespace || next.isLinebreak {
                    return .infix(op)
                }
                if let op = PrefixOperator(rawValue: scalar) {
                    return .prefix(op)
                }
                return .infix(op)
            } else if let op = PrefixOperator(rawValue: scalar) {
                return .prefix(op)
            }
            fallthrough
        default:
            self = start
            return nil
        }
    }

    mutating func readNumber() throws -> TokenType? {
        let start = self
        var digits = ""
        while let c = first, CharacterSet.decimalDigits.contains(c) || c == "." {
            digits.append(Character(removeFirst()))
        }
        if digits.isEmpty {
            return nil
        }
        guard let double = Double(digits) else {
            let range = start.startIndex ..< startIndex
            let error: LexerErrorType = (digits == ".") ?
                .unexpectedToken(digits) : .invalidNumber(digits)
            throw LexerError(error, at: range)
        }
        return .number(double)
    }

    mutating func readString() throws -> TokenType? {
        guard first == "\"" else {
            return nil
        }
        let start = self
        removeFirst()
        var string = "", escaped = false
        loop: while let scalar = first {
            switch scalar {
            case "\"" where !escaped:
                removeFirst()
                return .string(string)
            case "\\" where !escaped:
                escaped = true
            case "\n", "\r":
                break loop
            default:
                string.append(Character(scalar))
                escaped = false
            }
            removeFirst()
        }
        let range = start.startIndex ..< startIndex
        throw LexerError(.unterminatedString, at: range)
    }

    mutating func readIdentifier() -> TokenType? {
        guard let head = first, CharacterSet.letters.contains(head) else {
            return nil
        }
        var name = String(removeFirst())
        while let c = first, CharacterSet.alphanumerics.contains(c) {
            name.append(Character(removeFirst()))
        }
        if let keyword = Keyword(rawValue: name) {
            return .keyword(keyword)
        }
        return .identifier(name)
    }

    mutating func readToken(spaceBefore: Bool) throws -> Token? {
        let startIndex = self.startIndex
        guard let tokenType = try
            readLineBreak() ??
            readOperator(spaceBefore: spaceBefore) ??
            readNumber() ??
            readString() ??
            readIdentifier()
        else {
            return nil
        }
        let range = startIndex ..< self.startIndex
        return Token(type: tokenType, range: range)
    }
}
