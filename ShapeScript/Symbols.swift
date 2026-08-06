//
//  Symbols.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 23/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

typealias Symbols = [String: SymbolPair]

struct SymbolPair: Sendable {
    var getter: Symbol
    var setter: Symbol

    init(getter: Symbol, setter: Symbol? = nil) {
        self.getter = getter
        self.setter = setter ?? getter
    }
}

enum Symbol: Sendable {
    case function(FunctionType, Function)
    case property(ValueType, Setter, Getter)
    case block(BlockType, Getter)
    case constant(Value)
    case placeholder(ValueType)
    case option(Value)
}

extension SymbolPair {
    static func function(
        _ parameterType: ValueType,
        _ returnType: ValueType,
        _ fn: @escaping Function
    ) -> SymbolPair {
        .init(getter: .function(parameterType, returnType, fn))
    }

    static func command(_ parameterType: ValueType, _ fn: @escaping Setter) -> SymbolPair {
        .init(getter: .command(parameterType, fn))
    }

    static func getter(_ type: ValueType, _ fn: @escaping Getter) -> SymbolPair {
        .init(getter: .getter(type, fn))
    }

    static func property(_ type: ValueType, _ setter: @escaping Setter, _ getter: @escaping Getter) -> SymbolPair {
        .init(getter: .property(type, setter, getter))
    }

    static func block(_ type: BlockType, _ getter: @escaping Getter) -> SymbolPair {
        .init(getter: .block(type, getter))
    }

    static func constant(_ value: Value) -> SymbolPair {
        .init(getter: .constant(value))
    }

    static func placeholder(_ type: ValueType) -> SymbolPair {
        .init(getter: .placeholder(type))
    }

    static func option(_ value: Value) -> SymbolPair {
        .init(getter: .option(value))
    }

    var isCommand: Bool {
        setter.isCommand
    }

    var isExpression: Bool {
        getter.isExpression
    }
}

extension Symbol {
    static func function(
        _ parameterType: ValueType,
        _ returnType: ValueType,
        _ fn: @escaping Function
    ) -> Symbol {
        .function((parameterType, returnType), fn)
    }

    static func command(_ parameterType: ValueType, _ fn: @escaping Setter) -> Symbol {
        .function(parameterType, .void) {
            try fn($0, $1)
            return .void
        }
    }

    static func getter(_ type: ValueType, _ fn: @escaping Getter) -> Symbol {
        .function(.void, type) { try fn($1) }
    }

    var errorDescription: String {
        switch self {
        case .block, .function((_, .void), _): "command"
        case .function: "function"
        case .property: "property"
        case .constant: "constant"
        case .option: "option"
        case .placeholder: "placeholder"
        }
    }

    var isCommand: Bool {
        switch self {
        case .function, .property, .block, .placeholder:
            true
        case .constant, .option:
            false
        }
    }

    var isExpression: Bool {
        switch self {
        case let .function(type, _) where type.returnType == .void:
            false
        case .function, .property, .block, .constant, .option, .placeholder:
            true
        }
    }
}
