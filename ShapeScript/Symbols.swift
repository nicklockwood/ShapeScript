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

    static func command(
        _ parameterType: ValueType,
        _ fn: @escaping Setter
    ) -> Symbol {
        .function(parameterType, .void) {
            try fn($0, $1)
            return .void
        }
    }

    var errorDescription: String {
        switch self {
        case .block, .function((_, .void), _): return "command"
        case .function: return "function"
        case .property: return "property"
        case .constant: return "constant"
        case .placeholder: return "placeholder"
        }
    }
}

typealias Symbols = [String: Symbol]

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
    case object([String: Value])
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

extension Value: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, Value)...) {
        self.init(Dictionary(elements) { $1 })
    }

    init(_ elements: [String: Value]) {
        self = .object(elements)
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
        case let .object(values): return values
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
        case let .object(values):
            let values: [Value] = values.sorted(by: { $0.0 < $1.0 }).map { [.string($0), $1] }
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
             .string, .text, .path, .mesh, .polygon, .point, .bounds, .object:
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
            if isConvertible(to: .string) {
                members += ["lines", "words", "characters"]
            }
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
        case .string:
            return ["lines", "words", "characters"]
        case let .object(values):
            return values.keys.sorted()
        case .texture, .boolean, .number, .text:
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
            case "lines", "words", "characters":
                return self.as(.string)?[name]
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
        case let .string(string):
            switch name {
            case "lines":
                return .tuple(string
                    .split { $0.isNewline }
                    .map { .string("\($0)") })
            case "words":
                return .tuple(string
                    .split(omittingEmptySubsequences: true) {
                        $0.isWhitespace || $0.isNewline
                    }
                    .map { .string("\($0)") })
            case "characters":
                return .tuple(string.map { .string("\($0)") })
            default: return nil
            }
        case let .object(values):
            return values[name]
        case .boolean, .texture, .number, .text:
            return nil
        }
    }
}
