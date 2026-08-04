//
//  Members.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 30/10/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

private struct MemberProperty: Sendable {
    let name: String
    let type: ValueType
    let isAvailable: @Sendable (Value) -> Bool
    let get: @Sendable (Value, @escaping Mesh.CancellationHandler) -> Value?

    init(
        _ name: String,
        _ type: ValueType,
        isAvailable: @escaping @Sendable (Value) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.name = name
        self.type = type
        self.isAvailable = isAvailable
        self.get = get
    }
}

private extension [MemberProperty] {
    static let all: [MemberProperty] = [
        vector, size, rotation, color, texture, material, range, mesh,
        path, polygon, point, bounds, string, font, text,
    ].flatMap { $0 }

    static let vector: [MemberProperty] = [
        .init("x", .number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.x)
        },
        .init("y", .number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.y)
        },
        .init("z", .number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.z)
        },
    ]

    static let size: [MemberProperty] = [
        .init("width", .number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.x)
        },
        .init("height", .number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.y)
        },
        .init("depth", .number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.z)
        },
    ]

    static let rotation: [MemberProperty] = [
        .init("roll", .halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.roll.halfturns)
        },
        .init("yaw", .halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.yaw.halfturns)
        },
        .init("pitch", .halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.pitch.halfturns)
        },
        .init("axis", .vector) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .vector(rotation.axis)
        },
        .init("angle", .halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.angle.halfturns)
        },
    ]

    static let color: [MemberProperty] = [
        .init("red", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.red)
        },
        .init("green", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.green)
        },
        .init("blue", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.blue)
        },
        .init("hue", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.hue)
        },
        .init("saturation", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.saturation)
        },
        .init("brightness", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.brightness)
        },
        .init("alpha", .number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.alpha)
        },
    ]

    static let texture: [MemberProperty] = [
        .init("intensity", .number) { value, _ in
            guard case let .texture(texture) = value else { return nil }
            return .number(texture?.intensity ?? 0)
        },
    ]

    static let material: [MemberProperty] = [
        .init("opacity", .number) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.opacity.map { .numberOrTexture($0) } ?? .number(1)
        },
        .init("color", .color) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .color(material.color ?? .white)
        },
        .init("texture", .texture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .texture(material.texture)
        },
        .init("normals", .texture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .texture(material.normals)
        },
        .init("metallicity", .numberOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.metallicity.map { .numberOrTexture($0) } ?? .number(0)
        },
        .init("roughness", .numberOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.roughness.flatMap { .numberOrTexture($0) } ?? .number(0)
        },
        .init("glow", .colorOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.glow.flatMap { .colorOrTexture($0) } ?? .color(.black)
        },
    ]

    static let range: [MemberProperty] = [
        .init("start", .number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return .number(range.start)
        },
        .init("end", .number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return range.end.map(Value.number)
        },
        .init("step", .number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return range.step.map(Value.number)
        },
    ]

    static let mesh: [MemberProperty] = [
        .init("name", .string) { value, _ in
            guard case let .mesh(geometry) = value else { return nil }
            return .string(geometry.name ?? "")
        },
        .init("bounds", .bounds) { value, isCancelled in
            guard case let .mesh(geometry) = value else { return nil }
            return .bounds(geometry.exactBounds(with: geometry.transform) { !isCancelled() })
        },
        .init("polygons", .list(.polygon), isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .tuple(geometry.polygons(isCancelled).map { .polygon($0) })
        },
        .init("triangles", .list(.polygon), isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .tuple(geometry.triangles(isCancelled).map { .polygon($0) })
        },
        .init("material", .material, isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, _ in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .material(geometry.material)
        },
        .init("volume", .number, isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .number(geometry.volume(isCancelled))
        },
    ]

    static let path: [MemberProperty] = [
        .init("bounds", .bounds) { value, _ in
            guard case let .path(path) = value else { return nil }
            return .bounds(path.bounds)
        },
        .init("points", .list(.point)) { value, _ in
            guard case let .path(path) = value else { return nil }
            return .tuple(path.points.map { .point($0) })
        },
    ]

    static let polygon: [MemberProperty] = [
        .init("bounds", .bounds) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .bounds(polygon.bounds)
        },
        .init("center", .vector) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .vector(polygon.centroid)
        },
        .init("points", .list(.point)) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .tuple(polygon.vertices.map { .point(PathPoint($0)) })
        },
        .init("triangles", .list(.polygon)) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .tuple(polygon.triangulate().map { .polygon($0) })
        },
    ]

    static let point: [MemberProperty] = [
        .init("x", .number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.x)
        },
        .init("y", .number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.y)
        },
        .init("z", .number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.z)
        },
        .init("position", .vector) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .vector(point.position)
        },
        .init("color", .optional(.color)) { value, _ in
            guard case let .point(point) = value else { return nil }
            return point.color.map { .color($0) } ?? .void
        },
        .init("isCurved", .boolean) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .boolean(point.isCurved)
        },
    ]

    static let bounds: [MemberProperty] = [
        .init("min", .vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.min)
        },
        .init("max", .vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.max)
        },
        .init("size", .size) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .size(bounds.size)
        },
        .init("center", .vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.center)
        },
        .init("width", .number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.x)
        },
        .init("height", .number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.y)
        },
        .init("depth", .number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.z)
        },
    ]

    static let string: [MemberProperty] = [
        .init("lines", .list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.split { $0.isNewline }.map { .string("\($0)") })
        },
        .init("words", .list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.split(omittingEmptySubsequences: true) {
                $0.isWhitespace || $0.isNewline
            }.map { .string("\($0)") })
        },
        .init("characters", .list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.map { .string("\($0)") })
        },
    ]

    static let font: [MemberProperty] = [
        .init("name", .string) { value, _ in
            guard case let .font(font) = value else { return nil }
            return .string(font)
        },
    ]

    static let text: [MemberProperty] = [
        .init("string", .string) { value, _ in
            guard case let .text(text) = value else { return nil }
            return .string(text.string)
        },
        .init("font", .optional(.font)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.font.map { .font($0) } ?? .void
        },
        .init("color", .optional(.color)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.color.map { .color($0) } ?? .void
        },
        .init("linespacing", .optional(.number)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.linespacing.map { .number($0) } ?? .void
        },
    ]
}

