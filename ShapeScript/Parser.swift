//
//  Parser.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 26/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

// MARK: Public interface

public func parse(_ input: String) throws -> Program {
    var tokens = try ArraySlice(tokenize(input))
    let statements = try tokens.readStatements()
    if let token = tokens.first, token.type != .eof {
        throw ParserError(.unexpectedToken(token, expected: nil))
    }
    return Program(source: input, statements: statements)
}

public struct Program: Equatable {
    public let source: String
    public let statements: [Statement]
}

public enum StatementType: Equatable {
    case command(Identifier, Expression?)
    case block(Identifier, Block)
    case define(Identifier, Definition)
    case option(Identifier, Expression)
    case forloop(Identifier?, in: Expression, Block)
    case expression(Expression)
    case `import`(Expression)
}

public struct Statement: Equatable {
    public let type: StatementType
    public let range: SourceRange
}

public enum DefinitionType: Equatable {
    case block(Block)
    case expression(Expression)
}

public struct Definition: Equatable {
    public let type: DefinitionType
    public var range: SourceRange {
        switch type {
        case let .block(block):
            return block.range
        case let .expression(expression):
            return expression.range
        }
    }
}

public enum ExpressionType: Equatable {
    case number(Double)
    case string(String)
    case color(Color)
    case identifier(Identifier)
    case block(Identifier, Block)
    indirect case tuple([Expression])
    indirect case prefix(PrefixOperator, Expression)
    indirect case infix(Expression, InfixOperator, Expression)
    indirect case range(from: Expression, to: Expression, step: Expression?)
    indirect case member(Expression, Identifier)
    indirect case subexpression(Expression)
}

public struct Expression: Equatable {
    public let type: ExpressionType
    public let range: SourceRange
}

public struct Block: Equatable {
    public let statements: [Statement]
    public let range: SourceRange
}

public struct Identifier: Equatable {
    public let name: String
    public let range: SourceRange
}

public enum ParserErrorType: Equatable {
    case unexpectedToken(Token, expected: String?)
}

public struct ParserError: Error, Equatable {
    public let type: ParserErrorType

    public var range: SourceRange {
        switch type {
        case let .unexpectedToken(token, _):
            return token.range
        }
    }

    public var message: String {
        switch type {
        case let .unexpectedToken(token, _):
            return "Unexpected \(token.type.errorDescription)"
        }
    }

    public var hint: String? {
        switch type {
        case let .unexpectedToken(_, expected: expected?):
            return "Expected \(expected)."
        case .unexpectedToken(_, expected: nil):
            return nil
        }
    }

    init(_ type: ParserErrorType) {
        self.type = type
    }
}

// MARK: Implementation

