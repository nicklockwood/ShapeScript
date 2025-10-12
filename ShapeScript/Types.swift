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
    case any
    case color
    case texture
    case material
    case boolean
    case font
    case number
    case radians
    case halfturns
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
    case partialRange
    case bounds
    indirect case union(Set<ValueType>)
    indirect case tuple([ValueType])
    indirect case list(ValueType)
    indirect case object([String: ValueType])
}

extension ValueType: Comparable {
    private var sortIndex: Int {
        switch self {
        case .any: return 0
        case .color: return 1
        case .boolean: return 2
        case .number: return 3
        case .radians: return 4
        case .halfturns: return 5
        case .vector: return 6
        case .size: return 7
        case .rotation: return 8
        case .string: return 9
        case .text: return 10
        case .path: return 11
        case .mesh: return 12
        case .polygon: return 13
        case .point: return 14
        case .range: return 15
        case .texture: return 16
        case .font: return 17
        case .bounds: return 18
        case .union: return 19
        case .tuple: return 20
        case .list: return 21
        case .object: return 22
        case .material: return 23
        case .partialRange: return 24
        }
    }

    static func < (lhs: ValueType, rhs: ValueType) -> Bool {
        switch (lhs, rhs) {
        case let (.union(lhs), .union(rhs)):
            for (lhs, rhs) in zip(lhs.sorted(), rhs.sorted()) where lhs != rhs {
                return lhs < rhs
            }
            return lhs.count < rhs.count
        case let (.tuple(lhs), .tuple(rhs)):
            for (lhs, rhs) in zip(lhs, rhs) where lhs != rhs {
                return lhs < rhs
            }
            return lhs.count < rhs.count
        case let (.list(lhs), .list(rhs)):
            return lhs < rhs
        case let (lhs, rhs):
            switch lhs {
            case .any, .color, .texture, .material, .boolean, .font, .number,
                 .radians, .halfturns, .vector, .size, .rotation, .string, .text,
                 .path, .mesh, .polygon, .point, .range, .partialRange, .bounds,
                 .union, .tuple, .list, .object:
                return lhs.sortIndex < rhs.sortIndex
            }
        }
    }
}

extension ValueType {
    static let void: ValueType = .tuple([])
    static let sequence: ValueType = .union([.range, .list(.any)])
    static let anyObject: ValueType = .object(["*": .any])
    static let numberPair: ValueType = .tuple([.number, .number])
    static let colorOrTexture: ValueType = .union([.color, .texture])
    static let numberOrTexture: ValueType = .union([.number, .texture])
    static let numberOrVector: ValueType = .union([.number, .list(.number)])

    static func optional(_ type: ValueType) -> ValueType {
        .union([type, .void])
    }

    var isOptional: Bool {
        subtypes.contains(.void)
    }

    var subtypes: Set<ValueType> {
        switch self {
        case let .union(types):
            return types
        default:
            return [self]
        }
    }

    func simplified() -> ValueType {
        switch self {
        case let .union(types):
            let types = types.sorted()
            guard var result = types.first.map({ [$0] }) else {
                return self
            }
            for type in types.dropFirst() {
                result.removeAll(where: { $0.isSubtype(of: type) })
                if result.contains(where: { type.isSubtype(of: $0) }) {
                    continue
                }
                result.append(type)
            }
            return result.count == 1 ? result[0] : .union(Set(result))
        case .any, .color, .texture, .material, .boolean, .font, .number, .radians,
             .halfturns, .vector, .size, .rotation, .string, .text, .path, .mesh,
             .polygon, .point, .range, .partialRange, .bounds, .tuple, .list, .object:
            return self
        }
    }

    mutating func simplify() {
        self = simplified()
    }

    func union(_ type: ValueType) -> ValueType {
        switch (self, type) {
        case let (.union(lhs), .union(rhs)):
            return Self.union(lhs.union(rhs)).simplified()
        case let (.union(lhs), rhs):
            return Self.union(lhs.union([rhs])).simplified()
        case let (lhs, rhs):
            return Self.union([lhs, rhs]).simplified()
        }
    }

    mutating func formUnion(_ type: ValueType) {
        self = union(type)
    }

