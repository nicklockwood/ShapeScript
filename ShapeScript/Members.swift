//
//  Members.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 30/10/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

extension ValueType {
    /// Create an instance from a dictionary of memberwise values
    /// Note: this function assumes values have already been validated and cast to correct types
    func instance(with values: [String: Value]) -> Value? {
        switch self {
        case .object:
            return .object(values)
        case .material:
            return .material(.init(
                opacity: values["opacity"]?.numberOrTextureValue,
                albedo: (values["color"] ?? values["texture"])?.colorOrTextureValue,
                normals: values["normals"]?.value as? Texture,
                metallicity: values["metallicity"]?.numberOrTextureValue,
                roughness: values["roughness"]?.numberOrTextureValue,
                glow: values["glow"]?.colorOrTextureValue
            ))
        case .color, .texture, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .rotation, .string, .text, .path, .mesh, .polygon,
             .point, .range, .partialRange, .bounds, .union, .tuple, .list, .any:
            return nil
        }
    }

    var memberTypes: [String: ValueType] {
        switch self {
        case let .object(members):
            return members
        case .material:
            return [
                "color": .color,
                "opacity": .number,
                "texture": .texture,
                "normals": .texture,
                "metallicity": .numberOrTexture,
                "roughness": .numberOrTexture,
                "glow": .colorOrTexture,
            ]
        case .color, .texture, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .rotation, .string, .text, .path, .mesh, .polygon,
             .point, .range, .partialRange, .bounds, .union, .tuple, .list:
            // TODO: something better
            return Self.memberTypes
        case .any:
            return [:]
        }
    }

    func memberType(_ name: String) -> ValueType? {
        _memberType(name) ?? EvaluationContext.altNames[name].flatMap { _memberType($0) }
    }

    private func _memberType(_ name: String) -> ValueType? {
        switch self {
        case let .list(type):
            return (name.isOrdinal || name == "last") ? type : type.memberType(name)
        case let .tuple(types):
            if let index = name.ordinalIndex {
                return types.indices.contains(index) ? types[index] : nil
            }
            switch name {
            case "count": return .number
            case "last": return types.last
            case _ where types.count <= 1: return types.first?.memberType(name)
            default: return Self.memberTypes[name]
            }
        case let .union(types):
            let types = Set(types.compactMap { $0.memberType(name) })
            return types.isEmpty ? nil : ValueType.union(types).simplified()
        case .color, .texture, .material, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .rotation, .string, .text, .path, .mesh, .polygon,
             .point, .range, .partialRange, .bounds, .object:
            return memberTypes[name]
        case .any:
            return nil
        }
    }

    private static let memberTypes: [String: ValueType] = [
        "x": .number,
        "y": .number,
        "z": .number,
        "width": .number,
        "height": .number,
        "depth": .number,
        "roll": .halfturns,
        "yaw": .halfturns,
        "pitch": .halfturns,
        "red": .number,
        "green": .number,
        "blue": .number,
        "alpha": .number,
        "bounds": .bounds,
        "opacity": .number,
        "intensity": .number,
        "color": .optional(.color),
        "texture": .texture,
        "metallicity": .numberOrTexture,
        "roughness": .numberOrTexture,
        "glow": .colorOrTexture,
        "isCurved": .boolean,
        "start": .number,
        "end": .number,
        "step": .number,
        "min": .number,
        "max": .number,
        "volume": .number,
        "size": .size,
        "center": .vector,
        "count": .number,
        "points": .list(.point),
        "polygons": .list(.polygon),
        "triangles": .list(.polygon),
        "lines": .list(.string),
        "words": .list(.string),
        "characters": .list(.string),
        "linespacing": .optional(.number),
        "font": .optional(.font),
        "name": .string,
    ]
}