private extension TokenType {
    var errorDescription: String {
        switch self {
        case .linebreak: return "end of line"
        case let .identifier(name): return "identifier '\(name)'"
        case let .keyword(keyword): return "keyword '\(keyword)'"
        case let .hexColor(string): return "color \(string)"
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

private extension ArraySlice where Element == Token {
    var nextToken: Token {
        first!
    }

    mutating func readToken() -> Token {
        popFirst()!
    }

    mutating func readToken(_ type: TokenType) -> Bool {
        guard nextToken.type == type else {
            return false
        }
        removeFirst()
        return true
    }

    mutating func requireToken(_ type: TokenType, as expected: String?) throws {
        guard readToken(type) else {
            throw ParserError(.unexpectedToken(nextToken, expected: expected))
        }
    }

    mutating func requireToken(_ type: TokenType) throws {
        try requireToken(type, as: type.errorDescription)
    }

    func require<T>(_ result: T?, as expected: String) throws -> T {
        guard let result = result else {
            throw ParserError(.unexpectedToken(nextToken, expected: expected))
        }
        return result
    }

    mutating func readIdentifier() -> Identifier? {
        let token = nextToken
        guard case let .identifier(name) = token.type else {
            return nil
        }
        removeFirst()
        return Identifier(name: name, range: token.range)
    }

    mutating func readBlock() throws -> Block? {
        let start = self
        guard readToken(.lbrace) else {
            return nil
        }
        let statements = try readStatements()
        let end = nextToken
        try requireToken(.rbrace)
        let range = start.nextToken.range.lowerBound ..< end.range.upperBound
        return Block(statements: statements, range: range)
    }

    mutating func readOption() throws -> StatementType? {
        guard readToken(.keyword(.option)) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "option name")
        let expression = try require(readExpressions(), as: "default value")
        return .option(name, expression)
    }

    mutating func readDefine() throws -> StatementType? {
        guard readToken(.keyword(.define)) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "identifier name")
        if let block = try readBlock() {
            return .define(name, Definition(type: .block(block)))
        }
        let expression = try require(readExpressions(), as: "value")
        return .define(name, Definition(type: .expression(expression)))
    }

    mutating func readForLoop() throws -> StatementType? {
        guard readToken(.keyword(.for)) else {
            return nil
        }
        let identifier = readIdentifier()
        let expression: Expression
        if let identifier = identifier, !readToken(.identifier("in")) {
            expression = Expression(type: .identifier(identifier), range: identifier.range)
        } else {
            expression = try require(readExpression(), as: "range")
        }
        let body = try require(readBlock(), as: "loop body")
        return .forloop(identifier, in: expression, body)
    }

    mutating func readImport() throws -> StatementType? {
        guard readToken(.keyword(.import)) else {
            return nil
        }
        return try .import(require(readExpression(), as: "file path"))
    }

    mutating func readOperand() throws -> Expression? {
        let start = self
        let token = readToken()
        var range = token.range
        let type: ExpressionType
        switch token.type {
        case .lparen:
            _ = readToken(.linebreak)
            let expression = try require(readExpressions(allowLinebreaks: true), as: "expression")
            let endToken = nextToken
            try requireToken(.rparen)
            range = range.lowerBound ..< endToken.range.upperBound
            type = .subexpression(expression)
        case let .prefix(op):
            let operand = try require(readOperand(), as: "operand")
            range = range.lowerBound ..< operand.range.upperBound
            type = .prefix(op, operand)
        case let .number(number):
            type = .number(number)
        case let .string(string):
            type = .string(string)
        case let .hexColor(string):
            type = .color(Color(hexString: string) ?? .black)
        case let .identifier(name):
            let identifier = Identifier(name: name, range: range)
            guard readToken(.lparen) else {
                type = .identifier(identifier)
                break
            }
            let expression = try require(readExpressions(), as: "expression")
            let endToken = nextToken
            try requireToken(.rparen)
            // repackage function syntax as a lisp-style subexpression
            // TODO: should we support this as a distinct construct?
            var expressions = [Expression(
                type: .identifier(identifier),
                range: range
            )]
            if case let .tuple(params) = expression.type {
                expressions += params
            } else {
                expressions.append(expression)
            }
            range = range.lowerBound ..< endToken.range.upperBound
            type = .subexpression(
                Expression(type: .tuple(expressions), range: range)
            )
        case .dot, .linebreak, .keyword, .infix, .lbrace, .rbrace, .rparen, .eof:
            self = start
            return nil
        }
        var expression = Expression(type: type, range: range)
        while case .dot = nextToken.type {
            removeFirst()
            let rhs = try require(readIdentifier(), as: "member name")
            expression = Expression(
                type: .member(expression, rhs),
                range: range.lowerBound ..< rhs.range.upperBound
            )
        }
        return expression
    }

    mutating func readTerm() throws -> Expression? {
        guard let lhs = try readOperand() else {
            return nil
        }
        guard case let .infix(op) = nextToken.type, [.times, .divide].contains(op) else {
            return lhs
        }
        removeFirst()
        let rhs = try require(readTerm(), as: "operand")
        return Expression(
            type: .infix(lhs, op, rhs),
            range: lhs.range.lowerBound ..< rhs.range.upperBound
        )
    }

    mutating func readExpression() throws -> Expression? {
        guard var lhs = try readTerm() else {
            return nil
        }
        while case let .infix(op) = nextToken.type {
            removeFirst()
            let rhs = try require(readTerm(), as: "operand")
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        guard case .identifier("to") = nextToken.type else {
            return lhs
        }
        removeFirst()
        let rhs = try require(readExpression(), as: "end value")
        guard case .identifier("step") = nextToken.type else {
            return Expression(
                type: .range(from: lhs, to: rhs, step: nil),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        removeFirst()
        let step = try require(readExpression(), as: "step value")
        return Expression(
            type: .range(from: lhs, to: rhs, step: step),
            range: lhs.range.lowerBound ..< step.range.upperBound
        )
    }

    mutating func readExpressions(allowLinebreaks: Bool = false) throws -> Expression? {
        var expressions = [Expression]()
        while var expression = try readExpression() {
            if case let .identifier(identifier) = expression.type, let block = try readBlock() {
                let range = identifier.range.lowerBound ..< block.range.upperBound
                expression = Expression(type: .block(identifier, block), range: range)
            }
            expressions.append(expression)
            if allowLinebreaks {
                _ = readToken(.linebreak)
            }
        }
        switch expressions.count {
        case 0:
            return nil
        case 1:
            return expressions[0]
        default:
            let range = expressions[0].range.lowerBound ..< expressions.last!.range.upperBound
            return Expression(type: .tuple(expressions), range: range)
        }
    }

    mutating func readStatement() throws -> StatementType? {
        if let statement = try readDefine() ?? readOption() ?? readForLoop() ?? readImport() {
            return statement
        }
        guard let name = readIdentifier() else {
            guard let expression = try readExpression() else {
                return nil
            }
            return .expression(expression)
        }
        if let statements = try readBlock() {
            return .block(name, statements)
        }
        return try .command(name, readExpressions())
    }

    mutating func readStatements() throws -> [Statement] {
        _ = readToken(.linebreak)
        var start = self
        var statements = [Statement]()
        while let type = try readStatement() {
            let end = start[start.index(before: startIndex)]
            let range = start.nextToken.range.lowerBound ..< end.range.upperBound
            statements.append(Statement(type: type, range: range))
            switch nextToken.type {
            case .linebreak:
                removeFirst()
            case .eof, .rbrace:
                break
            default:
                throw ParserError(.unexpectedToken(nextToken, expected: nil))
            }
            start = self
        }
        return statements
    }
}
