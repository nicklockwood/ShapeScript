//
//  Symbols.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 23/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

// MARK: Symbols

typealias Getter = (EvaluationContext) throws -> Value
typealias Setter = (Value, EvaluationContext) throws -> Void
typealias FunctionType = (parameterType: ValueType, returnType: ValueType)

enum Symbol {
    case command(ValueType, Setter)
    case function(FunctionType, (Value, EvaluationContext) throws -> Value)
    case property(ValueType, Setter, Getter)
    case block(BlockType, Getter)
    case constant(Value)
    case placeholder(ValueType)
}

extension Symbol {
    static func function(
        _ parameterType: ValueType,
        _ returnType: ValueType,
        _ fn: @escaping (Value, EvaluationContext) throws -> Value
    ) -> Symbol {
        .function((parameterType, returnType), fn)
    }

    var errorDescription: String {
        switch self {
        case .command, .block: return "command"
        case .function: return "function"
        case .property: return "property"
        case .constant: return "constant"
        case .placeholder: return "placeholder"
        }
    }

    var type: ValueType {
        switch self {
        case .command:
            return .void
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

typealias Symbols = [String: Symbol]

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

// MARK: Values

typealias Polygon = Euclid.Polygon

enum Value: Hashable {
    case color(Color)
    case texture(Texture?)
    case boolean(Bool)
    case number(Double)
    case vector(Vector)
    case size(Vector)
    case rotation(Rotation)
    case string(String)
    case text(TextValue)
    case path(Path)
    case mesh(Geometry)
    case polygon(Polygon)
    case point(PathPoint)
    case tuple([Value])
    case range(RangeValue)
    case bounds(Bounds)
}

extension Value: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension Value: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    init(floatLiteral value: Double) {
        self = .number(value)
    }

    init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension Value: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension Value: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Value...) {
        self.init(elements)
    }

    init(_ elements: [Value]) {
        self = .tuple(elements)
    }

    init(_ elements: Value...) {
        self = elements.count == 1 ? elements[0] : .tuple(elements)
    }
}

struct RangeValue: Hashable, Sequence {
    var start, end, step: Double

    init(from start: Double, to end: Double) {
        self.init(from: start, to: end, step: 1)!
    }

    init?(from start: Double, to end: Double, step: Double) {
        guard step != 0 else {
            return nil
        }
        self.start = start
        self.end = end
        self.step = step
    }

    func makeIterator() -> StrideThrough<Double>.Iterator {
        stride(from: start, through: end, by: step).makeIterator()
    }
}

struct TextValue: Hashable {
    var string: String
    var font: String?
    var color: Color?
    var linespacing: Double?
}

extension Value {
    static let void: Value = .tuple([])

    static func angle(_ value: Angle) -> Value {
        .number(value.radians / .pi)
    }

    static func colorOrTexture(_ value: MaterialProperty) -> Value {
        switch value {
        case let .color(color):
            return .color(color)
        case let .texture(texture):
            return .texture(texture)
        }
    }

    var value: AnyHashable {
        switch self {
        case let .color(color): return color
        case let .texture(texture):
            return texture.map { $0 as AnyHashable } ?? AnyHashable("")
        case let .boolean(boolean): return boolean
        case let .number(number): return number
        case let .vector(vector): return vector
        case let .size(size): return size
        case let .rotation(rotation): return rotation
        case let .string(string): return string
        case let .text(text): return text
        case let .path(path): return path
        case let .mesh(mesh): return mesh
        case let .polygon(polygon): return polygon
        case let .point(point): return point
        case let .tuple(values) where values.count == 1: return values[0].value
        case let .tuple(values): return values.map { $0.value }
        case let .range(range): return range
        case let .bounds(bounds): return bounds
        }
    }

    var doubleValue: Double {
        assert(value is Double)
        return value as? Double ?? 0
    }

    var doublesValue: [Double] {
        switch self {
        case let .tuple(values):
            return values.map { $0.doubleValue }
        case let .number(value):
            return [value]
        default:
            assertionFailure()
            return []
        }
    }

    var angleValue: Angle {
        .radians(doubleValue * .pi)
    }

    var intValue: Int {
        Int(truncating: doubleValue as NSNumber)
    }

    var boolValue: Bool {
        assert(value is Bool)
        return value as? Bool ?? false
    }

    var stringValue: String {
        switch self {
        case let .tuple(values):
            var spaceNeeded = false
            return values.map {
                switch $0 {
                case let .string(string):
                    spaceNeeded = false
                    return string
                case let value:
                    defer { spaceNeeded = true }
                    let string = value.stringValue
                    return spaceNeeded ? " \(string)" : string
                }
            }.joined()
        default:
            assert(value is Loggable)
            return (value as? Loggable)?.logDescription ?? ""
        }
    }

    var tupleValue: [AnyHashable] {
        if case let .tuple(values) = self {
            return values.map { $0.value }
        }
        return [value]
    }

    var sequenceValue: AnySequence<Value>? {
        switch self {
        case let .range(range):
            return AnySequence(range.lazy.map { .number($0) })
        case let .tuple(values):
            if values.count == 1, let value = values.first?.sequenceValue {
                return value
            }
            return AnySequence(values)
        case .boolean, .vector, .size, .rotation, .color, .texture, .number,
             .string, .text, .path, .mesh, .polygon, .point, .bounds:
            return nil
        }
    }