    mutating func narrow(with type: ValueType) {
        if self == .any {
            self = type
        } else if !isSubtype(of: type) {
            self = union(type)
        }
    }

    var errorDescription: String {
        switch self {
        case .color: return "color"
        case .texture: return "texture"
        case .material: return "material"
        case .font: return "font"
        case .boolean: return "boolean"
        case .number: return "number"
        case .radians: return "angle in radians"
        case .halfturns: return "angle in half-turns"
        case .vector, .list(.number): return "vector"
        case .size: return "size"
        case .rotation: return "rotation"
        case .string: return "string"
        case .text: return "text"
        case .path: return "path"
        case .mesh: return "mesh"
        case .polygon: return "polygon"
        case .point: return "point"
        case .range: return "range"
        case .partialRange: return "partial range"
        case .bounds: return "bounds"
        case .any: return "any"
        case let .tuple(types) where types.count == 1:
            return types[0].errorDescription
        case .tuple([]): return "empty tuple"
        case .tuple, .list: return "tuple"
        case let .union(types):
            return types.sorted().errorDescription
        case .object: return "object"
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
        case let (.tuple(lhs), .list(rhs)):
            return lhs.allSatisfy { $0.isSubtype(of: rhs) }
        default:
            return self == type
        }
    }
}

extension [ValueType] {
    var errorDescription: String {
        let types = map(\.errorDescription)
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

// MARK: Function types

typealias Getter = (EvaluationContext) throws -> Value
typealias Setter = (Value, EvaluationContext) throws -> Void
typealias Function = (Value, EvaluationContext) throws -> Value
typealias FunctionType = (parameterType: ValueType, returnType: ValueType)
typealias Parameters = [String: ValueType]

// MARK: Block Types

typealias Options = [String: ValueType]

struct BlockType {
    let symbols: Symbols
    let options: Options
    let childTypes: ValueType
    let returnType: ValueType

    init(_ symbols: Symbols, _ options: Options, _ childTypes: ValueType, _ returnType: ValueType) {
        self.symbols = options.mapValues { .placeholder($0) }.merging(symbols) { $1 }
        self.options = options
        self.childTypes = childTypes
        self.returnType = returnType
    }
}

extension BlockType {
    static let builder: Self = .init(.builder, [:], .path, .mesh)
    static let shape: Self = .init(.shape, [:], .void, .mesh)
    static let group: Self = .init(.group, [:], .mesh, .mesh)
    static let path: Self = .init(.path, [:], .union([.point, .path]), .path)
    static let pathShape: Self = .init(.pathShape, [:], .void, .path)
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
        case let .constant(value), let .option(value):
            return value.type
        }
    }
}

