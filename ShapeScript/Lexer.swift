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
    var characters = Substring(input)
    var spaceBefore = true
    _ = characters.skipWhitespaceAndComments()
    while let token = try characters.readToken(spaceBefore: spaceBefore) {
        switch (tokens.last?.type, token.type) {
        case (.linebreak?, .linebreak):
            break // Skip duplicate linebreak
        case (.identifier?, .lparen) where spaceBefore && tokens.count > 1:
            switch tokens[tokens.count - 2].type {
            case .infix, .prefix:
                // Insert parens for disambiguation
                let identifier = tokens.removeLast()
                let range = identifier.range
                let lRange = range.lowerBound ..< range.lowerBound
                let rRange = range.upperBound ..< range.upperBound
                tokens += [
                    Token(type: .lparen, range: lRange),
                    identifier,
                    Token(type: .rparen, range: rRange),
                    token,
                ]
            default:
                tokens.append(token)
            }
        default:
            tokens.append(token)
        }
        spaceBefore = characters.skipWhitespaceAndComments()
        if !spaceBefore, let lastTokenType = tokens.last?.type {
            switch lastTokenType {
            case .infix, .prefix, .dot, .lparen, .lbrace, .call,
                 .lbracket, .subscript, .linebreak:
                spaceBefore = true
            case .identifier, .keyword, .hexColor, .number,
                 .string, .rbrace, .rparen, .rbracket, .eof:
                break
            }
        }
    }
    if !characters.isEmpty {
        let start = characters.startIndex
        let token = characters.readToEndOfToken()
        let range = start ..< characters.startIndex
        throw LexerError(.unexpectedToken(token), at: range)
    }
    tokens.append(Token(type: .eof, range: characters.startIndex ..< characters.endIndex))
    return tokens
}

/// Note: only includes keywords that start a command, not joining words
public enum Keyword: String, CaseIterable {
    case define
    case `for`
    case `if`
    case `else`
    case `import`
}

public enum PrefixOperator: String {
    case plus = "+"
    case minus = "-"
}

public enum InfixOperator: String, CaseIterable {
    case plus = "+"
    case minus = "-"
    case times = "*"
    case divide = "/"
    case modulo = "%"
    // Comparison operators
    case lt = "<"
    case gt = ">"
    case lte = "<="
    case gte = ">="
    case equal = "="
    case unequal = "<>"
    // Boolean operators
    case and, or
    // Range operators
    case `in`, to, step
}

public enum TokenType: Equatable {
    case linebreak
    case identifier(String)
    case keyword(Keyword)
    case hexColor(String)
    case infix(InfixOperator)
    case prefix(PrefixOperator)
    case number(Double)
    case string(String)
    case lbrace
    case rbrace
    case lparen
    case rparen
    case lbracket
    case rbracket
    case dot
    case call
    case `subscript`
    case eof
}

public typealias SourceRange = Range<String.Index>

public struct Token: Equatable {
    public let type: TokenType
    public let range: SourceRange
}

public enum LexerErrorType: Equatable {
    case invalidNumber(String)
    case invalidColor(String)
    case unexpectedToken(String)
    case unterminatedString
    case invalidEscapeSequence(String)
}

public struct LexerError: Error, Equatable {
    public let type: LexerErrorType
    public let range: SourceRange

    public init(_ type: LexerErrorType, at range: SourceRange) {
        self.type = type
        self.range = range
    }
}

public extension LexerError {
    var message: String {
        switch type {
        case let .invalidNumber(digits):
            return "Invalid numeric literal '\(digits)'"
        case let .invalidColor(string):
            return "Invalid color literal '#\(string)'"
        case let .unexpectedToken(token):
            guard token.count < 20, !token.contains("'") else {
                return "Unexpected token"
            }
            return "Unexpected token '\(token)'"
        case .unterminatedString:
            return "Unterminated string literal"
        case let .invalidEscapeSequence(sequence):
            let sequence = sequence.unicodeScalars.contains {
                CharacterSet.whitespaces.contains($0)
            } ? "'\(sequence)'" : sequence
            return "Invalid escape sequence \(sequence)"
        }
    }

    var suggestion: String? {
        switch type {
        case let .unexpectedToken(string):
            let options = InfixOperator.allCases.map(\.rawValue)
            return Self.alternatives[string.lowercased()] ??
                string.bestMatches(in: options).first
        case let .invalidEscapeSequence(string):
            return [
                "\"\"": "\\\"",
                "\\r": "\\n",
            ][string]
        default:
            return nil
        }
    }

