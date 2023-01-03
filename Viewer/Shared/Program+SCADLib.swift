//
//  Program+SCADLib.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 04/01/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import SCADLib
import ShapeScript

extension ShapeScript.Program {
    init(_ program: SCADLib.Program) {
        self.init(
            source: program.source,
            statements: program.statements.map { .init($0, asMesh: true) }
        )
    }
}

extension ShapeScript.Statement {
    init(_ statement: SCADLib.Statement, asMesh: Bool) {
        let type: ShapeScript.StatementType
        switch statement.type {
        case let .command(identifier, arguments, next):
            let positional = arguments.positionalArguments
            switch identifier.name {
            case "echo":
                type = .command(
                    Identifier(name: "print", range: identifier.range),
                    Expression(type: .tuple(arguments.map {
                        .init($0.expression)
                    }), range: statement.range)
                )
            case "translate":
                // TODO: handle asMesh = false
                var options: [ShapeScript.Statement] = []
                if let v = arguments.namedArguments["v"] ?? positional.first {
                    options.append(.init(type: .command(
                        Identifier(name: "translate", range: identifier.range),
                        Expression(v.expression)
                    ), range: v.range))
                }
                options += next.map { .init($0, asMesh: asMesh) } ?? []
                type = .expression(.block(
                    Identifier(name: "group", range: statement.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "rotate":
                // TODO: handle asMesh = false
                var options: [ShapeScript.Statement] = []
                // TODO: support axis/angle rotation
                if let a = arguments.namedArguments["a"] ?? positional.first {
                    options.append(.init(type: .define(
                        Identifier(name: "a", range: a.range),
                        Definition(type: .expression(
                            Expression(a.expression).scaled(by: -1 / 180)
                        ))
                    ), range: a.range))
                    options.append(.init(type: .command(
                        Identifier(name: "rotate", range: identifier.range),
                        Expression(type: .tuple([
                            Expression(type: .member(
                                Expression(type: .identifier("a"), range: a.range),
                                Identifier(name: "z", range: a.range)
                            ), range: a.range),
                            Expression(type: .member(
                                Expression(type: .identifier("a"), range: a.range),
                                Identifier(name: "y", range: a.range)
                            ), range: a.range),
                            Expression(type: .member(
                                Expression(type: .identifier("a"), range: a.range),
                                Identifier(name: "x", range: a.range)
                            ), range: a.range),
                        ]), range: a.range)
                    ), range: a.range))
                }
                options += next.map { .init($0, asMesh: asMesh) } ?? []
                type = .expression(.block(
                    Identifier(name: "group", range: statement.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "scale":
                // TODO: handle asMesh = false
                var options: [ShapeScript.Statement] = []
                if let v = arguments.namedArguments["v"] ?? positional.first {
                    options.append(.init(type: .command(
                        Identifier(name: "scale", range: identifier.range),
                        Expression(v.expression)
                    ), range: v.range))
                }
                options += next.map { .init($0, asMesh: asMesh) } ?? []
                type = .expression(.block(
                    Identifier(name: "group", range: statement.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "resize":
                preconditionFailure("TODO")
            case "mirror":
                preconditionFailure("TODO")
            case "multmatrix":
                preconditionFailure("TODO")
            case "color":
                // TODO: handle asMesh = false
                // TODO: support hex and named colors
                var options: [ShapeScript.Statement] = []
                let alpha = arguments.namedArguments["alpha"] ??
                    (positional.count > 1 ? positional[1] : nil)
                if let c = arguments.namedArguments["c"] ?? positional.first {
                    var color = Expression(c.expression)
                    if let alpha = alpha {
                        color = Expression(type: .tuple([
                            color, Expression(alpha.expression),
                        ]), range: alpha.range)
                    }
                    options.append(.init(type: .command(
                        Identifier(name: "color", range: identifier.range),
                        color
                    ), range: c.range))
                } else if let alpha = alpha {
                    options.append(.init(type: .command(
                        Identifier(name: "opacity", range: alpha.range),
                        Expression(alpha.expression)
                    ), range: alpha.range))
                }
                options += next.map { .init($0, asMesh: asMesh) } ?? []
                type = .expression(.block(
                    Identifier(name: "group", range: statement.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "offset":
                preconditionFailure("TODO")
            case "hull", "group", "union", "intersection", "difference":
                // TODO: handle asMesh = false properly
                let children = next.map { .init($0, asMesh: true) } ?? []
                type = .expression(.block(
                    Identifier(name: identifier.name, range: identifier.range),
                    Block(statements: children, range: arguments.range)
                ))
            case "minowski":
                preconditionFailure("TODO")
            case "circle":
                var options: [ShapeScript.Statement] = []
                if let d = arguments.namedArguments["d"] {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: d.range),
                        Expression(d.expression)
                    ), range: d.range))
                } else if let r = arguments.namedArguments["r"] ?? positional.first {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: r.range),
                        Expression(r.expression).scaled(by: 2)
                    ), range: r.range))
                } else {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: statement.range),
                        Expression(type: .number(2), range: statement.range)
                    ), range: statement.range))
                }
                if let fn = arguments.namedArguments["$fn"] {
                    options.append(Statement(type: .command(
                        Identifier(name: "detail", range: fn.range),
                        Expression(fn.expression)
                    ), range: fn.range))
                }
                let path = StatementType.expression(.block(
                    Identifier(name: "circle", range: identifier.range),
                    Block(statements: options, range: arguments.range)
                ))
                type = asMesh ? .expression(.block(
                    Identifier(name: "extrude", range: identifier.range),
                    Block(statements: [
                        .init(type: path, range: statement.range),
                    ], range: statement.range)
                )) : path
            case "square":
                var options: [ShapeScript.Statement] = []
                if let size = arguments.namedArguments["size"] ?? positional.first {
                    // Note: ShapeScript accepts a tuple of 1-3 for size
                    // but OpenSCAD only allows a tuple of size 2
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: size.range),
                        Expression(size.expression)
                    ), range: size.range))
                }
                let range = statement.range
                let position = Statement(type: .command(
                    Identifier(name: "position", range: range),
                    Expression(type: .tuple([
                        Expression(type: .infix(
                            Expression(type: .member(
                                Expression(type: .identifier("size"), range: range),
                                Identifier(name: "width", range: range)
                            ), range: range),
                            .divide,
                            Expression(type: .number(2), range: range)
                        ), range: range),
                        Expression(type: .infix(
                            Expression(type: .member(
                                Expression(type: .identifier("size"), range: range),
                                Identifier(name: "width", range: range)
                            ), range: range),
                            .divide,
                            Expression(type: .number(2), range: range)
                        ), range: range),
                    ]), range: range)
                ), range: range)
                if let center = arguments.namedArguments["center"] ??
                    (positional.count > 1 ? positional[1] : nil)
                {
                    options.append(Statement(
                        type: .ifelse(
                            Expression(type: .infix(
                                Expression(center.expression),
                                .equal,
                                Expression(
                                    type: .identifier("false"),
                                    range: position.range
                                )
                            ), range: position.range),
                            Block(statements: [
                                position,
                            ], range: position.range),
                            else: nil
                        ),
                        range: position.range
                    ))
                } else {
                    options.append(position)
                }
                type = .expression(.block(
                    Identifier(name: "square", range: identifier.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "linear_extrude":
                let range = statement.range
                var options: [ShapeScript.Statement] = []
                let height = (
                    arguments.namedArguments["height"] ?? positional.first
                ).map { Expression($0.expression) } ?? Expression(
                    type: .number(100),
                    range: range
                )
                options.append(.init(type: .command(
                    Identifier(name: "size", range: statement.range),
                    Expression(type: .tuple([
                        Expression(type: .number(1), range: statement.range),
                        Expression(type: .number(1), range: statement.range),
                        height,
                    ]), range: statement.range)
                ), range: statement.range))
                let position = Statement(type: .command(
                    Identifier(name: "position", range: range),
                    Expression(type: .tuple([
                        Expression(type: .number(0), range: statement.range),
                        Expression(type: .number(0), range: statement.range),
                        height.scaled(by: 0.5),
                    ]), range: statement.range)
                ), range: range)
                if let center = arguments.namedArguments["center"] {
                    options.append(Statement(
                        type: .ifelse(
                            Expression(type: .infix(
                                Expression(center.expression),
                                .equal,
                                Expression(
                                    type: .identifier("false"),
                                    range: position.range
                                )
                            ), range: position.range),
                            Block(statements: [
                                position,
                            ], range: position.range),
                            else: nil
                        ),
                        range: position.range
                    ))
                } else {
                    options.append(position)
                }
                if let twist = arguments.namedArguments["twist"] {
                    options.append(.init(type: .command(
                        Identifier(name: "twist", range: twist.range),
                        Expression(twist.expression).scaled(by: 1 / 180)
                    ), range: statement.range))
                }
                options += next.map { .init($0, asMesh: false) } ?? []
                if let slices = arguments.namedArguments["slices"] {
                    options.append(.init(type: .command(
                        Identifier(name: "detail", range: slices.range),
                        Expression(slices.expression).scaled(by: 4)
                    ), range: statement.range))
                }
                type = .expression(.block(
                    Identifier(name: "extrude", range: statement.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "cube":
                var options: [ShapeScript.Statement] = []
                if let size = arguments.namedArguments["size"] ?? positional.first {
                    // Note: ShapeScript accepts a tuple of 1-3 for size
                    // but OpenSCAD only allows a tuple of size 3
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: size.range),
                        Expression(size.expression)
                    ), range: size.range))
                }
                let range = statement.range
                let position = Statement(type: .command(
                    Identifier(name: "position", range: range),
                    Expression(type: .infix(
                        Expression(type: .identifier("size"), range: range),
                        .divide,
                        Expression(type: .number(2), range: range)
                    ), range: range)
                ), range: range)
                if let center = arguments.namedArguments["center"] ??
                    (positional.count > 1 ? positional[1] : nil)
                {
                    options.append(Statement(
                        type: .ifelse(
                            Expression(type: .infix(
                                Expression(center.expression),
                                .equal,
                                Expression(
                                    type: .identifier("false"),
                                    range: position.range
                                )
                            ), range: position.range),
                            Block(statements: [
                                position,
                            ], range: position.range),
                            else: nil
                        ),
                        range: position.range
                    ))
                } else {
                    options.append(position)
                }
                type = .expression(.block(
                    Identifier(name: "cube", range: identifier.range),
                    Block(statements: options, range: arguments.range)
                ))
            case "sphere":
                var options: [ShapeScript.Statement] = []
                if let d = arguments.namedArguments["d"] {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: d.range),
                        Expression(d.expression)
                    ), range: d.range))
                } else if let r = arguments.namedArguments["r"] ?? positional.first {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: r.range),
                        Expression(r.expression).scaled(by: 2)
                    ), range: r.range))
                } else {
                    options.append(Statement(type: .command(
                        Identifier(name: "size", range: statement.range),
                        Expression(type: .number(2), range: statement.range)
                    ), range: statement.range))
                }
                if let fn = arguments.namedArguments["$fn"] {
                    options.append(Statement(type: .command(
                        Identifier(name: "detail", range: fn.range),
                        Expression(fn.expression)
                    ), range: fn.range))
                }
                type = .expression(.block(
                    Identifier(name: "sphere", range: identifier.range),
                    Block(statements: options, range: arguments.range)
                ))
            default:
                var options: [ShapeScript.Statement] = []
                for (i, argument) in positional.enumerated() {
                    options.append(Statement(type: .command(
                        Identifier(name: "param\(i)", range: argument.range),
                        Expression(argument.expression)
                    ), range: argument.range))
                }
                type = .expression(.block(
                    Identifier(identifier),
                    Block(statements: options, range: arguments.range)
                ))
            }
        case let .define(identifier, definition):
            switch identifier.name {
            case "$fn":
                let expression: ShapeScript.Expression
                switch definition.type {
                case let .expression(exp):
                    expression = .init(exp)
                default:
                    preconditionFailure("TODO")
                }
                type = .command(
                    .init(name: "detail", range: identifier.range),
                    .init(type: .tuple([expression]), range: expression.range)
                )
            default:
                type = .define(.init(identifier), .init(definition))
            }
        case let .forloop(index, in: range, body):
            type = .forloop(
                index.map { Identifier($0) },
                in: Expression(range),
                Block(body, asMesh: asMesh)
            )
        case let .ifelse(condition, body, else: elseBody):
            type = .ifelse(
                Expression(condition),
                Block(body, asMesh: asMesh),
                else: elseBody.map { Block($0, asMesh: asMesh) }
            )
        case .import:
            preconditionFailure()
        case let .block(statements):
            assert(asMesh, "Use [Statement](_:asMesh:) instead")
            let statements = statements.map {
                ShapeScript.Statement($0, asMesh: asMesh)
            }
            type = .expression(.block(
                Identifier(name: "group", range: statement.range),
                Block(statements: statements, range: statement.range)
            ))
        }
        self.init(type: type, range: statement.range)
    }
}