extension Value {
    var type: ValueType {
        switch self {
        case .color: return .color
        case .texture: return .texture
        case .material: return .material
        case .boolean: return .boolean
        case .number: return .number
        case .radians: return .radians
        case .halfturns: return .halfturns
        case .vector: return .vector
        case .size: return .size
        case .rotation: return .rotation
        case .string: return .string
        case .text: return .text
        case .path: return .path
        case .mesh: return .mesh
        case .polygon: return .polygon
        case .point: return .point
        case .bounds: return .bounds
        case let .range(range):
            return range.end == nil ? .partialRange : .range
        case let .tuple(values):
            return .tuple(values.map(\.type))
        case let .object(values):
            return .object(values.mapValues { $0.type })
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
        func numerify(
            _ values: [Value],
            as numericType: ValueType = .number,
            range: ClosedRange<Int>
        ) -> [Double]? {
            guard range.contains(values.count) else {
                return nil
            }
            let numbers = values.compactMap { $0.as(numericType)?.doubleValue }
            guard numbers.count == values.count else {
                return nil
            }
            return numbers
        }
        switch (self, type) {
        case let (.tuple(values), type) where values.count == 1:
            return try values[0].as(type, in: context)
        case _ where self.type.isSubtype(of: type):
            return self
        case let (_, .union(types)):
            if types.contains(where: { self.type.isSubtype(of: $0) }) {
                return self
            }
            var errors = [Error]()
            for type in types.sorted() {
                do {
                    if let value = try self.as(type, in: context) {
                        return value
                    }
                } catch {
                    errors.append(error)
                }
            }
            if let error = errors.first {
                throw error
            }
            return nil
        case let (_, .list(type)) where self.type.isSubtype(of: type):
            return [self]
        case let (_, .tuple(types)) where
            types.count == 1 || types.count > 1 && types[1].isOptional:
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
                do {
                    let url = try context?.resolveURL(for: name)
                    return .texture(.file(name: name, url: url ?? URL(fileURLWithPath: name), intensity: 1))
                } catch {
                    if URL(fileURLWithPath: name).pathExtension.isEmpty {
                        return nil
                    }
                    throw error
                }
            }
        case let (.tuple(values), .font) where values.contains { $0.type == .string }:
            fallthrough
        case (.string, .font):
            return try self.as(.string, in: context).flatMap {
                let name = $0.stringValue
                return try .string(context?.resolveFont(name) ?? name)
            }
        case (.string, .number):
            return Double(stringValue).map { .number($0) }
        case (.string, .boolean):
            switch stringValue.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            default: return nil
            }
        case (.string, .color):
            // TODO: support named colors
            return Color(hexString: stringValue).map { .color($0) }
        case (.boolean, .string), (.number, .string), (.texture(.file), .string):
            return .string(stringValue)
        case let (.tuple(values), .string):
            let stringifyable = values.allSatisfy { $0.isConvertible(to: .string) }
            return stringifyable ? .string(stringValue) : nil
        case let (.radians(value), .number):
            return .number(value)
        case let (.halfturns(value), .number):
            return .number(value)
        case let (.number(value), .radians):
            return .radians(value)
        case let (.number(value), .halfturns):
            return .halfturns(value)
        case let (.number(value), .color):
            return .color(Color(value, 1))
        case let (.number(value), .vector):
            return .vector(Vector(value, 0))
        case let (.number(value), .size):
            return .size(Vector(size: value))
        case let (.number(value), .rotation):
            return .rotation(Rotation(unchecked: [value]))
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
            return numerify(values, as: .halfturns, range: 1 ... 3).map {
                .rotation(Rotation(unchecked: $0))
            }
        case let (.color(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.vector(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.vector(value), .size):
            return .size(value)
        case let (.size(value), .list(.number)):
            return .tuple(value.components.map { .number($0) })
        case let (.size(value), .vector):
            return .vector(value)
        case let (.rotation(value), .list(.number)):
            return .tuple(value.rollYawPitchInHalfTurns.map { .number($0) })
        case let (.object(values), .list(type)):
            let values = try values.sorted(by: { $0.0 < $1.0 }).compactMap {
                try Value(.string($0), $1).as(type, in: context)
            }
            guard values.count == values.count else {
                return nil
            }
            return .tuple(values)
        case let (.object(values), .tuple(types)):
            let values = try zip(values.sorted(by: { $0.0 < $1.0 }), types).compactMap {
                try Value(.string($0.key), $0.value).as($1, in: context)
            }
            guard values.count == types.count else {
                return nil
            }
            return .tuple(values)
        case let (.object(values), type):
            // Note: fails if any member value is not found for the type
            // Does not necessarily fail if type fields are missing (they may be optional)
            var values = values
            for (key, value) in values {
                guard let type = type.memberType(key) ?? type.memberType("*"),
                      let value = try value.as(type, in: context)
                else {
                    return nil
                }
                values[key] = value
            }
            return type.instance(with: values)
        case let (_, .list(type)):
            return try self.as(type, in: context).map { [$0] }
        case let (.path(path), .mesh):
            return .mesh(Geometry(
                type: .path(path),
                name: context?.name,
                transform: context?.transform ?? .identity,
                material: .default, // not used for paths
                smoothing: nil,
                children: [],
                sourceLocation: context?.sourceLocation
            ))
        case let (.mesh(geometry), .path):
            switch geometry.type {
            case let .path(path):
                return .path(path.transformed(by: geometry.transform))
            case .cone, .cylinder, .sphere, .cube, .extrude, .lathe, .loft, .fill, .hull, .minkowski,
                 .union, .difference, .intersection, .xor, .stencil, .group, .mesh, .camera, .light:
                return nil
            }
        case let (.polygon(polygon), .path):
            return .path(Path(polygon))
        case let (.polygon(polygon), .mesh):
            return try Value.path(Path(polygon)).as(.mesh, in: context)
        default:
            return nil
        }
    }
}

extension Definition {
    func inferTypes(for params: inout Parameters, in context: EvaluationContext) {
        switch type {
        case let .expression(expression):
            expression.inferTypes(for: &params, in: context, with: .any)
        case let .function(_, block), let .block(block):
            block.inferTypes(for: &params, in: context)
        }
    }