private struct TupleMemberProperty: Sendable {
    let name: String
    let fallbackType: ValueType?
    let type: @Sendable ([ValueType]) -> ValueType?
    let isAvailable: @Sendable ([Value]) -> Bool
    let get: @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?

    init(
        _ name: String,
        fallbackType: ValueType? = nil,
        type: @escaping @Sendable ([ValueType]) -> ValueType?,
        isAvailable: @escaping @Sendable ([Value]) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.name = name
        self.fallbackType = fallbackType
        self.type = type
        self.isAvailable = isAvailable
        self.get = get
    }

    init(
        _ name: String,
        _ type: ValueType,
        isAvailable: @escaping @Sendable ([Value]) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.init(
            name,
            fallbackType: type,
            type: { _ in type },
            isAvailable: isAvailable,
            get: get
        )
    }
}

private extension [TupleMemberProperty] {
    static let all = [
        structural, vector, size, rotation, string, color, bounds, aggregate, mesh,
    ].flatMap { $0 }

    static let structural: [TupleMemberProperty] = [
        .init("last", fallbackType: .any, type: { $0.last }, isAvailable: { !$0.isEmpty }) { _, values, _ in
            values.last
        },
        .init("count", .number) { _, values, _ in
            .number(Double(values.unwrapped(recursive: true).count))
        },
        .init("allButFirst", fallbackType: .list(.any), type: { types in
            .tuple(Swift.Array(types.dropFirst()))
        }) { _, values, _ in
            .tuple(Swift.Array(values.unwrapped(recursive: true).dropFirst()))
        },
        .init("allButLast", fallbackType: .list(.any), type: { types in
            .tuple(Swift.Array(types.dropLast()))
        }) { _, values, _ in
            .tuple(Swift.Array(values.unwrapped(recursive: true).dropLast()))
        },
    ]

