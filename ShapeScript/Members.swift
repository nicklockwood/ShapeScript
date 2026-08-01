//
//  Members.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 30/10/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

private struct MemberProperty: Sendable {
    let type: ValueType
    let isAvailable: @Sendable (Value) -> Bool
    let get: @Sendable (Value, @escaping Mesh.CancellationHandler) -> Value?

    init(
        _ type: ValueType,
        isAvailable: @escaping @Sendable (Value) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.type = type
        self.isAvailable = isAvailable
        self.get = get
    }
}

private typealias MemberProperties = [String: MemberProperty]

private extension MemberProperties {
    static func + (lhs: MemberProperties, rhs: MemberProperties) -> MemberProperties {
        lhs.merging(rhs) { $1 }
    }

    static let all = _merge(
        vector, size, rotation, color, texture, material, range, mesh,
        path, polygon, point, bounds, string, font, text
    )

    static let vector: MemberProperties = [
        "x": .init(.number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.x)
        },
        "y": .init(.number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.y)
        },
        "z": .init(.number) { value, _ in
            guard case let .vector(vector) = value else { return nil }
            return .number(vector.z)
        },
    ]

    static let size: MemberProperties = [
        "width": .init(.number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.x)
        },
        "height": .init(.number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.y)
        },
        "depth": .init(.number) { value, _ in
            guard case let .size(size) = value else { return nil }
            return .number(size.z)
        },
    ]

    static let rotation: MemberProperties = [
        "roll": .init(.halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.roll.halfturns)
        },
        "yaw": .init(.halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.yaw.halfturns)
        },
        "pitch": .init(.halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.pitch.halfturns)
        },
        "axis": .init(.vector) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .vector(rotation.axis)
        },
        "angle": .init(.halfturns) { value, _ in
            guard case let .rotation(rotation) = value else { return nil }
            return .halfturns(rotation.angle.halfturns)
        },
    ]

    static let color: MemberProperties = [
        "red": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.red)
        },
        "green": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.green)
        },
        "blue": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.blue)
        },
        "hue": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.hue)
        },
        "saturation": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.saturation)
        },
        "brightness": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.brightness)
        },
        "alpha": .init(.number) { value, _ in
            guard case let .color(color) = value else { return nil }
            return .number(color.alpha)
        },
    ]

    static let texture: MemberProperties = [
        "intensity": .init(.number) { value, _ in
            guard case let .texture(texture) = value else { return nil }
            return .number(texture?.intensity ?? 0)
        },
    ]

    static let material: MemberProperties = [
        "opacity": .init(.number) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.opacity.map { .numberOrTexture($0) } ?? .number(1)
        },
        "color": .init(.color) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .color(material.color ?? .white)
        },
        "texture": .init(.texture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .texture(material.texture)
        },
        "normals": .init(.texture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return .texture(material.normals)
        },
        "metallicity": .init(.numberOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.metallicity.map { .numberOrTexture($0) } ?? .number(0)
        },
        "roughness": .init(.numberOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.roughness.flatMap { .numberOrTexture($0) } ?? .number(0)
        },
        "glow": .init(.colorOrTexture) { value, _ in
            guard case let .material(material) = value else { return nil }
            return material.glow.flatMap { .colorOrTexture($0) } ?? .color(.black)
        },
    ]

    static let range: MemberProperties = [
        "start": .init(.number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return .number(range.start)
        },
        "end": .init(.number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return range.end.map(ShapeScript.Value.number)
        },
        "step": .init(.number) { value, _ in
            guard case let .range(range) = value else { return nil }
            return range.step.map(ShapeScript.Value.number)
        },
    ]

    static let mesh: MemberProperties = [
        "name": .init(.string) { value, _ in
            guard case let .mesh(geometry) = value else { return nil }
            return .string(geometry.name ?? "")
        },
        "bounds": .init(.bounds) { value, isCancelled in
            guard case let .mesh(geometry) = value else { return nil }
            return .bounds(geometry.exactBounds(with: geometry.transform) { !isCancelled() })
        },
        "polygons": .init(.list(.polygon), isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .tuple(geometry.polygons(isCancelled).map { .polygon($0) })
        },
        "triangles": .init(.list(.polygon), isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .tuple(geometry.triangles(isCancelled).map { .polygon($0) })
        },
        "material": .init(.material, isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, _ in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .material(geometry.material)
        },
        "volume": .init(.number, isAvailable: {
            guard case let .mesh(geometry) = $0 else { return false }
            return geometry.hasMesh
        }) { value, isCancelled in
            guard case let .mesh(geometry) = value, geometry.hasMesh else { return nil }
            return .number(geometry.volume(isCancelled))
        },
    ]

    static let path: MemberProperties = [
        "bounds": .init(.bounds) { value, _ in
            guard case let .path(path) = value else { return nil }
            return .bounds(path.bounds)
        },
        "points": .init(.list(.point)) { value, _ in
            guard case let .path(path) = value else { return nil }
            return .tuple(path.points.map { .point($0) })
        },
    ]

    static let polygon: MemberProperties = [
        "bounds": .init(.bounds) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .bounds(polygon.bounds)
        },
        "center": .init(.vector) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .vector(polygon.centroid)
        },
        "points": .init(.list(.point)) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .tuple(polygon.vertices.map { .point(PathPoint($0)) })
        },
        "triangles": .init(.list(.polygon)) { value, _ in
            guard case let .polygon(polygon) = value else { return nil }
            return .tuple(polygon.triangulate().map { .polygon($0) })
        },
    ]

    static let point: MemberProperties = [
        "x": .init(.number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.x)
        },
        "y": .init(.number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.y)
        },
        "z": .init(.number) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .number(point.position.z)
        },
        "position": .init(.vector) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .vector(point.position)
        },
        "color": .init(.optional(.color)) { value, _ in
            guard case let .point(point) = value else { return nil }
            return point.color.map { .color($0) } ?? .void
        },
        "isCurved": .init(.boolean) { value, _ in
            guard case let .point(point) = value else { return nil }
            return .boolean(point.isCurved)
        },
    ]

    static let bounds: MemberProperties = [
        "min": .init(.vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.min)
        },
        "max": .init(.vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.max)
        },
        "size": .init(.size) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .size(bounds.size)
        },
        "center": .init(.vector) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .vector(bounds.center)
        },
        "width": .init(.number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.x)
        },
        "height": .init(.number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.y)
        },
        "depth": .init(.number) { value, _ in
            guard case let .bounds(bounds) = value else { return nil }
            return .number(bounds.size.z)
        },
    ]

    static let string: MemberProperties = [
        "lines": .init(.list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.split { $0.isNewline }.map { .string("\($0)") })
        },
        "words": .init(.list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.split(omittingEmptySubsequences: true) {
                $0.isWhitespace || $0.isNewline
            }.map { .string("\($0)") })
        },
        "characters": .init(.list(.string)) { value, _ in
            guard case let .string(string) = value else { return nil }
            return .tuple(string.map { .string("\($0)") })
        },
    ]

    static let font: MemberProperties = [
        "name": .init(.string) { value, _ in
            guard case let .font(font) = value else { return nil }
            return .string(font)
        },
    ]

    static let text: MemberProperties = [
        "string": .init(.string) { value, _ in
            guard case let .text(text) = value else { return nil }
            return .string(text.string)
        },
        "font": .init(.optional(.font)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.font.map { .font($0) } ?? .void
        },
        "color": .init(.optional(.color)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.color.map { .color($0) } ?? .void
        },
        "linespacing": .init(.optional(.number)) { value, _ in
            guard case let .text(text) = value else { return nil }
            return text.linespacing.map { .number($0) } ?? .void
        },
    ]
}