    func staticSymbol(in context: EvaluationContext) throws -> Symbol {
        switch type {
        case let .expression(expression):
            return try .placeholder(expression.staticType(in: context))
        case .function, .block:
            return try evaluate(in: context)
        }
    }

    func staticType(in context: EvaluationContext) throws -> ValueType {
        try staticSymbol(in: context).type
    }
}

extension Expression {
    func inferTypes(
        for params: inout Parameters,
        in context: EvaluationContext,
        with type: ValueType
    ) {
        switch self.type {
        case let .identifier(name):
            if context.symbol(for: name) == nil {
                params[name]?.narrow(with: type)
            }
        case let .block(_, block):
            block.inferTypes(for: &params, in: context)
        case let .tuple(expressions):
            switch expressions.count {
            case 0:
                return
            case 1:
                expressions[0].inferTypes(for: &params, in: context, with: type)
            default:
                switch type {
                case let .tuple(types):
                    for (type, expression) in zip(types, expressions) {
                        expression.inferTypes(for: &params, in: context, with: type)
                    }
                case let .list(type):
                    for expression in expressions {
                        expression.inferTypes(for: &params, in: context, with: type)
                    }
                case .vector, .size, .color:
                    for expression in expressions {
                        expression.inferTypes(for: &params, in: context, with: .number)
                    }
                default:
                    // TODO: figure out types for other cases
                    for expression in expressions {
                        expression.inferTypes(for: &params, in: context, with: .any)
                    }
                }
            }
        case let .subscript(lhs, rhs):
            // TODO: can we use rhs type to infer something about the lhs?
            lhs.inferTypes(for: &params, in: context, with: .any)
            rhs.inferTypes(for: &params, in: context, with: .union([.number, .string]))
        case let .member(expression, _):
            // TODO: can we use member name to infer something about the type?
            expression.inferTypes(for: &params, in: context, with: .any)
        case let .import(expression):
            expression.inferTypes(for: &params, in: context, with: .string)
        case let .infix(lhs, .step, rhs):
            lhs.inferTypes(for: &params, in: context, with: .range)
            rhs.inferTypes(for: &params, in: context, with: .number)
        case let .prefix(.minus, rhs), let .prefix(.plus, rhs):
            rhs.inferTypes(for: &params, in: context, with: .numberOrVector)
        case let .infix(lhs, .minus, rhs),
             let .infix(lhs, .plus, rhs),
             let .infix(lhs, .times, rhs),
             let .infix(lhs, .divide, rhs),
             let .infix(lhs, .modulo, rhs):
            lhs.inferTypes(for: &params, in: context, with: .numberOrVector)
            rhs.inferTypes(for: &params, in: context, with: .numberOrVector)
        case let .infix(lhs, .in, rhs):
            lhs.inferTypes(for: &params, in: context, with: .any)
            rhs.inferTypes(for: &params, in: context, with: .any)
        case let .infix(lhs, .to, rhs),
             let .infix(lhs, .lt, rhs),
             let .infix(lhs, .gt, rhs),
             let .infix(lhs, .lte, rhs),
             let .infix(lhs, .gte, rhs):
            lhs.inferTypes(for: &params, in: context, with: .number)
            rhs.inferTypes(for: &params, in: context, with: .number)
        case let .infix(lhs, .and, rhs), let .infix(lhs, .or, rhs):
            lhs.inferTypes(for: &params, in: context, with: .boolean)
            rhs.inferTypes(for: &params, in: context, with: .boolean)
        case let .infix(lhs, .equal, rhs), let .infix(lhs, .unequal, rhs):
            // TODO: if lhs/rhs type is known, can we infer the rhs/lhs matches?
            lhs.inferTypes(for: &params, in: context, with: .any)
            rhs.inferTypes(for: &params, in: context, with: .any)
        case .number, .string, .color:
            break
        }
    }

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
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            switch symbol {
            case let .function((parameterType, _), _) where parameterType != .void:
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: 0,
                    expected: parameterType.errorDescription,
                    got: "block"
                ), at: block.range)
            case .block, .function, .property, .constant, .option, .placeholder:
                return symbol.type
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
                    case .property, .constant, .option, .placeholder, .function, .block:
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
        case let .prefix(.minus, rhs),
             let .prefix(.plus, rhs):
            if try rhs.staticType(in: context).isSubtype(of: .list(.any)) {
                return .list(.number)
            }
            return .number
        case let .infix(lhs, .minus, rhs),
             let .infix(lhs, .plus, rhs):
            if try lhs.staticType(in: context).isSubtype(of: .list(.any)) ||
                rhs.staticType(in: context).isSubtype(of: .list(.any))
            {
                return .list(.number)
            }
            return .number
        case let .infix(lhs, .times, _),
             let .infix(lhs, .divide, _),
             let .infix(lhs, .modulo, _):
            if try lhs.staticType(in: context).isSubtype(of: .list(.any)) {
                return .list(.number)
            }
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
             .infix(_, .or, _),
             .infix(_, .in, _):
            return .boolean
        case let .member(expression, member):
            let type = try expression.staticType(in: context)
            return type.memberType(member.name) ?? .any
        case let .subscript(lhs, _):
            switch try lhs.staticType(in: context) {
            case let .list(type):
                return type
            case let .tuple(types):
                return .union(Set(types))
            default:
                // TODO: other cases
                return .any
            }
        case let .import(expression):
            var file: String?
            switch expression.type {
            case let .string(string):
                file = string
            case let .tuple(expressions):
                if case let .string(string)? = expressions.last?.type {
                    file = string
                }
            default:
                break
            }
            switch file?.components(separatedBy: ".").last?.lowercased() ?? "" {
            case "txt": return .string
            case "shape", "json", "": return .any
            default: return .mesh
            }
        }
    }
}