extension Array where Element == ShapeScript.Statement {
    init(_ statement: SCADLib.Statement, asMesh: Bool) {
        switch statement.type {
        case let .block(statements):
            self = statements.flatMap { [Element]($0, asMesh: asMesh) }
        case let .command(identifier, arguments, next):
            let positional = arguments.positionalArguments
            switch identifier.name {
            case "group":
                self = next.map { [Element]($0, asMesh: asMesh) } ?? []
            case "translate":
                var options: [ShapeScript.Statement] = []
                if let v = arguments.namedArguments["v"] ?? positional.first {
                    options.append(.init(type: .command(
                        Identifier(name: "translate", range: identifier.range),
                        Expression(v.expression)
                    ), range: v.range))
                }
                options += next.map { .init($0, asMesh: asMesh) } ?? []
                self = options
            default:
                self = [.init(statement, asMesh: asMesh)]
            }
        default:
            self = [.init(statement, asMesh: asMesh)]
        }
    }
}

extension Array where Element == SCADLib.Argument {
    var range: SourceRange {
        first.map {
            $0.range.lowerBound ..< last!.range.upperBound
        } ?? ("".startIndex ..< "".endIndex) // TODO: find better solution
    }
}

extension ShapeScript.Block {
    init(_ statement: SCADLib.Statement, asMesh: Bool) {
        switch statement.type {
        case let .block(statements):
            self.init(
                statements: statements.map { .init($0, asMesh: asMesh) },
                range: statement.range
            )
        default:
            self.init(
                statements: [.init(statement, asMesh: asMesh)],
                range: statement.range
            )
        }
    }
}

