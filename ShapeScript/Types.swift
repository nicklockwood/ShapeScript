//
//  Types.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 18/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

// MARK: Types

enum ValueType: Hashable {
    case color
    case texture
    case boolean
    case font
    case number
    case vector
    case size
    case rotation
    case string
    case text
    case path
    case mesh
    case polygon
    case point
    case range
    case bounds
    case any
    indirect case union([ValueType])
    indirect case tuple([ValueType])
    indirect case list(ValueType)
}

extension ValueType {
    static let void: ValueType = .tuple([])
    static let numberPair: ValueType = .tuple([.number, .number])
    static let colorOrTexture: ValueType = .union([.color, .texture])

    var subtypes: [ValueType] {
        switch self {
        case let .union(types):
            return types
        default:
            return [self]
        }
    }

    var errorDescription: String {
        switch self {
        case .color: return "color"
        case .texture: return "texture"
        case .font: return "font"
        case .boolean: return "boolean"
        case .number: return "number"
        case .vector: return "vector"
        case .size: return "size"
        case .rotation: return "rotation"
        case .string: return "string"
        case .text: return "text"
        case .path: return "path"
        case .mesh: return "mesh"
        case .polygon: return "polygon"
        case .point: return "point"
        case .range: return "range"
        case .bounds: return "bounds"
        case .any: return "any"
        case let .tuple(types) where types.count == 1:
            return types[0].errorDescription
        case .tuple, .list: return "tuple"
        case let .union(types):
            return types.errorDescription
        }
    }

    func isSubtype(of type: ValueType) -> Bool {
        switch (self, type) {
        case (_, .any):
            return true
        case let (.union(lhs), rhs):
            return lhs.allSatisfy { $0.isSubtype(of: rhs) }
        case let (_, .union(types)):
            return types.contains(where: isSubtype(of:))
        case let (.list(lhs), .list(rhs)):
            return lhs.isSubtype(of: rhs)
        case let (.tuple(lhs), .tuple(rhs)):
            return lhs.count == rhs.count &&
                zip(lhs, rhs).allSatisfy { $0.isSubtype(of: $1) }
        default:
            return self == type
        }
    }

    func memberType(_ name: String) -> ValueType? {
        switch self {
        case let .list(type):
            return (name.isOrdinal || name == "last") ? type : type.memberType(name)
        case let .tuple(types):
            if let index = name.ordinalIndex {
                return types.indices.contains(index) ? types[index] : nil
            }
            return name == "last" ? types.last : Self.memberTypes[name]
        case let .union(types):
            let types = types.compactMap { $0.memberType(name) }
            return types.isEmpty ? nil : .union(types)
        case .color, .texture, .boolean, .font, .number, .vector, .size,
             .rotation, .string, .text, .path, .mesh, .polygon, .point, .range,
             .bounds, .any:
            return Self.memberTypes[name]
        }
    }

    private static let memberTypes: [String: ValueType] = [
        "x": .number,
        "y": .number,
        "z": .number,
        "width": .number,
        "height": .number,
        "depth": .number,
        "roll": .number,
        "yaw": .number,
        "pitch": .number,
        "red": .number,
        "green": .number,
        "blue": .number,
        "alpha": .number,
        "bounds": .bounds,
        "start": .number,
        "end": .number,
        "step": .number,
        "min": .number,
        "max": .number,
        "size": .size,
        "center": .vector,
        "count": .number,
    ]
}

extension Sequence where Element == ValueType {
    var errorDescription: String {
        let types = map { $0.errorDescription }
        switch types.count {
        case 1:
            return types[0]
        case 2:
            return "\(types[0]) or \(types[1])"
        default:
            return "\(types.dropLast().joined(separator: ", ")), or \(types.last!)"
        }
    }
}

// MARK: Block Types

typealias Options = [String: ValueType]

enum BlockType {
    case builder
    case shape
    case group
    case path
    case pathShape
    case text
    case user
    indirect case custom(BlockType?, Options)
}

extension BlockType {
    var options: Options {
        switch self {
        case let .custom(baseType, options):
            return (baseType?.options ?? [:]).merging(options) { $1 }
        case .builder, .group, .path, .shape, .pathShape, .text, .user:
            return [:]
        }
    }

    var childTypes: ValueType {
        switch self {
        case .builder: return .path
        case .group: return .mesh
        case .path: return .union([.point, .path])
        case .text: return .text
        case .shape, .pathShape, .user: return .void
        case let .custom(baseType, _):
            return baseType?.childTypes ?? .void
        }
    }