extension Block {
    func inferTypes(for params: inout Parameters, in context: EvaluationContext) {
        context.pushScope { context in
            statements.gatherDefinitions(in: context)
            statements.forEach { $0.inferTypes(for: &params, in: context) }
        }
    }

    func staticType(in context: EvaluationContext) throws -> ValueType {
        var options: Options?
        return try staticType(in: context, options: &options)
    }

    func staticType(in context: EvaluationContext, options: inout Options?) throws -> ValueType {
        var types = [ValueType]()
        statements.gatherDefinitions(in: context)
        for statement in statements {
            if options != nil, case let .option(identifier, expression) = statement.type {
                let type = try expression.staticType(in: context)
                context.define(identifier.name, as: .placeholder(type))
                options?[identifier.name] = type
            } else {
                let type = try statement.staticType(in: context)
                if type != .void {
                    types.append(type)
                }
            }
        }
        switch types.count {
        case 0: return .void
        case 1: return types[0]
        default:
            return .list(types.dropFirst().reduce(types[0]) { $0.union($1) })
        }
    }
}

extension CaseStatement {
    func inferTypes(
        for params: inout Parameters,
        in context: EvaluationContext,
        with type: ValueType
    ) {
        context.pushScope { context in
            pattern.inferTypes(for: &params, in: context, with: type)
            body.inferTypes(for: &params, in: context)
        }
    }
}