extension ShapeScript.Definition {
    init(_ definition: SCADLib.Definition) {
        let type: ShapeScript.DefinitionType
        switch definition.type {
        case let .expression(expression):
            type = .expression(.init(expression))
        case let .module(parameters, block):
            let options = parameters.enumerated().flatMap { i, param in
                let expression: ShapeScript.Expression = param.expression.map {
                    .init($0)
                } ?? Expression(
                    type: .string(""),
                    range: param.range
                )
                return [
                    Statement(
                        type: .option(Identifier(
                            name: "param\(i)",
                            range: param.range
                        ), expression),
                        range: param.range
                    ),
                    Statement(
                        type: .option(.init(param.name), Expression(
                            type: .identifier("param\(i)"),
                            range: param.range
                        )),
                        range: param.range
                    ),
                ]
            }
            type = .block(Block(statements: options + block.statements.map {
                ShapeScript.Statement($0, asMesh: true)
            }, range: block.range))
        case .function:
            preconditionFailure("TODO")
        }
        self.init(type: type)
    }
}

extension ShapeScript.Expression {
    init(arguments: [SCADLib.Argument]) {
        self.init(
            type: .tuple(arguments.map { .init($0.expression) }),
            range: arguments.range
        )
    }

    init(_ expression: SCADLib.Expression) {
        let type: ShapeScript.ExpressionType
        switch expression.type {
        case .undefined:
            type = .tuple([])
        case let .number(value):
            type = .number(value)
        case let .boolean(value):
            type = .identifier(value ? "true" : "false")
        case let .string(value):
            type = .string(value)
        case let .identifier(name):
            type = .identifier(name.mangled())
        case let .vector(expressions):
            type = .tuple(expressions.map(Expression.init))
        case let .call(fn, arguments):
            var expressions = arguments.map { Expression($0.expression) }
            if case let .identifier(name) = fn.type {
                switch name {
                case "sin", "cos", "tan":
                    expressions = expressions.map {
                        $0.scaled(by: .pi / 180)
                    }
                default:
                    break
                }
            }
            type = .tuple([Expression(fn)] + expressions)
        case let .prefix(op, rhs):
            switch op {
            case .plus, .minus, .not:
                type = .prefix(
                    ShapeScript.PrefixOperator(rawValue: op.rawValue)!,
                    Expression(rhs)
                )
            }
        case let .infix(lhs, op, rhs):
            guard let op = ShapeScript.InfixOperator(rawValue: op.rawValue) else {
                preconditionFailure()
            }
            type = .infix(.init(lhs), op, .init(rhs))
        case .member:
            preconditionFailure()
        case let .range(start, step, end):
            let range = ExpressionType.infix(.init(start), .to, .init(end))
            if let step = step {
                type = .infix(
                    Expression(type: range, range: expression.range),
                    .step,
                    Expression(step)
                )
            } else {
                type = range
            }
        }
        self.init(type: type, range: expression.range)
    }

    func scaled(by factor: Double) -> Self {
        let type: ShapeScript.ExpressionType
        switch self.type {
        case let .number(value):
            type = .number(value * factor)
        case let .tuple(expressions):
            type = .tuple(expressions.map { $0.scaled(by: factor) })
        default:
            type = .infix(self, .times, Self(
                type: .number(factor),
                range: range
            ))
        }
        return .init(type: type, range: range)
    }
}

extension String {
    func mangled() -> String {
        var name = replacingOccurrences(of: "$", with: "dollar_")
        if name.hasPrefix("_") {
            name = "underscore\(name)"
        }
        switch name {
        case "sign":
            break
        default:
            if stdlibSymbols.contains(name) {
                name = "\(name)_"
            }
        }
        return name
    }
}

extension ShapeScript.Identifier {
    init(_ identifier: SCADLib.Identifier) {
        self.init(name: identifier.name.mangled(), range: identifier.range)
    }
}
