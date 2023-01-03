//
//  Parser.swift
//  SCADLib
//
//  Created by Nick Lockwood on 03/01/2023.
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
    case define(Identifier, Definition)
    indirect case command(Identifier, [Argument], Statement?)
    indirect case forloop(Identifier?, in: Expression, Statement)
    indirect case ifelse(Expression, Statement, else: Statement?)
    case `import`(Expression)
    case block([Statement])
}

public struct Statement: Equatable {
    public let type: StatementType
    public let range: SourceRange
}

public struct Parameter: Equatable {
    public let name: Identifier
    public let expression: Expression?
    public var range: SourceRange {
        name.range.lowerBound ..<
            (expression?.range.upperBound ?? name.range.upperBound)
    }
}

public struct Argument: Equatable {
    public let name: Identifier?
    public let expression: Expression
    public var range: SourceRange {
        (name?.range.lowerBound ?? expression.range.lowerBound)
            ..< expression.range.upperBound
    }
}

public extension Array where Element == Argument {
    var namedArguments: [String: Argument] {
        .init(compactMap {
            guard let identifier = $0.name else {
                return nil
            }
            return (identifier.name, $0)
        }) { $1 }
    }

    var positionalArguments: [Argument] {
        filter { $0.name == nil }
    }
}

public enum DefinitionType: Equatable {
    case module([Parameter], Block)
    case function([Parameter], Expression)
    case expression(Expression)
}

public struct Definition: Equatable {
    public let type: DefinitionType
    public var range: SourceRange {
        switch type {
        case let .module(_, block):
            return block.range
        case let .function(_, expression),
             let .expression(expression):
            return expression.range
        }
    }
}

public enum ExpressionType: Equatable {
    case undefined
    case number(Double)
    case boolean(Bool)
    case string(String)
    case identifier(String)
    case vector([Expression])
    indirect case call(Expression, [Argument])
    indirect case prefix(PrefixOperator, Expression)
    indirect case infix(Expression, InfixOperator, Expression)
    indirect case member(Expression, Identifier)
    indirect case range(Expression, Expression?, Expression)
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
        case let .unexpectedToken(token, expected) where [
            TokenType.rparen.errorDescription,
            "operator",
        ].contains(expected):
            let string: String
            switch token.type {
            case let .identifier(name):
                string = name
            case let .infix(op):
                string = op.rawValue
            case let .prefix(op):
                string = op.rawValue
            case .assign:
                string = "="
            default:
                return nil
            }
            let options = InfixOperator.allCases.map { $0.rawValue }
            return Self.alternatives[string.lowercased()] ??
                string.bestMatches(in: options).first
        case .unexpectedToken, .custom:
            return nil
        }
    }

    var hint: String? {
        switch type {
        case let .unexpectedToken(_, expected: expected?):
            if let suggestion = suggestion {
                return "Did you mean '\(suggestion)'?"
            }
            return "Expected \(expected)."
        case .unexpectedToken(_, expected: nil):
            return nil
        case let .custom(_, hint: hint, _):
            return hint
        }
    }
}

// MARK: Implementation

private extension ParserError {
    static let alternatives: [String: String] = [
        "and": "&&",
        "or": "||",
        "not": "!",
        "mod": "%",
        "equals": "=",
        "eq": "=",
        "is": "=",
        "=": "==",
    ]
}