    var vectorValue: Vector {
        assert(value is Vector)
        return value as? Vector ?? .zero
    }

    var rotationValue: Rotation {
        assert(value is Rotation)
        return value as? Rotation ?? .identity
    }

    var colorValue: Color {
        assert(value is Color)
        return value as? Color ?? .white
    }

    var colorOrTextureValue: MaterialProperty? {
        switch self {
        case let .color(color):
            return .color(color)
        case let .texture(texture):
            return texture.map { .texture($0) }
        case .boolean, .vector, .size, .rotation, .range, .tuple, .number,
             .string, .text, .path, .mesh, .polygon, .point, .bounds:
            return nil
        }
    }

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

    var members: [String] {
        switch self {
        case .vector, .point:
            return ["x", "y", "z"]
        case .size:
            return ["width", "height", "depth"]
        case .rotation:
            return ["roll", "yaw", "pitch"]
        case .color:
            return ["red", "green", "blue", "alpha"]
        case let .tuple(values):
            var members = Array(String.ordinals(upTo: values.count))
            if !members.isEmpty {
                members.append("last")
            }
            members += ["count", "allButFirst", "allButLast"]
            guard values.allSatisfy({ $0.type == .number }) else {
                guard values.allSatisfy({ $0.type == .path }) else {
                    if values.count == 1 {
                        members += values[0].members
                    }
                    return members
                }
                return members + ["bounds"]
            }
            if (1 ... 4).contains(values.count) {
                members += ["red", "green", "blue", "alpha"]
                if values.count < 4 {
                    members += [
                        "x", "y", "z",
                        "width", "height", "depth",
                        "roll", "yaw", "pitch",
                    ]
                }
            }
            return members
        case .range:
            return ["start", "end", "step"]
        case .path, .mesh, .polygon:
            return ["bounds"]
        case .bounds:
            return ["min", "max", "size", "center", "width", "height", "depth"]
        case .texture, .boolean, .number, .string, .text:
            return []
        }
    }

    subscript(_ name: String) -> Value? {
        switch self {
        case let .vector(vector):
            switch name {
            case "x": return .number(vector.x)
            case "y": return .number(vector.y)
            case "z": return .number(vector.z)
            default: return nil
            }
        case let .point(point):
            return Value.vector(point.position)[name]
        case let .size(size):
            switch name {
            case "width": return .number(size.x)
            case "height": return .number(size.y)
            case "depth": return .number(size.z)
            default: return nil
            }
        case let .rotation(rotation):
            switch name {
            case "roll": return .number(rotation.roll.radians / .pi)
            case "yaw": return .number(rotation.yaw.radians / .pi)
            case "pitch": return .number(rotation.pitch.radians / .pi)
            default: return nil
            }
        case let .color(color):
            switch name {
            case "red": return .number(color.r)
            case "green": return .number(color.g)
            case "blue": return .number(color.b)
            case "alpha": return .number(color.a)
            default: return nil
            }
        case let .tuple(values):
            if values.count == 1, case .tuple = values[0] {
                return values[0][name]
            }
            switch name {
            case "last":
                return values.last
            case "allButFirst":
                return .tuple(Array(values.dropFirst()))
            case "allButLast":
                return .tuple(Array(values.dropLast()))
            case "count":
                return .number(Double(values.count))
            default:
                if let index = name.ordinalIndex {
                    return index < values.count ? values[index] : nil
                }
            }
            guard values.allSatisfy({ $0.type == .number }) else {
                guard values.allSatisfy({ $0.type == .path }) else {
                    if values.count == 1 {
                        return values[0][name]
                    }
                    return nil
                }
                let values = values.compactMap { $0.value as? Path }
                switch name {
                case "bounds":
                    return .bounds(values.bounds)
                default:
                    return nil
                }
            }
            let values = values.map { $0.doubleValue }
            switch name {
            case "x", "y", "z":
                return values.count < 4 ? Value.vector(Vector(values))[name] : nil
            case "width", "height", "depth":
                return values.count < 4 ? Value.size(Vector(size: values))[name] : nil
            case "roll", "yaw", "pitch":
                return Rotation(rollYawPitchInHalfTurns: values).map(Value.rotation)?[name]
            case "red", "green", "blue", "alpha":
                return Color(values).map(Value.color)?[name]
            default:
                return nil
            }
        case let .range(range):
            switch name {
            case "start": return .number(range.start)
            case "end": return .number(range.end)
            case "step": return .number(range.step)
            default: return nil
            }
        case let .path(path):
            switch name {
            case "bounds": return .bounds(path.bounds)
            default: return nil
            }
        case let .mesh(mesh):
            switch name {
            case "bounds": return .bounds(mesh.bounds)
            default: return nil
            }
        case let .polygon(polygon):
            switch name {
            case "bounds": return .bounds(polygon.bounds)
            default: return nil
            }
        case let .bounds(bounds):
            switch name {
            case "min": return .vector(bounds.min)
            case "max": return .vector(bounds.max)
            case "size": return .size(bounds.size)
            case "center": return .vector(bounds.center)
            case "width": return .number(bounds.size.x)
            case "height": return .number(bounds.size.y)
            case "depth": return .number(bounds.size.z)
            default: return nil
            }
        case .boolean, .texture, .number, .string, .text:
            return nil
        }
    }
}
