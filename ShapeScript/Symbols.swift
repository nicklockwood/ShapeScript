//
//  Symbols.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 23/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

typealias Symbols = [String: Symbol]

enum Symbol {
    case function(FunctionType, Function)
    case property(ValueType, Setter, Getter)
    case block(BlockType, Getter)
    case constant(Value)
    case placeholder(ValueType)
    case option(Value)
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
        case .block, .function((_, .void), _): return "command"
        case .function: return "function"
        case .property: return "property"
        case .constant: return "constant"
        case .option: return "option"
        case .placeholder: return "placeholder"
        }
    }
}
