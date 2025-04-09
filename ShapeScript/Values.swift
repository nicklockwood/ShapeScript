//
//  Values.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 26/10/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

typealias Polygon = Euclid.Polygon

enum Value: Hashable {
    case color(Color)
    case texture(Texture?)
    case material(Material)
    case boolean(Bool)
    case number(Double)
    case radians(Double)
    case halfturns(Double)
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

struct RangeValue: Hashable {
    var start: Double
    var end, step: Double?

    init(from start: Double, to end: Double?) {
        self.start = start
        self.end = end
    }
}

extension RangeValue {
    init?(from start: Double, to end: Double?, step: Double?) {
        guard step != 0 else {
            return nil
        }
        self.init(from: start, to: end)
        self.step = step
    }

    var stepIsPositive: Bool { step ?? 1 > 0 }
    private static let epsilon: Double = 0.0000001
    private var adjustedEnd: Double? {
        end.map { $0 + (stepIsPositive ? 1 : -1) * Self.epsilon }
    }

    var stride: StrideThrough<Double>? {
        adjustedEnd.map { Swift.stride(from: start, through: $0, by: step ?? 1) }
    }

    func contains(_ value: Double) -> Bool {
        if stepIsPositive ? value < start : value > start { return false }
        if let step = step,
           case let remainder = abs((value - start).remainder(dividingBy: step)),
           remainder > Self.epsilon, abs(step) - remainder > Self.epsilon
        {
            return false
        }
        guard let adjustedEnd = adjustedEnd else { return true }
        return stepIsPositive ? value <= adjustedEnd : value >= adjustedEnd
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

    static func colorOrTexture(_ value: MaterialProperty) -> Value {
        switch value {
        case let .color(color):
            return .color(color)
        case let .texture(texture):
            return .texture(texture)
        }
    }

    static func numberOrTexture(_ value: MaterialProperty) -> Value {
        switch value {
        case let .color(color):
            return .number(color.r)
        case let .texture(texture):
            return .texture(texture)
        }
    }

    var errorDescription: String {
        switch self {
        case let .mesh(geometry):
            switch geometry.type {
            case .path: return "path"
            case .cone: return "cone"
            case .cylinder: return "cylinder"
            case .sphere: return "sphere"
            case .cube: return "cube"
            case .group, .extrude, .lathe, .loft, .fill, .hull, .union,
                 .difference, .intersection, .xor, .stencil, .mesh:
                return "mesh"
            case .camera: return "camera"
            case .light: return "light"
            }
        default:
            return type.errorDescription
        }
    }

    var value: AnyHashable {
        switch self {
        case let .color(color): return color
        case let .texture(texture):
            return texture.map { $0 as AnyHashable } ?? AnyHashable("")
        case let .material(material): return material
        case let .boolean(boolean): return boolean
        case let .number(number): return number
        case let .radians(radians): return radians
        case let .halfturns(halfturns): return halfturns
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
        case let .object(values): return values.mapValues { $0.value }
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

    var angleValue: Angle? {
        switch self {
        case let .radians(radians):
            return .radians(radians)
        case let .halfturns(halfturns):
            return .halfturns(halfturns)
        default:
            assertionFailure()
            return nil
        }
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

    var objectValue: [String: AnyHashable] {
        value as? [String: AnyHashable] ?? [:]
    }

    var sequenceValue: AnySequence<Value>? {
        switch self {
        case let .range(range):
            return range.stride.map { AnySequence($0.lazy.map { .number($0) }) }
        case let .tuple(values):
            if values.count == 1, let first = values.first {
                if case .range = first {
                    // Special case to handle unbounded ranges
                    return first.sequenceValue
                } else if let value = first.sequenceValue {
                    return value
                }
            }
            return AnySequence(values)
        case let .object(values):
            return AnySequence(values.sorted(by: {
                $0.0 < $1.0
            }).map {
                [.string($0), $1]
            })
        case .boolean, .vector, .size, .rotation, .color, .texture, .material,
             .number, .radians, .halfturns, .string, .text, .path, .mesh, .polygon,
             .point, .bounds:
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
             .radians, .halfturns, .string, .text, .path, .material, .mesh,
             .polygon, .point, .bounds, .object:
            return nil
        }
    }

    var numberOrTextureValue: MaterialProperty? {
        switch self {
        case let .number(value):
            return .color(.init(value, value))
        case let .texture(texture):
            return texture.map { .texture($0) }
        case .boolean, .vector, .size, .rotation, .range, .tuple, .color,
             .radians, .halfturns, .string, .text, .path, .material, .mesh,
             .polygon, .point, .bounds, .object:
            return nil
        }
    }
}