private struct TupleMemberProperty: Sendable {
    let fallbackType: ValueType?
    let type: @Sendable ([ValueType]) -> ValueType?
    let isAvailable: @Sendable ([Value]) -> Bool
    let get: @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?

    init(
        fallbackType: ValueType? = nil,
        type: @escaping @Sendable ([ValueType]) -> ValueType?,
        isAvailable: @escaping @Sendable ([Value]) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.fallbackType = fallbackType
        self.type = type
        self.isAvailable = isAvailable
        self.get = get
    }

    init(
        _ type: ValueType,
        isAvailable: @escaping @Sendable ([Value]) -> Bool = { _ in true },
        get: @escaping @Sendable (Value, [Value], @escaping Mesh.CancellationHandler) -> Value?
    ) {
        self.init(
            fallbackType: type,
            type: { _ in type },
            isAvailable: isAvailable,
            get: get
        )
    }
}

private typealias TupleMemberProperties = [String: TupleMemberProperty]

private extension TupleMemberProperties {
    static let all = _merge(
        structural, vector, size, rotation, string, color, bounds, aggregate, mesh
    )

    static let structural: TupleMemberProperties = [
        "last": .init(fallbackType: .any, type: { $0.last }, isAvailable: { !$0.isEmpty }) { _, values, _ in
            values.last
        },
        "count": .init(.number) { _, values, _ in
            .number(Double(values.unwrapped(recursive: true).count))
        },
        "allButFirst": .init(fallbackType: .list(.any), type: { types in
            .tuple(Swift.Array(types.dropFirst()))
        }) { _, values, _ in
            .tuple(Swift.Array(values.unwrapped(recursive: true).dropFirst()))
        },
        "allButLast": .init(fallbackType: .list(.any), type: { types in
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

    static let aggregate: TupleMemberProperties = [
        "bounds": .init(.bounds, isAvailable: {
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

    static let mesh: TupleMemberProperties = [
        "polygons": .init(.list(.polygon), isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains { value in
                value.type == .mesh || value.type == .polygon
            }
        }) { _, values, isCancelled in
            .tuple(values.flattened(recursive: true).flatMap { value in
                switch value {
                case let .mesh(geometry) where geometry.hasMesh:
                    let polygons = geometry.polygons(isCancelled)
                        .transformed(by: geometry.transform)
                    return polygons.map { ShapeScript.Value.polygon($0) }
                case let .polygon(polygon):
                    return [.polygon(polygon)]
                default:
                    return []
                }
            })
        },
        "triangles": .init(.list(.polygon), isAvailable: {
            $0.isEmpty || $0.flattened(recursive: true).contains { value in
                value.type == .mesh || value.type == .polygon
            }
        }) { _, values, isCancelled in
            .tuple(values.flattened(recursive: true).flatMap { value in
                switch value {
                case let .mesh(geometry) where geometry.hasMesh:
                    let triangles = geometry.triangles(isCancelled)
                        .transformed(by: geometry.transform)
                    return triangles.map { ShapeScript.Value.polygon($0) }
                case let .polygon(polygon):
                    return polygon.triangulate().map { ShapeScript.Value.polygon($0) }
                default:
                    return []
                }
            })
        },
        "volume": .init(.number, isAvailable: {
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
        properties: MemberProperties
    ) -> TupleMemberProperties {
        Dictionary(uniqueKeysWithValues: properties.map { name, property in
            (
                name,
                TupleMemberProperty(
                    property.type,
                    isAvailable: { ShapeScript.Value.tuple($0).as(valueType) != nil },
                    get: { _, values, isCancelled in
                        ShapeScript.Value.tuple(values).as(valueType)?[name, isCancelled]
                    }
                )
            )
        })
    }

    var fallbackTypes: [String: ValueType] {
        .init(
            compactMap { name, property in
                property.fallbackType.map { (name, $0) }
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
            memberProperties.mapValues(\.type)
        case .texture, .boolean, .font, .number, .radians, .halfturns,
             .vector, .size, .string, .text, .path, .mesh, .polygon, .point,
             .range, .partialRange, .bounds, .union, .tuple, .list:
            Self.knownMemberTypes
        case .any:
            [:]
        }
    }

    fileprivate var memberProperties: MemberProperties {
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
            [:]
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
            if let type = tupleMemberProperties[name]?.type(types) {
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

    private var tupleMemberProperties: TupleMemberProperties {
        guard case .tuple = self else {
            return [:]
        }
        return .all
    }

    private static let knownMemberTypes = Dictionary(
        MemberProperties.all.map { ($0.key, $0.value.type) },
        uniquingKeysWith: { lhs, _ in lhs }
    ).merging(TupleMemberProperties.all.fallbackTypes) { _, rhs in rhs }
        .merging(["color": .optional(.color)]) { _, rhs in rhs }
}

private func _merge<T>(_ dictionaries: [String: T]...) -> [String: T] {
    var result = [String: T]()
    for dictionary in dictionaries {
        result.merge(dictionary) { $1 }
    }
    return result
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
            members.appendUnique(contentsOf: TupleMemberProperties.all.compactMap {
                $0.value.isAvailable(values) ? $0.key : nil
            })
            if ShapeScript.Value.tuple(values).as(.size) != nil {
                members.appendUnique(contentsOf: Array(MemberProperties.size.keys))
            }
            if values.count == 1 {
                members.appendUnique(contentsOf: values[0].members)
            }
            return members
        case .vector, .size, .rotation, .color, .texture, .material,
             .range, .mesh, .path, .polygon, .point, .bounds, .font, .text:
            return type.memberProperties.compactMap { $0.value.isAvailable(self) ? $0.key : nil }
        case .string:
            var members = Array(type.memberProperties.keys)
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
            if let value = TupleMemberProperties.all[name]?.get(self, values, isCancelled) {
                return value
            }
            if MemberProperties.size[name] != nil {
                return ShapeScript.Value.tuple(values).as(.size)?[name, isCancelled]
            }
            let values = values.unwrapped(recursive: true)
            if let index = name.ordinalIndex {
                return index < values.count ? values[index] : nil
            }
            if values.count == 1 {
                return values[0][name, isCancelled]
            }
            return nil
        case .string where ValueType.color.memberProperties[name] != nil:
            return self.as(.color)?[name, isCancelled]
        case .vector, .size, .rotation, .color, .texture, .material,
             .range, .mesh, .path, .polygon, .point, .bounds, .string, .font, .text:
            return type.memberProperties[name]?.get(self, isCancelled)
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
