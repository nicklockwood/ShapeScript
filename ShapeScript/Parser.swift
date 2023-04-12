//
//  Parser.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 26/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid

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
    case define(Identifier, Definition)
    case option(Identifier, Expression)
    case forloop(Identifier?, in: Expression, Block)
    case ifelse(Expression, Block, else: Block?)
    case switchcase(Expression, [CaseStatement], else: Block?)
    case expression(Expression)
}

public struct Statement: Equatable {
    public let type: StatementType
    public let range: SourceRange
}

public enum DefinitionType: Equatable {
    case block(Block)
    case function([Identifier], Block)
    case expression(Expression)
}

public struct Definition: Equatable {
    public let type: DefinitionType
    public var range: SourceRange {
        switch type {
        case let .block(block), let .function(_, block):
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
    case identifier(String)
    case block(Identifier, Block)
    case tuple([Expression])
    indirect case prefix(PrefixOperator, Expression)
    indirect case infix(Expression, InfixOperator, Expression)
    indirect case member(Expression, Identifier)
    indirect case `import`(Expression)
}

public struct Expression: Equatable {
    public let type: ExpressionType
    public let range: SourceRange
}

public struct Block: Equatable {
    public let statements: [Statement]
    public let range: SourceRange
}

public struct CaseStatement: Equatable {
    var pattern: Expression
    var body: Block
    var range: SourceRange
}

public struct Identifier: Equatable {
    public let name: String
    public let range: SourceRange
}

public enum ParserErrorType: Equatable {
    case unexpectedToken(Token, expected: String?)
    case custom(String, hint: String?, at: SourceRange?)
}

public struct ParserError: Error, Equatable {
    public let type: ParserErrorType

    public init(_ type: ParserErrorType) {
        self.type = type
    }
}

public extension ParserError {
    var range: SourceRange? {
        switch type {
        case let .unexpectedToken(token, _):
            return token.range
        case let .custom(_, _, at: range):
            return range
        }
    }

    var message: String {
        switch type {
        case let .unexpectedToken(token, _):
            return "Unexpected \(token.type.errorDescription)"
        case let .custom(message, _, _):
            return message
        }
    }

    var suggestion: String? {
        switch type {
        case let .unexpectedToken(token, expected):
            guard case let .identifier(string) = token.type else {
                return nil
            }
            guard let expected = expected else {
                let options = Keyword.allCases.map { $0.rawValue }
                return string.bestMatches(in: options).first
            }
            switch expected {
            case "if body", "operator":
                let options = InfixOperator.allCases.map { $0.rawValue }
                return Self.alternatives[string.lowercased()] ??
                    string.bestMatches(in: options).first
            case "case statement":
                return string == "default" ? "else" : nil
            default:
                return nil
            }
        case .custom:
            return nil
        }
    }

    var hint: String? {
        switch type {
        case let .unexpectedToken(_, expected: expected):
            if let suggestion = suggestion {
                return "Did you mean '\(suggestion)'?"
            }
            return expected.map { "Expected \($0)." }
        case let .custom(_, hint: hint, _):
            return hint
        }
    }
}

// MARK: Implementation

extension ParserError {
    static let alternatives: [String: String] = [
        "mod": "%",
        "fmod": "%",
        "equals": "=",
        "eq": "=",
        "is": "=",
    ]
}

private extension TokenType {
    var errorDescription: String {
        switch self {
        case .linebreak: return "end of line"
        case let .identifier(name): return "token '\(name)'"
        case let .keyword(keyword): return "keyword '\(keyword)'"
        case let .hexColor(string): return "color \(string)"
        case let .infix(op): return "operator '\(op.rawValue)'"
        case let .prefix(op): return "prefix operator '\(op.rawValue)'"
        case .number: return "numeric literal"
        case .string: return "text literal"
        case .lbrace: return "opening brace"
        case .rbrace: return "closing brace"
        case .lparen, .call: return "opening paren"
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
        guard readToken(.identifier("option")) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "option name")
        let expression = try require(readExpressions(), as: "default value")
        return .option(name, expression)
    }

    mutating func readParameters() throws -> [Identifier]? {
        let start = self
        guard let expression = try readExpressions() else {
            return []
        }
        switch expression.type {
        case let .identifier(name):
            return [Identifier(name: name, range: expression.range)]
        case let .tuple(expressions):
            var names = [Identifier]()
            for expression in expressions {
                guard case let .identifier(name) = expression.type else {
                    fallthrough
                }
                names.append(Identifier(name: name, range: expression.range))
            }
            return names
        default:
            self = start
            return nil
        }
    }

    mutating func readDefine() throws -> StatementType? {
        guard readToken(.keyword(.define)) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "symbol name")
        let start = self
        // TODO: should lparen be permitted here?
        guard readToken(.call) || readToken(.lparen),
              let names = try readParameters(),
              readToken(.rparen),
              let block = try readBlock()
        else {
            self = start
            if let block = try readBlock() {
                return .define(name, Definition(type: .block(block)))
            }
            let expression = try require(readExpressions(), as: "value")
            return .define(name, Definition(type: .expression(expression)))
        }
        return .define(name, Definition(type: .function(names, block)))
    }

    mutating func readForLoop() throws -> StatementType? {
        guard readToken(.keyword(.for)) else {
            return nil
        }
        var identifier: Identifier?
        var expression = try require(readExpression(), as: "index or range")
        if case let .identifier(name) = expression.type, readToken(.identifier("in")) {
            identifier = Identifier(name: name, range: expression.range)
            expression = try require(readExpression(), as: "range")
        }
        let body = try require(readBlock(), as: "loop body")
        return .forloop(identifier, in: expression, body)
    }

    mutating func readIfElse() throws -> StatementType? {
        guard readToken(.keyword(.if)) else {
            return nil
        }
        let condition = try require(readExpression(), as: "condition")
        let body = try require(readBlock(), as: "if body")
        let start = self
        _ = readToken(.linebreak)
        guard readToken(.keyword(.else)) else {
            self = start
            return .ifelse(condition, body, else: nil)
        }
        let lowerBound = nextToken.range.lowerBound
        if let elseBody = try readBlock() {
            return .ifelse(condition, body, else: elseBody)
        } else if let statementType = try readIfElse() {
            let end = start[start.index(before: startIndex)]
            let range = lowerBound ..< end.range.upperBound
            return .ifelse(condition, body, else: Block(statements: [
                Statement(type: statementType, range: range),
            ], range: range))
        }
        throw ParserError(.unexpectedToken(nextToken, expected: "else body"))
    }

    mutating func readSwitch() throws -> StatementType? {
        guard readToken(.identifier("switch")) else {
            return nil
        }
        let condition = try require(readExpression(), as: "condition")
        try requireToken(.lbrace)
        var cases = [CaseStatement]()
        var statements = [Statement]()
        var defaultCase: Block?
        func closeCase() {
            if let start = statements.first, let end = statements.last {
                let block = Block(
                    statements: statements,
                    range: start.range.lowerBound ..< end.range.upperBound
                )
                if defaultCase != nil {
                    defaultCase = block
                } else if var caseStatement = cases.last {
                    caseStatement.body = block
                    let range = caseStatement.range.lowerBound ..< end.range.upperBound
                    caseStatement.range = range
                    cases[cases.count - 1] = caseStatement
                }
            }
            statements.removeAll()
        }
        loop: while let token = first {
            switch token.type {
            case .rbrace:
                closeCase()
                break loop
            case .identifier("case"):
                if defaultCase != nil {
                    break loop
                }
                closeCase()
                let start = removeFirst()
                try cases.append(CaseStatement(
                    pattern: require(readExpressions(), as: "pattern"),
                    body: Block(statements: [], range: start.range),
                    range: start.range
                ))
            case .keyword(.else):
                closeCase()
                let start = removeFirst()
                defaultCase = Block(statements: [], range: start.range)
            case .linebreak:
                removeFirst()
            default:
                if cases.isEmpty, defaultCase == nil {
                    throw ParserError(.unexpectedToken(
                        token, expected: "case statement"
                    ))
                }
                try statements.append(require(readStatement(), as: "statement"))
            }
        }
        try requireToken(.rbrace)
        return .switchcase(condition, cases, else: defaultCase)
    }

    mutating func readOperand() throws -> Expression? {
        let start = self
        let token = readToken()
        var range = token.range
        let type: ExpressionType
        switch token.type {
        // TODO: should call be permitted here?
        case .lparen, .call:
            _ = readToken(.linebreak)
            let expression = try readExpressions(allowLinebreaks: true) ??
                Expression(
                    type: .tuple([]),
                    range: range.upperBound ..< nextToken.range.lowerBound
                )
            range = range.lowerBound ..< nextToken.range.upperBound
            try requireToken(.rparen, as: expression.type == .tuple([]) ?
                "expression" : TokenType.rparen.errorDescription)
            switch expression.type {
            case .tuple:
                type = expression.type
            default:
                type = .tuple([expression])
            }
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
            guard readToken(.call) else {
                type = .identifier(name)
                break
            }
            let expression = try readExpressions()
            let endToken = nextToken
            try requireToken(.rparen, as: "expression or \(TokenType.rparen.errorDescription)")
            // repackage function syntax as a lisp-style subexpression
            // TODO: should we support this as a distinct construct?
            var expressions = [Expression(
                type: .identifier(name),
                range: range
            )]
            if let expression = expression {
                if case let .tuple(params) = expression.type {
                    expressions += params
                } else {
                    expressions.append(expression)
                }
            }
            type = .tuple(expressions)
            range = range.lowerBound ..< endToken.range.upperBound
        case .keyword(.import):
            type = try .import(require(readExpressions(), as: "file path"))
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
        guard var lhs = try readOperand() else {
            return nil
        }
        while case let .infix(op) = nextToken.type,
              [.times, .divide, .modulo].contains(op)
        {
            removeFirst()
            let rhs = try require(readOperand(), as: "operand")
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return lhs
    }

    mutating func readSum() throws -> Expression? {
        guard var lhs = try readTerm() else {
            return nil
        }
        while case let .infix(op) = nextToken.type, [.plus, .minus].contains(op) {
            removeFirst()
            let rhs = try require(readTerm(), as: "operand")
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return lhs
    }

    mutating func readRange() throws -> Expression? {
        guard let lhs = try readSum() else {
            return nil
        }
        guard case .identifier("to") = nextToken.type else {
            return lhs
        }
        removeFirst()
        let rhs = try require(readSum(), as: "end value")
        return Expression(
            type: .infix(lhs, .to, rhs),
            range: lhs.range.lowerBound ..< rhs.range.upperBound
        )
    }

    mutating func readStep() throws -> Expression? {
        guard let lhs = try readRange() else {
            return nil
        }
        guard case .identifier("step") = nextToken.type else {
            return lhs
        }
        let start = self
        removeFirst()
        guard let rhs = try readSum() else {
            self = start
            return lhs
        }
        if case .identifier("step") = nextToken.type {
            // TODO: should multiple step values actually be permitted?
            // TODO: or is there a better error than "unexpected token"?
            throw ParserError(.unexpectedToken(nextToken, expected: nil))
        }
        return Expression(
            type: .infix(lhs, .step, rhs),
            range: lhs.range.lowerBound ..< rhs.range.upperBound
        )
    }

    mutating func readComparison() throws -> Expression? {
        let not = nextToken.type == .identifier("not") ? readToken() : nil
        guard var lhs = try readStep() else {
            return not.map {
                Expression(type: .identifier("not"), range: $0.range)
            }
        }
        if case let .infix(op) = nextToken.type, [
            .lt, .lte, .gt, .gte, .equal, .unequal,
        ].contains(op) {
            removeFirst()
            // TODO: should we allow chained comparison operators?
            let not = nextToken.type == .identifier("not") ? readToken() : nil
            var rhs = try require(readSum(), as: "operand")
            if let not = not {
                rhs = Expression(type: .tuple([
                    Expression(type: .identifier("not"), range: not.range),
                    rhs,
                ]), range: not.range.lowerBound ..< rhs.range.upperBound)
            }
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return not.map {
            let not = Expression(type: .identifier("not"), range: $0.range)
            return Expression(
                type: .tuple([not, lhs]),
                range: $0.range.lowerBound ..< lhs.range.upperBound
            )
        } ?? lhs
    }

    mutating func readBooleanLogic() throws -> Expression? {
        guard var lhs = try readComparison() else {
            return nil
        }
        while case let .identifier(name) = nextToken.type,
              let op = InfixOperator(rawValue: name),
              [.and, .or].contains(op)
        {
            removeFirst()
            let rhs = try require(readComparison(), as: "operand")
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return lhs
    }

    mutating func readExpression() throws -> Expression? {
        try readBooleanLogic()
    }

    mutating func readExpressions(allowLinebreaks: Bool = false) throws -> Expression? {
        var expressions = [Expression]()
        while var expression = try readExpression() {
            if case let .identifier(name) = expression.type, let block = try readBlock() {
                let range = expression.range.lowerBound ..< block.range.upperBound
                let identifier = Identifier(name: name, range: expression.range)
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

    mutating func readStatementType() throws -> StatementType? {
        if let statement = try readDefine() ?? readOption() ??
            readForLoop() ?? readIfElse() ?? readSwitch()
        {
            return statement
        }
        let start = self
        guard let identifier = readIdentifier() else {
            return try readExpressions().map { .expression($0) }
        }
        if case let .function(type, _) = Symbols.all[identifier.name],
           type.parameterType != .void, type.returnType != .void
        {
            // Not a command or read-only property getter
            self = start
            return try readExpressions().map { .expression($0) }
        }
        switch nextToken.type {
        case .infix, .dot, .identifier, .lbrace:
            self = start
            guard let expression = try readExpressions() else {
                return nil
            }
            switch expression.type {
            case var .tuple(expressions) where expressions[0].type == .identifier(identifier.name):
                expressions.removeFirst()
                let expression: Expression
                if expressions.count > 1 {
                    let range = expressions[0].range.lowerBound ..< expressions.last!.range.upperBound
                    expression = Expression(type: .tuple(expressions), range: range)
                } else {
                    expression = expressions[0]
                }
                return .command(identifier, expression)
            default:
                return .expression(expression)
            }
        // TODO: should call be treated differently here?
        case .number, .linebreak, .keyword, .hexColor, .prefix,
             .string, .rbrace, .lparen, .call, .rparen, .eof:
            return try .command(identifier, readExpressions())
        }
    }

    mutating func readStatement() throws -> Statement? {
        let start = self
        guard let type = try readStatementType() else {
            return nil
        }
        let end = start[start.index(before: startIndex)]
        let range = start.nextToken.range.lowerBound ..< end.range.upperBound
        return Statement(type: type, range: range)
    }

    mutating func readStatements() throws -> [Statement] {
        _ = readToken(.linebreak)
        var statements = [Statement]()
        while let statement = try readStatement() {
            statements.append(statement)
            switch nextToken.type {
            case .linebreak:
                removeFirst()
            case .eof, .rbrace:
                break
            default:
                throw ParserError(.unexpectedToken(nextToken, expected: nil))
            }
        }
        return statements
    }
}