    static let vector = forwarding(.vector, properties: .vector)
    static let size = forwarding(.size, properties: .size)
    static let rotation = forwarding(.rotation, properties: .rotation)
    static let string = forwarding(.string, properties: .string)
    static let color = forwarding(.color, properties: .color)
    static let bounds = forwarding(.bounds, properties: .bounds)

    static let aggregate: [TupleMemberProperty] = [
        .init("bounds", .bounds, isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains {
                $0.value is Bounded || $0.value is Geometry
            }
        }) { _, values, isCancelled in
            .bounds(Bounds(values.flattened(recursive: true).compactMap {
                switch $0.value {
                case let bounded as Bounded:
                    bounded.bounds
                case let geometry as Geometry:
                    geometry.exactBounds(with: geometry.transform) {
                        !isCancelled()
                    }
                default:
                    nil
                }
            }))
        },
    ]

    static let mesh: [TupleMemberProperty] = [
        .init("polygons", .list(.polygon), isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains { value in
                value.type == .mesh || value.type == .polygon
            }
        }) { _, values, isCancelled in
            .tuple(values.flattened(recursive: true).flatMap { value in
                switch value {
                case let .mesh(geometry) where geometry.hasMesh:
                    let polygons = geometry.polygons(isCancelled)
                        .transformed(by: geometry.transform)
                    return polygons.map { Value.polygon($0) }
                case let .polygon(polygon):
                    return [.polygon(polygon)]
                default:
                    return []
                }
            })
        },
        .init("triangles", .list(.polygon), isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains { value in
                value.type == .mesh || value.type == .polygon
            }
        }) { _, values, isCancelled in
            .tuple(values.flattened(recursive: true).flatMap { value in
                switch value {
                case let .mesh(geometry) where geometry.hasMesh:
                    let triangles = geometry.triangles(isCancelled)
                        .transformed(by: geometry.transform)
                    return triangles.map { Value.polygon($0) }
                case let .polygon(polygon):
                    return polygon.triangulate().map { Value.polygon($0) }
                default:
                    return []
                }
            })
        },
        .init("volume", .number, isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains { $0.type == .mesh }
        }) { _, values, isCancelled in
            .number(values.flattened(recursive: true).reduce(0) {
                switch $1 {
                case let .mesh(geometry) where geometry.hasMesh:
                    $0 + geometry.volume(isCancelled)
                default:
                    $0
                }
            })
        },
    ]

    private static func forwarding(
        _ valueType: ValueType,
        properties: [MemberProperty]
    ) -> [TupleMemberProperty] {
        properties.map { property in
            TupleMemberProperty(
                property.name,
                property.type,
                isAvailable: { Value.tuple($0).as(valueType) != nil },
                get: { value, _, isCancelled in
                    value.as(valueType)?[property.name, isCancelled]
                }
            )
        }
    }

    var fallbackTypes: [String: ValueType] {
        Dictionary(
            compactMap { property in
                property.fallbackType.map { (property.name, $0) }
            },
            uniquingKeysWith: { lhs, _ in lhs }
        )
    }
}

private struct MemberwiseConstructor: Sendable {
    var isSelected: @Sendable ([String: Value]) -> Bool = { _ in true }
    let make: @Sendable ([String: Value]) throws -> Value?
}

private extension MemberwiseConstructor {
    static let material = MemberwiseConstructor { values in
        .material(.init(
            opacity: values["opacity"]?.numberOrTextureValue,
            albedo: (values["color"] ?? values["texture"])?.colorOrTextureValue,
            normals: values["normals"]?.value as? Texture,
            metallicity: values["metallicity"]?.numberOrTextureValue,
            roughness: values["roughness"]?.numberOrTextureValue,
            glow: values["glow"]?.colorOrTextureValue
        ))
    }