extension Statement {
    func inferTypes(for params: inout Parameters, in context: EvaluationContext) {
        switch type {
        case let .command(identifier, expression):
            guard let expression, let symbol = context.symbol(for: identifier.name) else {
                // Probably an error, but gather types anyway in case it helps
                expression?.inferTypes(for: &params, in: context, with: .any)
                return
            }
            switch symbol {
            case let .function(type, _):
                expression.inferTypes(for: &params, in: context, with: type.parameterType)
            case let .property(type, _, _):
                expression.inferTypes(for: &params, in: context, with: type)
            case let .block(type, _):
                expression.inferTypes(for: &params, in: context, with: .list(type.childTypes))
            case .constant, .option, .placeholder:
                return
            }
        case let .expression(type):
            Expression(type: type, range: range).inferTypes(for: &params, in: context, with: .any)
        case let .define(identifier, definition):
            definition.inferTypes(for: &params, in: context)
            if let symbol = try? definition.staticSymbol(in: context) {
                context.define(identifier.name, as: symbol)
            }
        case let .forloop(_, in: expression, body):
            expression.inferTypes(for: &params, in: context, with: .sequence)
            body.inferTypes(for: &params, in: context)
        case let .ifelse(condition, body, else: elseBody):
            condition.inferTypes(for: &params, in: context, with: .boolean)
            body.inferTypes(for: &params, in: context)
            elseBody?.inferTypes(for: &params, in: context)
        case let .switchcase(condition, cases, else: elseBody):
            condition.inferTypes(for: &params, in: context, with: .any)
            let type = (try? condition.staticType(in: context)) ?? .any
            for caseStatement in cases {
                caseStatement.inferTypes(for: &params, in: context, with: type)
            }
            elseBody?.inferTypes(for: &params, in: context)
        case let .option(_, expression):
            expression.inferTypes(for: &params, in: context, with: .any)
        }
    }

    func staticType(in context: EvaluationContext) throws -> ValueType {
        switch type {
        case let .command(identifier, _):
            let name = identifier.name
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.commandSymbols),
                    at: identifier.range
                )
            }
            switch symbol {
            case .property:
                return .void
            case .function, .block, .constant, .option, .placeholder:
                return symbol.type
            }
        case let .expression(type):
            return try Expression(type: type, range: range).staticType(in: context)
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .define(identifier, definition):
            switch definition.type {
            case let .function(names, _):
                // In case of recursion
                let parameterType: ValueType = names.count == 1 ?
                    .any : .tuple(names.map { _ in .any })
                context.define(identifier.name, as: .function((parameterType, .any)) { _, _ in .void })
            case .block:
                // In case of recursion
                context.define(identifier.name, as: .block(.init([:], [:], .void, .any)) { _ in .void })
            case .expression:
                break
            }
            let symbol = try definition.staticSymbol(in: context)
            context.define(identifier.name, as: symbol)
            return .void
        case let .forloop(identifier, in: expression, block):
            var type: ValueType = .void
            try context.pushScope { context in
                if let identifier {
                    let elementType: ValueType
                    switch try expression.staticType(in: context) {
                    case let .tuple(types):
                        elementType = .union(Set(types))
                    case let .list(type):
                        elementType = type
                    case .range:
                        elementType = .number
                    default:
                        // TODO: can we do better here?
                        elementType = .any
                    }
                    context.define(identifier.name, as: .placeholder(elementType))
                }
                type = try block.staticType(in: context)
            }
            return .list(type)
        case let .ifelse(_, body, else: elseBody):
            var type: ValueType = .void
            try context.pushScope { context in
                type = try body.staticType(in: context)
            }
            if let elseBody {
                try context.pushScope { context in
                    try type.formUnion(elseBody.staticType(in: context))
                }
            } else {
                type.formUnion(.void)
            }
            return type
        case let .switchcase(_, cases, else: elseBody):
            var type: ValueType = .void
            for caseStatement in cases {
                try context.pushScope { context in
                    try type.formUnion(caseStatement.body.staticType(in: context))
                }
            }
            if let elseBody {
                try context.pushScope { context in
                    try type.formUnion(elseBody.staticType(in: context))
                }
            }
            return type
        }
    }
}

extension [Statement] {
    func gatherDefinitions(in context: EvaluationContext) {
        for statement in self {
            switch statement.type {
            case let .define(identifier, definition):
                if context.symbol(for: identifier.name) == nil {
                    let type = (try? definition.staticType(in: context)) ?? .any
                    context.define(identifier.name, as: .placeholder(type))
                }
            case .command, .option, .forloop, .ifelse, .switchcase, .expression:
                break
            }
        }
    }
}