private extension TokenType {
    var errorDescription: String {
        switch self {
        case let .identifier(name): return "token '\(name)'"
        case let .keyword(keyword): return "keyword '\(keyword)'"
        case let .infix(op): return "operator '\(op.rawValue)'"
        case let .prefix(op): return "prefix operator '\(op.rawValue)'"
        case .number: return "numeric literal"
        case .string: return "text literal"
        case .lbrace: return "opening brace"
        case .rbrace: return "closing brace"
        case .lparen: return "opening paren"
        case .rparen: return "closing paren"
        case .lbracket: return "opening bracket"
        case .rbracket: return "closing bracket"
        case .dot: return "dot"
        case .comma: return "comma"
        case .colon: return "colon"
        case .assign: return "assignment operator"
        case .terminator: return "semicolon"
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

    mutating func readCommas() -> Bool {
        var commasFound = false
        while readToken(.comma) {
            commasFound = true
        }
        return commasFound
    }

    mutating func readExpressions() throws -> [Expression] {
        _ = readCommas()
        var expressions = [Expression]()
        while let expression = try readExpression() {
            expressions.append(expression)
            if !readCommas() {
                break
            }
        }
        return expressions
    }

    mutating func readArguments() throws -> [Argument] {
        _ = readCommas()
        var arguments = [Argument]()
        while var expression = try readExpression() {
            var name: Identifier?
            if case let .identifier(n) = expression.type, readToken(.assign) {
                name = Identifier(name: n, range: expression.range)
                expression = try require(readExpression(), as: "expression")
            }
            arguments.append(Argument(name: name, expression: expression))
            if !readCommas() {
                break
            }
        }
        return arguments
    }

    // TODO: named parameters
    mutating func readParameters() -> [Parameter] {
        _ = readCommas()
        var parameters = [Parameter]()
        while let identifier = readIdentifier() {
            parameters.append(Parameter(
                name: identifier,
                expression: nil
            ))
            if !readCommas() {
                break
            }
        }
        return parameters
    }

    mutating func readDefineOrCommand() throws -> StatementType? {
        let start = self
        guard let identifier = readIdentifier() else {
            return nil
        }
        switch readToken().type {
        case .assign:
            let expression = try require(readExpression(), as: "expression")
            try requireToken(.terminator)
            return .define(identifier, .init(type: .expression(expression)))
        case .lparen:
            let arguments = try readArguments()
            try requireToken(.rparen)
            let start = self
            var next: Statement?
            if let statementType = try readBlockOrCommand() {
                let end = start[start.index(before: startIndex)]
                let range = start.nextToken.range.lowerBound ..< end.range.upperBound
                next = Statement(type: statementType, range: range)
            } else {
                try requireToken(.terminator)
            }
            return .command(identifier, arguments, next)
        default:
            self = start
            return nil
        }
    }

    mutating func readBlockOrCommand() throws -> StatementType? {
        if let block = try readBlock() {
            return .block(block.statements)
        }
        guard let identifier = readIdentifier() else {
            return nil
        }
        try requireToken(.lparen)
        let arguments = try readArguments()
        try requireToken(.rparen)
        let start = self
        var next: Statement?
        if let statementType = try readBlockOrCommand() {
            let end = start[start.index(before: startIndex)]
            let range = start.nextToken.range.lowerBound ..< end.range.upperBound
            next = Statement(type: statementType, range: range)
        } else {
            try requireToken(.terminator)
        }
        return .command(identifier, arguments, next)
    }

    mutating func readFunction() throws -> StatementType? {
        guard readToken(.keyword(.function)) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "function name")
        try requireToken(.lparen)
        let parameters = readParameters()
        try requireToken(.rparen)
        try requireToken(.assign)
        let expression = try require(readExpression(), as: "expression")
        try requireToken(.terminator)
        return .define(name, .init(type: .function(parameters, expression)))
    }

    mutating func readModule() throws -> StatementType? {
        guard readToken(.keyword(.module)) else {
            return nil
        }
        let name = try require(readIdentifier(), as: "module name")
        try requireToken(.lparen)
        let parameters = readParameters()
        try requireToken(.rparen)
        let block = try require(readBlock(), as: "module body")
        return .define(name, .init(type: .module(parameters, block)))
    }

    mutating func readForLoop() throws -> StatementType? {
        guard readToken(.keyword(.for)) ||
            readToken(.identifier("intersection_for"))
        else {
            return nil
        }
        try requireToken(.lparen)
        let identifier = readIdentifier()
        let expression: Expression
        if identifier != nil {
            try requireToken(.assign)
            expression = try require(readExpression(), as: "range expression")
        } else {
            let endToken = nextToken
            expression = try readExpression() ?? Expression(
                type: .undefined,
                range: endToken.range.lowerBound ..< endToken.range.lowerBound
            )
        }
        try requireToken(.rparen)
        let body = try require(readStatement(), as: "loop body")
        return .forloop(identifier, in: expression, body)
    }

    mutating func readIfElse() throws -> StatementType? {
        guard readToken(.keyword(.if)) else {
            return nil
        }
        try requireToken(.lparen)
        let condition = try require(readExpression(), as: "condition")
        try requireToken(.rparen)
        let body = try require(readStatement(), as: "if body")
        let start = self
        guard readToken(.keyword(.else)) else {
            self = start
            return .ifelse(condition, body, else: nil)
        }
        if let elseBody = try readStatement() {
            return .ifelse(condition, body, else: elseBody)
        }
        throw ParserError(.unexpectedToken(nextToken, expected: "else body"))
    }

    mutating func readImport() throws -> StatementType? {
        nil
//        guard readToken(.keyword(.import)) else {
//            return nil
//        }
//        return try .import(require(readExpressions(), as: "file path"))
    }

    mutating func readOperand() throws -> Expression? {
        let start = self
        let token = readToken()
        var range = token.range
        let type: ExpressionType
        switch token.type {
        case .lparen:
            let expression = try require(readExpression(), as: "expression")
            range = range.lowerBound ..< nextToken.range.upperBound
            try requireToken(.rparen, as: TokenType.rparen.errorDescription)
            type = expression.type
        case .lbracket:
            let expressions = try readExpressions()
            guard expressions.count == 1,
                  let lhs = expressions.first,
                  readToken(.colon)
            else {
                let endToken = nextToken
                try requireToken(.rbracket)
                type = .vector(expressions)
                range = range.lowerBound ..< endToken.range.upperBound
                break
            }
            var increment: Expression?
            var rhs = try require(readExpression(), as: "upper bound or increment")
            if readToken(.colon) {
                increment = rhs
                rhs = try require(readExpression(), as: "upper bound")
            }
            let endToken = nextToken
            try requireToken(.rbracket)
            type = .range(lhs, increment, rhs)
            range = range.lowerBound ..< endToken.range.upperBound
        case let .prefix(op):
            let operand = try require(readOperand(), as: "operand")
            range = range.lowerBound ..< operand.range.upperBound
            type = .prefix(op, operand)
        case let .number(number):
            type = .number(number)
        case let .string(string):
            type = .string(string)
        case let .identifier(name):
            guard readToken(.lparen) else {
                type = .identifier(name)
                break
            }
            let arguments = try readArguments()
            let endToken = nextToken
            try requireToken(.rparen, as: "expression or \(TokenType.rparen.errorDescription)")
            type = .call(
                Expression(type: .identifier(name), range: range),
                arguments
            )
            range = range.lowerBound ..< endToken.range.upperBound
        case .keyword(.false):
            type = .boolean(false)
        case .keyword(.true):
            type = .boolean(true)
        case .keyword(.undef):
            type = .undefined
        case .dot, .colon, .comma, .terminator, .keyword, .infix, .assign,
             .lbrace, .rbrace, .rparen, .rbracket, .eof:
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
              [.times, .divide, .modulo, .exponent].contains(op)
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

    mutating func readComparison() throws -> Expression? {
        guard var lhs = try readSum() else {
            return nil
        }
        while case let .infix(op) = nextToken.type, [
            .lt, .lte, .gt, .gte, .equal, .unequal,
        ].contains(op) {
            removeFirst()
            let rhs = try require(readSum(), as: "operand")
            lhs = Expression(
                type: .infix(lhs, op, rhs),
                range: lhs.range.lowerBound ..< rhs.range.upperBound
            )
        }
        return lhs
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

    mutating func readStatement() throws -> Statement? {
        let start = self
        if let statement = try readForLoop() ?? readIfElse() ?? readImport() ?? readDefineOrCommand() ?? readFunction(
        ) ??
            readModule()
        {
            let end = start[start.index(before: startIndex)]
            let range = start.nextToken.range.lowerBound ..< end.range.upperBound
            return Statement(type: statement, range: range)
        }
        if let block = try readBlock() {
            return Statement(type: .block(block.statements), range: block.range)
        }
        return nil
    }

    mutating func readStatements() throws -> [Statement] {
        var statements = [Statement]()
        while let statement = try readStatement() {
            statements.append(statement)
        }
        switch nextToken.type {
        case .eof, .terminator, .rbrace:
            return statements
        default:
            throw ParserError(.unexpectedToken(nextToken, expected: nil))
        }
    }
}