    static let colorHSB = MemberwiseConstructor(isSelected: {
        $0["hue"] ?? $0["saturation"] ?? $0["brightness"] != nil
    }) { values in
        guard values["red"] ?? values["green"] ?? values["blue"] == nil else {
            throw RuntimeErrorType.assertionFailure(
                "Color initializer cannot mix red/green/blue with hue/saturation/brightness"
            )
        }
        return .color(.init(
            hue: values["hue"]?.doubleValue ?? 0,
            saturation: values["saturation"]?.doubleValue ?? 0,
            brightness: values["brightness"]?.doubleValue ?? 0,
            alpha: values["alpha"]?.doubleValue ?? 1
        ))
    }

    static let colorRGB = MemberwiseConstructor { values in
        .color(.init(
            red: values["red"]?.doubleValue ?? 0,
            green: values["green"]?.doubleValue ?? 0,
            blue: values["blue"]?.doubleValue ?? 0,
            alpha: values["alpha"]?.doubleValue ?? 1
        ))
    }

    static let rotationAxisAngle = MemberwiseConstructor(isSelected: {
        $0["axis"] ?? $0["angle"] != nil
    }) { values in
        guard values["roll"] ?? values["yaw"] ?? values["pitch"] == nil else {
            throw RuntimeErrorType.assertionFailure(
                "Rotation initializer cannot mix roll/yaw/pitch with axis/angle"
            )
        }
        guard let rotation = Rotation(
            axis: values["axis"]?.vectorValue ?? .unitZ,
            angle: values["angle"]?.angleValue ?? .zero
        ) else {
            throw RuntimeErrorType.assertionFailure("Axis vector must be nonzero")
        }
        return .rotation(rotation)
    }

    static let rotationEuler = MemberwiseConstructor { values in
        .rotation(.init(
            roll: values["roll"]?.angleValue ?? .zero,
            yaw: values["yaw"]?.angleValue ?? .zero,
            pitch: values["pitch"]?.angleValue ?? .zero
        ))
    }
}

extension ValueType {
    /// Create an instance from a dictionary of memberwise values
    /// Note: this function assumes values have already been validated and cast to correct types
    func instance(with values: [String: Value]) throws -> Value? {
        switch self {
        case .object:
            .object(values)
        default:
            try memberwiseConstructors.first { $0.isSelected(values) }?.make(values)
        }
    }

    var memberTypes: [String: ValueType] {
        switch self {
        case let .object(members):
            members
        case .material, .color, .rotation:
            Dictionary(uniqueKeysWithValues: memberProperties.map { ($0.name, $0.type) })
        case .texture, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .string, .text, .path, .mesh, .polygon, .point,
             .range, .partialRange, .bounds, .union, .tuple, .list:
            Self.knownMemberTypes
        case .any:
            [:]
        }
    }

    fileprivate var memberProperties: [MemberProperty] {
        switch self {
        case .vector: .vector
        case .size: .size
        case .rotation: .rotation
        case .color: .color
        case .texture: .texture
        case .material: .material
        case .range, .partialRange: .range
        case .mesh: .mesh
        case .path: .path
        case .polygon: .polygon
        case .point: .point
        case .bounds: .bounds
        case .string: .string
        case .font: .font
        case .text: .text
        case .boolean, .number, .radians, .halfturns,
             .object, .union, .tuple, .list, .any:
            []
        }
    }

