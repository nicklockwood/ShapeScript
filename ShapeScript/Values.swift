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
        let end = self.end + (step > 0 ? 1 : -1) * 0.0000001
        return stride(from: start, through: end, by: step).makeIterator()
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
            return AnySequence(values.sorted(by: {
                $0.0 < $1.0
            }).map {
                [.string($0), $1]
            })
        case .boolean, .vector, .size, .rotation, .color, .texture, .number,
             .radians, .halfturns, .string, .text, .path, .mesh, .polygon,
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
             .radians, .halfturns, .string, .text, .path, .mesh, .polygon,
             .point, .bounds, .object:
            return nil
        }
    }

    var members: [String] {
        switch self {
        case .vector:
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
            if let vector = self.as(.vector) {
                members += vector.members
            }
            if let size = self.as(.size) {
                members += size.members
            }
            if let rotation = self.as(.rotation) {
                members += rotation.members
            }
            if values.count == 1 {
                return members + values[0].members
            }
            if let string = self.as(.string) {
                members += string.members
            }
            if !members.contains("alpha"), let color = self.as(.color) {
                members += color.members
            }
            return members
        case .range:
            return ["start", "end", "step"]
        case let .mesh(geometry):
            var members = ["name", "bounds"]
            if geometry.hasMesh {
                members.append("polygons")
            }
            return members
        case .path:
            return ["bounds", "points"]
        case .polygon:
            return ["bounds", "center", "points"]
        case .point:
            return ["x", "y", "z", "position", "color", "isCurved"]
        case .bounds:
            return ["min", "max", "size", "center", "width", "height", "depth"]
        case .string:
            var members = ["lines", "words", "characters"]
            if let color = self.as(.color) {
                members += color.members
            }
            return members
        case .text:
            return ["string", "font", "color", "linespacing"]
        case let .object(values):
            return values.keys.sorted()
        case .texture, .boolean, .number, .radians, .halfturns:
            return []
        }
    }

    subscript(name: String) -> Value? {
        self[name, { false }]
    }

    subscript(
        name: String,
        isCancelled: @escaping Mesh.CancellationHandler
    ) -> Value? {
        switch self {
        case let .vector(vector):
            switch name {
            case "x": return .number(vector.x)
            case "y": return .number(vector.y)
            case "z": return .number(vector.z)
            default: return nil
            }
        case let .size(size):
            switch name {
            case "width": return .number(size.x)
            case "height": return .number(size.y)
            case "depth": return .number(size.z)
            default: return nil
            }
        case let .rotation(rotation):
            switch name {
            case "roll": return .halfturns(rotation.roll.halfturns)
            case "yaw": return .halfturns(rotation.yaw.halfturns)
            case "pitch": return .halfturns(rotation.pitch.halfturns)
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
                return self.as(.string)?[name, isCancelled]
            case "x", "y", "z":
                return self.as(.vector)?[name, isCancelled]
            case "width", "height", "depth":
                return self.as(.size)?[name, isCancelled]
            case "roll", "yaw", "pitch":
                return self.as(.rotation)?[name, isCancelled]
            case "red", "green", "blue", "alpha":
                return self.as(.color)?[name, isCancelled]
            default:
                if let index = name.ordinalIndex {
                    return index < values.count ? values[index] : nil
                }
                if values.count == 1 {
                    return values[0][name, isCancelled]
                }
                return nil
            }
        case let .range(range):
            switch name {
            case "start": return .number(range.start)
            case "end": return .number(range.end)
            case "step": return .number(range.step)
            default: return nil
            }
        case let .mesh(geometry):
            switch name {
            case "name":
                return .string(geometry.name ?? "")
            case "bounds":
                return .bounds(geometry.exactBounds(with: geometry.transform) {
                    !isCancelled()
                })
            case "polygons" where geometry.hasMesh:
                _ = geometry.build { !isCancelled() }
                let polygons = (geometry.mesh?.polygons ?? [])
                    .transformed(by: geometry.transform)
                return .tuple(polygons.map { .polygon($0) })
            default:
                return nil
            }
        case let .path(path):
            switch name {
            case "bounds": return .bounds(path.bounds)
            case "points": return .tuple(path.points.map { .point($0) })
            default: return nil
            }
        case let .polygon(polygon):
            switch name {
            case "bounds":
                return .bounds(polygon.bounds)
            case "center":
                return .vector(polygon.center)
            case "points":
                return .tuple(polygon.vertices.map { .point(PathPoint($0)) })
            default:
                return nil
            }
        case let .point(point):
            switch name {
            case "position":
                return .vector(point.position)
            case "isCurved":
                return .boolean(point.isCurved)
            case "color":
                return point.color.map { .color($0) } ?? .void
            default:
                return Value.vector(point.position)[name, isCancelled]
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
            case "red", "green", "blue", "alpha":
                return self.as(.color)?[name, isCancelled]
            default:
                return nil
            }
        case let .text(text):
            switch name {
            case "string":
                return .string(text.string)
            case "font":
                return text.font.map { .string($0) } ?? .void
            case "color":
                return text.color.map { .color($0) } ?? .void
            case "linespacing":
                return text.linespacing.map { .number($0) } ?? .void
            default:
                return nil
            }
        case let .object(values):
            return values[name]
        case .boolean, .texture, .number, .radians, .halfturns:
            return nil
        }
    }
}