extension Value {
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
        case .texture:
            return ["intensity"]
        case .material:
            return ["opacity", "color", "texture", "metallicity", "roughness", "glow"]
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
            let flattened = values.flattened
            if flattened.isEmpty || flattened.contains(where: {
                $0.value is Bounded || $0.value is Geometry
            }) {
                members.append("bounds")
            }
            if flattened.isEmpty || flattened.contains(where: { $0.type == .mesh }) {
                members += ["polygons", "triangles", "volume"]
            } else if flattened.contains(where: { $0.type == .polygon }) {
                members += ["polygons", "triangles"]
            }
            return members
        case .range:
            return ["start", "end", "step"]
        case let .mesh(geometry):
            var members = ["name", "bounds"]
            if geometry.hasMesh {
                members += ["polygons", "triangles", "material", "volume"]
            }
            return members
        case .path:
            return ["bounds", "points"]
        case .polygon:
            return ["bounds", "center", "points", "triangles"]
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
        case .font:
            return ["name"]
        case .text:
            return ["string", "font", "color", "linespacing"]
        case let .object(values):
            return values.keys.sorted()
        case .boolean, .number, .radians, .halfturns:
            return []
        }
    }

    func hasMember(_ name: String) -> Bool {
        members.contains(name) || EvaluationContext
            .altNames[name].map { members.contains($0) } ?? false
    }

    subscript(name: String) -> Value? {
        self[name, { false }]
    }

    subscript(
        name: String,
        isCancelled: @escaping Mesh.CancellationHandler
    ) -> Value? {
        _member(name, isCancelled) ?? EvaluationContext
            .altNames[name].flatMap { _member($0, isCancelled) }
    }

    private func _member(_ name: String, _ isCancelled: @escaping Mesh.CancellationHandler) -> Value? {
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
        case let .texture(texture):
            switch name {
            case "intensity": return .number(texture?.intensity ?? 0)
            default: return nil
            }
        case let .material(material):
            switch name {
            case "opacity": return material.opacity.map { .numberOrTexture($0) } ?? .number(1)
            case "color": return .color(material.color ?? .white)
            case "texture": return .texture(material.texture)
            case "metallicity": return material.metallicity.map { .numberOrTexture($0) } ?? .number(0)
            case "roughness": return material.roughness.flatMap { .numberOrTexture($0) } ?? .number(0)
            case "glow": return material.glow.flatMap { .colorOrTexture($0) } ?? .color(.black)
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
                return (self.as(.size) ?? self.as(.bounds))?[name, isCancelled]
            case "roll", "yaw", "pitch":
                return self.as(.rotation)?[name, isCancelled]
            case "red", "green", "blue", "alpha":
                return self.as(.color)?[name, isCancelled]
            case "bounds":
                return .bounds(Bounds(values.flattened.compactMap {
                    switch $0.value {
                    case let bounded as Bounded:
                        return bounded.bounds
                    case let geometry as Geometry:
                        return geometry.exactBounds(with: geometry.transform) {
                            !isCancelled()
                        }
                    default:
                        return nil
                    }
                }))
            case "volume":
                return .number(values.flattened.reduce(0) {
                    switch $1 {
                    case let .mesh(geometry) where geometry.hasMesh:
                        return $0 + geometry.volume(isCancelled)
                    default:
                        return $0
                    }
                })
            case "polygons":
                return .tuple(values.flattened.flatMap {
                    switch $0 {
                    case let .mesh(geometry) where geometry.hasMesh:
                        let polygons = geometry.polygons(isCancelled)
                            .transformed(by: geometry.transform)
                        return polygons.map { Value.polygon($0) }
                    case .polygon:
                        return [self]
                    default:
                        return []
                    }
                })
            case "triangles":
                return .tuple(values.flattened.flatMap {
                    switch $0 {
                    case let .mesh(geometry) where geometry.hasMesh:
                        let triangles = geometry.polygons(isCancelled)
                            .transformed(by: geometry.transform)
                        return triangles.map { Value.polygon($0) }
                    case let .polygon(polygon):
                        return polygon.triangulate().map { Value.polygon($0) }
                    default:
                        return []
                    }
                })
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
            case "end": return range.end.map(Value.number)
            case "step": return range.step.map(Value.number)
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
                let polygons = geometry.polygons(isCancelled)
                return .tuple(polygons.map { .polygon($0) })
            case "triangles" where geometry.hasMesh:
                let triangles = geometry.triangles(isCancelled)
                return .tuple(triangles.map { .polygon($0) })
            case "material" where geometry.hasMesh:
                return .material(geometry.material)
            case "volume" where geometry.hasMesh:
                return .number(geometry.volume(isCancelled))
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
            case "triangles":
                return .tuple(polygon.triangulate().map { .polygon($0) })
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
        case let .font(font):
            switch name {
            case "name":
                return .string(font)
            default:
                return nil
            }
        case let .text(text):
            switch name {
            case "string":
                return .string(text.string)
            case "font":
                return text.font.map { .font($0) } ?? .void
            case "color":
                return text.color.map { .color($0) } ?? .void
            case "linespacing":
                return text.linespacing.map { .number($0) } ?? .void
            default:
                return nil
            }
        case let .object(values):
            return values[name]
        case .boolean, .number, .radians, .halfturns:
            return nil
        }
    }

    var indices: Range<Int> {
        switch self {
        case .vector, .size:
            return -3 ..< 3
        case .color:
            return -4 ..< 4
        case let .tuple(values):
            return -values.endIndex ..< values.endIndex
        case let .range(range):
            guard let values = range.stride.map(Array.init) else { fallthrough }
            return -values.endIndex ..< values.endIndex
        case .boolean, .texture, .number, .radians, .halfturns, .material, .rotation,
             .string, .font, .text, .path, .mesh, .polygon, .point, .bounds, .object:
            return 0 ..< 0
        }
    }

    subscript(index: Int) -> Value? {
        switch self {
        case let .vector(vector), let .size(vector):
            switch index {
            case 0: return .number(vector.x)
            case 1: return .number(vector.y)
            case 2: return .number(vector.z)
            default: return nil
            }
        case let .color(color):
            switch index {
            case 0: return .number(color.r)
            case 1: return .number(color.g)
            case 2: return .number(color.b)
            case 3: return .number(color.a)
            default: return nil
            }
        case let .tuple(values):
            if values.count == 1, let result = values[0][index] { return result }
            let index = index < 0 ? values.count + index : index
            return values.indices.contains(index) ? values[index] : nil
        case let .range(range):
            guard let values = range.stride.map(Array.init) else { return nil }
            let index = index < 0 ? values.count + index : index
            return values.indices.contains(index) ? .number(values[index]) : nil
        case .boolean, .texture, .number, .radians, .halfturns, .material, .rotation,
             .string, .font, .text, .path, .mesh, .polygon, .point, .bounds, .object:
            return nil
        }
    }
}

private extension [Value] {
    var flattened: [Value] {
        flatMap {
            switch $0 {
            case let .tuple(values):
                return values.flattened
            case .color, .texture, .material, .boolean, .number,
                 .radians, .halfturns, .vector, .size, .rotation,
                 .string, .font, .text, .path, .mesh, .polygon, .point,
                 .range, .bounds, .object:
                return [$0]
            }
        }
    }
}