    var returnType: ValueType {
        switch self {
        case .builder, .group, .shape: return .mesh
        case .path, .pathShape: return .path
        case .text: return .list(.path)
        case .user: return .any
        case let .custom(baseType, _):
            return baseType?.returnType ?? .any
        }
    }

    var symbols: Symbols {
        switch self {
        case .shape: return .shape
        case .group: return .group
        case .builder: return .builder
        case .path: return .path
        case .pathShape, .text: return .pathShape
        case .user: return .user
        case let .custom(baseType, _):
            return baseType?.symbols ?? .node
        }
    }
}

// MARK: Inference

extension Symbol {
    var type: ValueType {
        switch self {
        case let .function(type, _):
            return type.returnType
        case let .block(type, _):
            return type.returnType
        case let .property(type, _, _), let .placeholder(type):
            return type
        case let .constant(value):
            return value.type
        }
    }
}

extension Value {
    var type: ValueType {
        switch self {
        case .color: return .color
        case .texture: return .texture
        case .boolean: return .boolean
        case .number: return .number
        case .vector: return .vector
        case .size: return .size
        case .rotation: return .rotation
        case .string: return .string
        case .text: return .text
        case .path: return .path
        case .mesh: return .mesh
        case .polygon: return .polygon
        case .point: return .point
        case .range: return .range
        case .bounds: return .bounds
        case let .tuple(values):
            return .tuple(values.map { $0.type })
        }
    }

    func isConvertible(to type: ValueType) -> Bool {
        self.as(type) != nil
    }

    func `as`(_ type: ValueType) -> Value? {
        try? self.as(type, in: nil)
    }

