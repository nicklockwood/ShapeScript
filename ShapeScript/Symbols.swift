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

enum Symbol {
    case command(ValueType, Setter)
    case function(ValueType, (Value, EvaluationContext) throws -> Value)
    case property(ValueType, Setter, Getter)
    case block(BlockType, Getter)
    case constant(Value)
}

extension Symbol {
    var errorDescription: String {
        switch self {
        case .command, .block: return "command"
        case .function: return "function"
        case .property: return "property"
        case .constant: return "constant"
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
    case paths // Hack to support multiple paths
    case mesh
    case tuple
    case point
    case pair // Hack to support common math functions
    case range
    case void
    case bounds
    case any
    indirect case union([ValueType])
}

extension ValueType {
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
        case .paths: return "path"
        case .mesh: return "mesh"
        case .tuple: return "tuple"
        case .point: return "point"
        case .pair: return "pair"
        case .range: return "range"
        case .void: return "void"
        case .bounds: return "bounds"
        case .any: return "any"
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

enum Value {
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
    case point(PathPoint)
    case tuple([Value])
    case range(RangeValue)
    case bounds(Bounds)
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
        case .boolean, .vector, .size, .rotation, .color, .texture,
             .number, .string, .text, .path, .mesh, .point, .bounds:
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
        case .boolean, .vector, .size, .rotation, .range, .tuple,
             .number, .string, .text, .path, .mesh, .point, .bounds:
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
        case .point: return .point
        case let .tuple(values) where values.count == 1:
            // TODO: find better solution for this.
            return values[0].type
        case .tuple: return .tuple
        case .range: return .range
        case .bounds: return .bounds
        }
    }

    func isConvertible(to type: ValueType) -> Bool {
        switch (self, type) {
        case (_, .any),
             (_, .tuple),
             (.boolean, .string),
             (.boolean, .text),
             (.number, .string),
             (.number, .text),
             (.number, .color),
             (.number, .vector),
             (.number, .size),
             (.number, .rotation),
             (.string, .text),
             (.string, .texture),
             (.string, .font):
            return true
        case let (_, .union(types)):
            return types.contains(where: isConvertible(to:))
        case let (.tuple(values), type) where values.count == 1:
            return values[0].isConvertible(to: type)
        case let (.tuple(values), .color) where values.count == 2:
            return values[0].isConvertible(to: .color) && values[1].type == .number
        case let (.tuple(values), .color),
             let (.tuple(values), .vector),
             let (.tuple(values), .size),
             let (.tuple(values), .rotation):
            return values.allSatisfy { $0.type == .number }
        case let (.tuple(values), .string),
             let (.tuple(values), .text),
             let (.tuple(values), .texture),
             let (.tuple(values), .font):
            return values.allSatisfy { $0.isConvertible(to: .string) }
        case let (.tuple(values), .void):
            return values.isEmpty
        default:
            return self.type == type
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
        case .path, .mesh:
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
