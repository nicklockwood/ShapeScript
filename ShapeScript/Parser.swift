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
    let source: String
    let statements: [Statement]
}

public enum StatementType: Equatable {
    case command(Identifier, Expression?)
    case node(Identifier, Block)
    case define(Identifier, Definition)
    case option(Identifier, Expression)
    case forloop(index: Identifier?, from: Expression, to: Expression, Block)
    case expression(Expression)
    case `import`(Expression)
}

public struct Statement: Equatable {
    public let type: StatementType
    public let range: Range<String.Index>
}

public enum DefinitionType: Equatable {
    case block(Block)
    case expression(Expression)
}

public struct Definition: Equatable {
    public let type: DefinitionType
    public var range: Range<String.Index> {
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
    case identifier(Identifier)
    case node(Identifier, Block)
    indirect case tuple([Expression])
    indirect case prefix(PrefixOperator, Expression)
    indirect case infix(Expression, InfixOperator, Expression)
    indirect case member(Expression, Identifier)
    indirect case subexpression(Expression)
}

public struct Expression: Equatable {
    public let type: ExpressionType
    public let range: Range<String.Index>
}

public struct Block: Equatable {
    public let statements: [Statement]
    public let range: Range<String.Index>
}

public struct Identifier: Equatable {
    public let name: String
    public let range: Range<String.Index>
}

public enum ParserErrorType: Equatable {
    case unexpectedToken(Token, expected: String?)
}

public struct ParserError: Error, Equatable {
    public let type: ParserErrorType

    public var range: Range<String.Index> {
        switch type {
        case let .unexpectedToken(token, _):
            return token.range
        }
    }

    public var message: String {
        switch type {
        case let .unexpectedToken(token, _):
            return "Unexpected \(token.type.description)"
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

private extension ArraySlice where Element == Token {
    var nextToken: Token {
        return first!
    }

    mutating func readToken() -> Token {
        return popFirst()!
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
        try requireToken(type, as: type.description)
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
        try requireToken(.rbrace, as: nil)
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
        let index = readIdentifier()
        let start: Expression
        if let identifier = index, !readToken(.identifier("in")) {
            start = Expression(type: .identifier(identifier), range: identifier.range)
            try requireToken(.identifier("to"), as: "'to' or 'in'")
        } else {
            start = try require(readExpression(), as: "starting index")
            try requireToken(.identifier("to"), as: "'to'")
        }
        let end = try require(readExpression(), as: "end index")
        let body = try require(readBlock(), as: "loop body")
        return .forloop(index: index, from: start, to: end, body)
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
        let range = token.range
        if case .lparen = token.type {
            let expression = try require(readExpressions(), as: "expression")
            let endToken = nextToken
            try requireToken(.rparen)
            return Expression(
                type: .subexpression(expression),
                range: range.lowerBound ..< endToken.range.upperBound
            )
        }
        if case let .prefix(op) = token.type {
            let operand = try require(readOperand(), as: "operand")
            return Expression(
                type: .prefix(op, operand),
                range: range.lowerBound ..< operand.range.upperBound
            )
        }
        let type: ExpressionType
        switch token.type {
        case let .number(number):
            type = .number(number)
        case let .string(string):
            type = .string(string)
        case let .identifier(name):
            type = .identifier(Identifier(name: name, range: range))
            if readToken(.lparen) {
                let expression = try require(readExpressions(), as: "expression")
                let endToken = nextToken
                try requireToken(.rparen)
                // repackage function syntax as a lisp-style subexpression
                // TODO: should we support this as a distinct construct?
                var expressions = [Expression(type: type, range: range)]
                switch expression.type {
                case let .tuple(params):
                    expressions += params
                default:
                    expressions.append(expression)
                }
                return Expression(
                    type: .subexpression(
                        Expression(
                            type: .tuple(expressions),
                            range: range.lowerBound ..< expression.range.upperBound
                        )
                    ),
                    range: range.lowerBound ..< endToken.range.upperBound
                )
            }
        default:
            self = start
            return nil
        }
        return Expression(type: type, range: range)
    }

    mutating func readTerm() throws -> Expression? {
        guard let lhs = try readOperand() else {
            return nil
        }
        switch nextToken.type {
        case .dot:
            removeFirst()
            let rhs = try require(readIdentifier(), as: "member name")
            return Expression(
                type: .member(lhs, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        case let .infix(op) where [.times, .divide].contains(op):
            removeFirst()
            let rhs = try require(readTerm(), as: "operand")
            return Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        default:
            return lhs
        }
    }

    mutating func readExpression() throws -> Expression? {
        guard let lhs = try readTerm() else {
            return nil
        }
        let token = nextToken
        if case let .infix(op) = token.type {
            removeFirst()
            let rhs = try require(readExpression(), as: "operand")
            return Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return lhs
    }

    mutating func readExpressions() throws -> Expression? {
        var expressions = [Expression]()
        while var expression = try readExpression() {
            if case let .identifier(identifier) = expression.type, let block = try readBlock() {
                let range = identifier.range.lowerBound ..< block.range.upperBound
                expression = Expression(type: .node(identifier, block), range: range)
            }
            expressions.append(expression)
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
            return .node(name, statements)
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