    var hint: String? {
        switch type {
        case let .invalidNumber(digits):
            if digits.components(separatedBy: ".").count > 2 {
                return "Numbers must contain at most one decimal point."
            }
            return nil
        case .invalidColor:
            return "Hex colors must be 3, 4, 6 or 8 digits in length."
        case .unexpectedToken:
            if let suggestion {
                return "Did you mean '\(suggestion)'?"
            }
            return nil
        case .unterminatedString:
            return "Try adding a closing \" (double quote) at the end of the line."
        case .invalidEscapeSequence:
            let hint = "Supported sequences are \\\", \\n and \\\\."
            if let suggestion {
                return "\(hint) Did you mean \(suggestion)?"
            }
            return hint
        }
    }
}

public extension String {
    func lineRange(at index: Index, includingIndent: Bool = false) -> SourceRange {
        var endIndex = endIndex
        var startIndex = startIndex
        let index = min(max(index, startIndex), endIndex)
        var i = startIndex
        while i < index {
            let nextIndex = self.index(after: i)
            if self[i].isLinebreak {
                startIndex = nextIndex
            }
            i = nextIndex
        }
        while i < endIndex {
            if self[i].isLinebreak {
                endIndex = i
                break
            }
            i = self.index(after: i)
        }
        if !includingIndent {
            while startIndex < index, self[startIndex].isWhitespace {
                startIndex = self.index(after: startIndex)
            }
        }
        return startIndex ..< endIndex
    }

    func lineAndColumn(at index: Index) -> (line: Int, column: Int) {
        var line = 1, column = 1
        var i = startIndex
        while i < min(index, endIndex) {
            if self[i].isLinebreak == true {
                line += 1
                column = 1
            } else {
                column += 1
            }
            i = self.index(after: i)
        }
        return (line: line, column: column)
    }

    func line(at index: Index) -> Int {
        lineAndColumn(at: index).line
    }

    func range(ofLine line: Int) -> SourceRange {
        var line = line
        var start = startIndex
        while let end = self[start...].firstIndex(where: { $0.isLinebreak }) {
            line -= 1
            guard line > 0 else {
                return start ..< end
            }
            start = index(after: end)
        }
        return start ..< endIndex
    }
}

// MARK: Implementation

private extension LexerError {
    static let alternatives: [String: String] = [
        "&&": "and",
        "&": "and",
        "||": "or",
        "|": "or",
        "!": "not",
        "==": "=",
        "===": "=",
        "!=": "<>",
        "/=": "<>",
        "=/=": "<>",
        "=<": "<=",
        "=>": ">=",
    ]
}

private let whitespace = " \t"
private let linebreaks = "\n\r\r\n"
private let delimiters = "()[]{}"
private let operators = "+-*/<>=!?&|%^~"
private let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
private let digits = "0123456789"
private let alphanumerics = digits + letters
private let hexadecimals = digits + "ABCDEFabcdef"

private extension Character {
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

private extension Substring {
    mutating func skipBlockComment() {
        assert(first == "*")
        removeFirst()
        while let c = first {
            removeFirst()
            switch c {
            case "*" where first == "/":
                removeFirst()
                return
            case "/" where first == "*":
                skipBlockComment()
            default:
                break
            }
        }
    }