    private var memberwiseConstructors: [MemberwiseConstructor] {
        switch self {
        case .material: [.material]
        case .color: [.colorHSB, .colorRGB]
        case .rotation: [.rotationAxisAngle, .rotationEuler]
        case .texture, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .string, .text, .path, .mesh, .polygon, .point,
             .range, .partialRange, .bounds, .object, .union, .tuple, .list, .any:
            []
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
            if let type = tupleMemberProperties.first(where: { $0.name == name })?.type(types) {
                return type
            }
            return types.count <= 1 ? types.first?.memberType(name) : Self.knownMemberTypes[name]
        case let .union(types):
            let types = Set(types.compactMap { $0.memberType(name) })
            return types.isEmpty ? nil : ValueType.union(types).simplified()
        case .color, .texture, .material, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .rotation, .string, .text, .path, .mesh, .polygon, .point,
             .range, .partialRange, .bounds, .object:
            return memberTypes[name]
        case .any:
            return nil
        }
    }

    private var tupleMemberProperties: [TupleMemberProperty] {
        guard case .tuple = self else {
            return []
        }
        return .all
    }

    private static let knownMemberTypes = Dictionary(
        [MemberProperty].all.map { ($0.name, $0.type) },
        uniquingKeysWith: { lhs, _ in lhs }
    ).merging([TupleMemberProperty].all.fallbackTypes) { _, rhs in rhs }
        .merging(["color": .optional(.color)]) { _, rhs in rhs }
}

private extension [String] {
    mutating func appendUnique(contentsOf names: [String]) {
        for name in names where !contains(name) {
            append(name)
        }
    }
}

extension Value {
    var members: [String] {
        switch self {
        case let .tuple(values):
            var members = Array(String.ordinals(upTo: values.count))
            members.appendUnique(contentsOf: [TupleMemberProperty].all.filter {
                $0.isAvailable(values)
            }.map(\.name))
            if values.count == 1 {
                members.appendUnique(contentsOf: values[0].members)
            }
            return members
        case .vector, .size, .rotation, .color, .texture, .material,
             .range, .mesh, .path, .polygon, .point, .bounds, .font, .text:
            return type.memberProperties.filter { $0.isAvailable(self) }.map(\.name)
        case .string:
            var members = type.memberProperties.map(\.name)
            if let color = self.as(.color) {
                members += color.members
            }
            return members
        case let .object(values):
            return values.keys.sorted()
        case let .pretransformed(value):
            return value.members
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

    subscript(name: String, isCancelled: @escaping Mesh.CancellationHandler) -> Value? {
        _member(name, isCancelled) ?? EvaluationContext
            .altNames[name].flatMap { _member($0, isCancelled) }
    }

    private func _member(_ name: String, _ isCancelled: @escaping Mesh.CancellationHandler) -> Value? {
        switch self {
        case let .tuple(values):
            if let value = [TupleMemberProperty].all.first(where: { $0.name == name })?
                .get(self, values, isCancelled)
            {
                return value
            }
            let values = values.unwrapped(recursive: true)
            if let index = name.ordinalIndex {
                return index < values.count ? values[index] : nil
            }
            if values.count == 1 {
                return values[0][name, isCancelled]
            }
            return nil
        case .string where ValueType.color.memberProperties.contains(where: { $0.name == name }):
            return self.as(.color)?[name, isCancelled]
        case .vector, .size, .rotation, .color, .texture, .material,
             .range, .mesh, .path, .polygon, .point, .bounds, .string, .font, .text:
            return type.memberProperties.first { $0.name == name }?.get(self, isCancelled)
        case let .object(values):
            return values[name]
        case let .pretransformed(value):
            return value._member(name, isCancelled).map { .pretransformed($0) }
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
        case let .pretransformed(value):
            return value.indices
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
            case 0: return .number(color.red)
            case 1: return .number(color.green)
            case 2: return .number(color.blue)
            case 3: return .number(color.alpha)
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
        case let .pretransformed(value):
            return value[index].map { .pretransformed($0) }
        case .boolean, .texture, .number, .radians, .halfturns, .material, .rotation,
             .string, .font, .text, .path, .mesh, .polygon, .point, .bounds, .object:
            return nil
        }
    }
}