    /// Convert value to specified type. Returns nil if conversion is not possible.
    /// Note: context is used to verify that font or texture values exist. Errors are only thrown for
    /// non-existent font or texture and will never be thrown if context is nil.
    func `as`(_ type: ValueType, in context: EvaluationContext?) throws -> Value? {
        func numerify(_ values: [Value], range: ClosedRange<Int>) -> [Double]? {
            guard range.contains(values.count) else {
                return nil
            }
            let numbers = values.compactMap { $0.as(.number)?.doubleValue }
            guard numbers.count == values.count else {
                return nil
            }
            return numbers
        }
        switch (self, type) {
        case _ where self.type.isSubtype(of: type):
            return self
        case let (_, .union(types)):
            if types.contains(where: { self.type.isSubtype(of: $0) }) {
                return self
            }
            for type in types {
                if let value = try self.as(type, in: context) {
                    return value
                }
            }
            return nil
        case let (_, .list(type)) where self.type.isSubtype(of: type):
            switch self {
            case .tuple:
                return self
            default:
                return [self]
            }
        case let (_, .tuple(types)) where types.count == 1:
            return try self.as(types[0], in: context).map { [$0] }
        case (_, .text):
            return try self.as(.string, in: context).flatMap {
                .text(TextValue(string: $0.stringValue))
            }
        case let (.tuple(values), .texture) where values.contains { $0.type == .string }:
            fallthrough
        case (.string, .texture):
            return try self.as(.string, in: context).flatMap {
                let name = $0.stringValue
                if name.isEmpty {
                    return .texture(nil)
                }
                let url = try context?.resolveURL(for: name)
                return .texture(.file(name: name, url: url ?? URL(fileURLWithPath: name)))
            }
        case let (.tuple(values), .font) where values.contains { $0.type == .string }:
            fallthrough
        case (.string, .font):
            return try self.as(.string, in: context).flatMap {
                let name = $0.stringValue
                return try .string(context?.resolveFont(name) ?? name)
            }
        case (.boolean, .string), (.number, .string):
            return .string(stringValue)
        case let (.tuple(values), .string):
            let stringifyable = values.allSatisfy { $0.as(.string) != nil }
            return stringifyable ? .string(stringValue) : nil
        case let (.number(value), .color):
            return .color(Color(value, 1))
        case let (.number(value), .vector):
            return .vector(Vector(value, 0))
        case let (.number(value), .size):
            return .size(Vector(size: value))
        case let (.number(value), .rotation):
            return .rotation(Rotation(unchecked: [value]))
        case let (.tuple(values), type) where values.count == 1:
            return try values[0].as(type, in: context)
        case let (.tuple(values), .tuple(types)):
            guard values.count == types.count else {
                return nil
            }
            let values = try zip(values, types).compactMap {
                try $0.as($1, in: context)
            }
            guard values.count == types.count else {
                return nil
            }
            return .tuple(values)
        case let (.tuple(values), .color) where values.count == 2:
            guard case let .color(color)? = values[0].as(.color),
                  case let .number(alpha)? = values[1].as(.number)
            else {
                return nil
            }
            return .color(color.withAlpha(alpha))
        case let (.tuple(values), .list(.number)) where
            values.count == 2 && values[0].type == .color:
            if case let (.color(color), .number(alpha)) = (values[0], values[1]) {
                return .tuple(color.withAlpha(alpha).components.map { .number($0) })
            }
            return nil
        case let (.tuple(values), .list(type)):
            let result = try values.compactMap { try $0.as(type, in: context) }
            guard result.count == values.count else {
                return nil
            }
            return .tuple(result)
        case let (.tuple(values), .color):
            return numerify(values, range: 1 ... 4).map { .color(Color(unchecked: $0)) }
        case let (.tuple(values), .vector):
            return numerify(values, range: 1 ... 3).map { .vector(Vector($0)) }
        case let (.tuple(values), .size):
            return numerify(values, range: 1 ... 3).map { .size(Vector(size: $0)) }
        case let (.tuple(values), .rotation):
            return numerify(values, range: 1 ... 3).map {
                .rotation(Rotation(unchecked: $0))
            }
        case let (.color(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.vector(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.size(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.rotation(value), .list(.number)):
            return .tuple(value.rollYawPitchInHalfTurns.map { .number($0) })
        case let (_, .list(type)):
            return self.as(type).map { [$0] }
        default:
            return nil
        }
    }
}

extension Definition {
    func staticSymbol(in context: EvaluationContext) throws -> Symbol {
        switch type {
        case let .expression(expression):
            return try .placeholder(expression.staticType(in: context))
        case .function, .block:
            return try evaluate(in: context)
        }
    }
}

extension Expression {
    func staticType(in context: EvaluationContext) throws -> ValueType {
        switch type {
        case .number:
            return .number
        case .string:
            return .string
        case .color:
            return .color
        case let .identifier(name):
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            return symbol.type
        case let .block(identifier, block):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(.unknownSymbol(name, options: context.expressionSymbols), at: range)
            }
            switch symbol {
            case .block:
                return symbol.type
            case .property, .constant, .placeholder, .function((.void, _), _):
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 0),
                    at: block.range
                )
            case let .function((parameterType, _), _):
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: 0,
                    expected: parameterType.errorDescription,
                    got: "block"
                ), at: block.range)
            }
        case let .tuple(expressions):
            switch expressions.count {
            case 0:
                return .void
            case 1:
                return try expressions[0].staticType(in: context)
            default:
                if case let .identifier(name) = expressions[0].type {
                    guard let symbol = context.symbol(for: name) else {
                        throw RuntimeError(
                            .unknownSymbol(name, options: context.expressionSymbols),
                            at: range
                        )
                    }
                    switch symbol {
                    case let .function(type, _) where type.parameterType != .void:
                        return type.returnType
                    case let .block(type, _) where type.childTypes != .void:
                        return type.returnType
                    case .property, .constant, .placeholder, .function, .block:
                        break
                    }
                }
                var type: ValueType?
                for expression in expressions {
                    let staticType = try expression.staticType(in: context)
                    if type == nil {
                        type = staticType
                    } else if type != staticType {
                        type = nil
                        break
                    }
                }
                return .list(type ?? .any)
            }
        case .prefix(.minus, _),
             .prefix(.plus, _),
             .infix(_, .minus, _),
             .infix(_, .plus, _),
             .infix(_, .times, _),
             .infix(_, .divide, _):
            return .number
        case .infix(_, .to, _), .infix(_, .step, _):
            return .range
        case .infix(_, .equal, _),
             .infix(_, .unequal, _),
             .infix(_, .lt, _),
             .infix(_, .gt, _),
             .infix(_, .lte, _),
             .infix(_, .gte, _),
             .infix(_, .and, _),
             .infix(_, .or, _):
            return .boolean
        case let .member(expression, member):
            let type = try expression.staticType(in: context)
            return type.memberType(member.name) ?? .any
        case let .subexpression(expression):
            return try expression.staticType(in: context)
        }
    }
}