    mutating func skipWhitespaceAndComments() -> Bool {
        var wasSpace = false
        while let c = first {
            guard c.isWhitespace else {
                if c == "/" {
                    wasSpace = true
                    let nextIndex = index(after: startIndex)
                    if nextIndex != endIndex {
                        switch self[nextIndex] {
                        case "/":
                            removeFirst()
                            removeFirst()
                            while let c = first, !c.isLinebreak {
                                removeFirst()
                            }
                        case "*":
                            removeFirst()
                            skipBlockComment()
                            continue
                        default:
                            break
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
        guard let c = first, c.isLinebreak else {
            return nil
        }
        removeFirst()
        return .linebreak
    }

    mutating func readCharacters(in characters: String) -> String? {
        var result = ""
        while let c = first, characters.contains(c) {
            result.append(removeFirst())
        }
        return result.isEmpty ? nil : result
    }

    mutating func readToEndOfToken() -> String {
        if let string = readCharacters(in: delimiters) {
            return string
        } else if let string = readCharacters(in: operators) {
            return string
        } else {
            var string = ""
            let terminator = whitespace + linebreaks + delimiters + operators
            while let c = first, !terminator.contains(c) {
                string.append(removeFirst())
            }
            return string
        }
    }

    mutating func readOperator(spaceBefore: Bool) -> TokenType? {
        let start = self
        switch popFirst() {
        case "{": return .lbrace
        case "}": return .rbrace
        case "(": return spaceBefore ? .lparen : .call
        case ")": return .rparen
        case "[": return spaceBefore ? .lbracket : .subscript
        case "]": return .rbracket
        case "." where !spaceBefore:
            if let next = first, !next.isWhitespace, !next.isLinebreak {
                return .dot
            }
            self = start
            return nil
        case let c? where operators.contains(c):
            func toOp(_ string: String) -> TokenType? {
                if let op = InfixOperator(rawValue: string) {
                    guard let next = first else {
                        // technically postfix, but we don't have those
                        return .infix(op)
                    }
                    if !spaceBefore || next.isWhitespace || next.isLinebreak {
                        return .infix(op)
                    }
                    if let op = PrefixOperator(rawValue: string) {
                        return .prefix(op)
                    }
                    return .infix(op)
                } else if let op = PrefixOperator(rawValue: string) {
                    return .prefix(op)
                } else {
                    return nil
                }
            }
            var string = String(c)
            var op = toOp(string)
            var end = start
            if op != nil {
                end = self
            }
            while let c = first, operators.contains(c) {
                removeFirst()
                string.append(c)
                if let nextOp = toOp(string) {
                    op = nextOp
                    end = self
                }
            }
            let remaining = String(end[..<startIndex])
            if !remaining.isEmpty, PrefixOperator(rawValue: remaining) == nil {
                self = start
                return nil
            }
            self = end
            return op
        default:
            self = start
            return nil
        }
    }

    mutating func readNumber() throws -> TokenType? {
        let startIndex = startIndex
        var start = self, number = ""
        while let c = first, "\(digits).".contains(c) {
            if c == "." { start = self }
            number.append(removeFirst())
        }
        if number.last == ".", number.count == 1 || first.map({
            letters.contains($0)
        }) ?? false {
            number.removeLast()
            self = start
        }
        if number.isEmpty {
            return nil
        }
        guard let double = Double(number) else {
            let range = startIndex ..< self.startIndex
            throw LexerError(.invalidNumber(number), at: range)
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
        loop: while let c = first {
            if !escaped {
                switch c {
                case "\"":
                    removeFirst()
                    if first == "\"" {
                        let range = start.index(before: startIndex) ..< index(after: startIndex)
                        throw LexerError(.invalidEscapeSequence(String(start[range])), at: range)
                    }
                    return .string(string)
                case "\\":
                    escaped = true
                case "\n", "\r", "\r\n":
                    break loop
                default:
                    string.append(c)
                }
                removeFirst()
                continue
            }
            switch c {
            case "n":
                string.append("\n")
            case "\\", "\"":
                string.append(c)
            case "\n", "\r", "\r\n":
                break loop
            default:
                let range = start.index(before: startIndex) ..< index(after: startIndex)
                throw LexerError(.invalidEscapeSequence(String(start[range])), at: range)
            }
            removeFirst()
            escaped = false
        }
        let range = start.startIndex ..< startIndex
        throw LexerError(.unterminatedString, at: range)
    }

    mutating func readIdentifier() -> TokenType? {
        guard let head = first, letters.contains(head) else {
            return nil
        }
        removeFirst()
        let name = String(head) + (readCharacters(in: "\(alphanumerics)_") ?? "")
        if let keyword = Keyword(rawValue: name) {
            return .keyword(keyword)
        }
        return .identifier(name)
    }

    mutating func readHexColor() throws -> TokenType? {
        guard first == "#" else {
            return nil
        }
        let start = self
        removeFirst()
        let string = readCharacters(in: alphanumerics) ?? ""
        let range = start.startIndex ..< startIndex
        guard string.allSatisfy({ hexadecimals.contains($0) }) else {
            throw LexerError(.invalidColor(string), at: range)
        }
        switch string.count {
        case 3, 4, 6, 8:
            return .hexColor(string)
        case 0:
            throw LexerError(.unexpectedToken("#"), at: range)
        default:
            throw LexerError(.invalidColor(string), at: range)
        }
    }

    mutating func readToken(spaceBefore: Bool) throws -> Token? {
        let startIndex = startIndex
        guard let tokenType = try
            readLineBreak() ??
            readOperator(spaceBefore: spaceBefore) ??
            readNumber() ??
            readString() ??
            readIdentifier() ??
            readHexColor()
        else {
            return nil
        }
        let range = startIndex ..< self.startIndex
        return Token(type: tokenType, range: range)
    }
}
