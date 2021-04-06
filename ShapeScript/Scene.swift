//
//  Scene.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public extension Vector {
    // TODO: should tiny scale be treated as an error?
    init(size components: [Double]) {
        switch components.count {
        case 1: self.init(components[0], components[0], components[0])
        case 2: self.init(components[0], components[1], components[0])
        default: self.init(components)
        }
    }
}

public enum GeometryType: Hashable, CustomStringConvertible {
    case none
    // primitives
    case cone(segments: Int)
    case cylinder(segments: Int)
    case sphere(segments: Int)
    case cube
    // builders
    case extrude([Path], along: [Path])
    case lathe([Path], segments: Int)
    case loft([Path])
    case fill([Path])
    // csg
    case union
    case difference
    case intersection
    case xor
    case stencil
    // shapes
    case path(Path)
    case mesh(Mesh)

    public var description: String {
        switch self {
        case .none: return "group"
        case .cone: return "cone"
        case .cylinder: return "cylinder"
        case .sphere: return "sphere"
        case .cube: return "cube"
        case .extrude: return "extrusion"
        case .lathe: return "lathe"
        case .loft: return "loft"
        case .fill: return "fill"
        case .union: return "union"
        case .difference: return "difference"
        case .intersection: return "intersection"
        case .xor: return "xor"
        case .stencil: return "stencil"
        case .path: return "path"
        case .mesh: return "mesh"
        }
    }

    public var bounds: Bounds {
        switch self {
        case .none, .union, .xor, .difference, .intersection, .stencil:
            return .empty
        case .cone, .cylinder, .sphere, .cube:
            return .init(min: .init(-0.5, -0.5, -0.5), max: .init(0.5, 0.5, 0.5))
        case let .extrude(paths, along: along):
            if along.isEmpty {
                var points = [Vector]()
                for path in paths {
                    let offset = (path.plane?.normal ?? Vector(0, 0, 1)) / 2
                    for p in path.points {
                        points.append(p.position + offset)
                        points.append(p.position - offset)
                    }
                }
                return .init(points: points)
            }
            var bounds = Bounds.empty
            for along in along {
                let alongBounds = along.bounds
                for path in paths {
                    let pathBounds = path.bounds
                    bounds = bounds.union(Bounds(
                        min: alongBounds.min + pathBounds.min,
                        max: alongBounds.max + pathBounds.max
                    ))
                }
            }
            return bounds
        case let .lathe(paths, _):
            var result = [Bounds]()
            for path in paths {
                var min = path.bounds.min, max = path.bounds.max
                min.x = Swift.min(Swift.min(Swift.min(min.x, -max.x), min.z), -max.z)
                max.x = -min.x
                min.z = min.x
                max.z = -min.x
                result.append(.init(min: min, max: max))
            }
            return .init(bounds: result)
        case let .loft(paths),
             let .fill(paths):
            return .init(bounds: Array(paths.map { $0.bounds }))
        case let .path(path):
            return path.bounds
        case let .mesh(mesh):
            return mesh.bounds
        }
    }
}

private struct MeshCacheKey: Hashable {
    let type: GeometryType
    let material: Material?
    let transform: Transform
    let children: [MeshCacheKey]
}

private var meshCache = [MeshCacheKey: Mesh]()
private let meshQueue = DispatchQueue(label: "shapescript.meshCache")

public struct SourceLocation {
    public let line: Int
    public let file: URL?

    public init(at line: Int, in file: URL?) {
        self.line = line
        self.file = file
    }
}

public struct Scene {
    public let background: MaterialProperty
    public let children: [Geometry]

    public static let empty = Self(background: .color(.clear), children: [])

    public func deepCopy() -> Self {
        Self(background: background, children: children.map { $0.deepCopy() })
    }
}

public class Geometry {
    public let type: GeometryType
    public let name: String?
    public let transform: Transform
    public let material: Material
    public let children: [Geometry]
    public let isOpaque: Bool
    public let sourceLocation: SourceLocation?
    public let renderChildren: Bool
    public var isSelected: Bool = false

    public var isEmpty: Bool {
        switch type {
        case .none, .union, .xor, .difference, .intersection, .stencil:
            break
        case .cone, .cylinder, .sphere, .cube:
            return false
        case let .extrude(shapes, _),
             let .lathe(shapes, _),
             let .loft(shapes),
             let .fill(shapes):
            if shapes.isEmpty || shapes[0].points.count < 2 {
                break
            }
            return false
        case let .path(path):
            if path.points.count < 2 {
                break
            }
            return false
        case let .mesh(mesh):
            if mesh.polygons.isEmpty {
                break
            }
            return false
        }
        return !children.contains(where: { !$0.isEmpty })
    }

    public var bounds: Bounds {
        switch type {
        case .difference, .stencil:
            return children.first.map { $0.bounds.transformed(by: $0.transform) } ?? .empty
        case .intersection:
            var bounds = children.first.map { $0.bounds.transformed(by: $0.transform) } ?? .empty
            for child in children.dropFirst() {
                bounds = bounds.intersection(child.bounds.transformed(by: child.transform))
            }
            return bounds
        case .union, .xor, .none:
            var bounds = children.first.map { $0.bounds.transformed(by: $0.transform) } ?? .empty
            for child in children.dropFirst() {
                bounds = bounds.union(child.bounds.transformed(by: child.transform))
            }
            return bounds
        case .cone, .cube, .cylinder, .sphere, .extrude, .lathe, .loft, .fill, .path, .mesh:
            var bounds = type.bounds
            for child in children {
                bounds = bounds.union(child.bounds.transformed(by: child.transform))
            }
            return bounds
        }
    }

    public func transformed(by transform: Transform) -> Geometry {
        Geometry(
            type: type,
            name: name,
            transform: self.transform * transform,
            material: material,
            children: children,
            sourceLocation: sourceLocation
        )
    }

    // object graph shares a common color and no texture
    func hasUniformMaterial(_ material: Material? = nil) -> Bool {
        if self.material.texture != nil {
            return false
        }
        if material != nil, material != self.material {
            return false
        }
        return !children.contains(where: { !$0.hasUniformMaterial(material ?? self.material) })
    }

    public func with(
        transform: Transform,
        material: Material?,
        sourceLocation: SourceLocation?
    ) -> Geometry {
        var material = material
        if material != nil, !hasUniformMaterial() {
            material?.color = nil
            material?.texture = nil
        }
        return _with(
            transform: transform,
            material: material,
            sourceLocation: sourceLocation
        )
    }

    private func _with(
        transform: Transform,
        material: Material?,
        sourceLocation: SourceLocation?
    ) -> Geometry {
        var type = self.type
        var m = self.material
        if let material = material, case let .mesh(mesh) = type {
            m.opacity *= material.opacity
            m.color = material.color ?? self.material.color
            m.texture = material.texture ?? self.material.texture
            type = .mesh(mesh.replacing(self.material, with: m))
        }
        let copy = Geometry(
            type: type,
            name: name,
            transform: self.transform * transform,
            material: m,
            children: children.map {
                $0._with(
                    transform: .identity,
                    material: material,
                    sourceLocation: sourceLocation
                )
            },
            sourceLocation: self.sourceLocation ?? sourceLocation
        )
        copy.mesh = mesh
        copy.associatedData = associatedData
        copy.isSelected = isSelected
        return copy
    }

    public func deepCopy() -> Geometry {
        let copy = Geometry(
            type: type,
            name: name,
            transform: transform,
            material: material,
            children: children.map { $0.deepCopy() },
            sourceLocation: sourceLocation
        )
        copy.mesh = mesh
        copy.associatedData = associatedData
        copy.isSelected = isSelected
        return copy
    }

    private let cacheKey: MeshCacheKey

    var path: Path? {
        guard case let .path(path) = type else {
            return nil
        }
        return path
    }

    public private(set) var mesh: Mesh? {
        didSet {
            associatedData = nil
        }
    }

    public func build(_ callback: () -> Bool) -> Bool {
        guard mesh == nil else {
            return true
        }
        for child in children where !child.build(callback) {
            return false
        }
        if let mesh = meshQueue.sync(execute: { meshCache[cacheKey] }) {
            self.mesh = mesh
            return callback()
        }
        return buildMesh(callback)
    }

    private func mergeMeshes(_ builders: [() -> Mesh],
                             with fn: (Mesh, Mesh) -> Mesh = { $0.union($1) },
                             callback: () -> Bool) -> Bool
    {
        mesh = Mesh([])
        guard !builders.isEmpty else {
            return true
        }
        var builders = builders
        var meshes = [(Mesh, Bounds)]()
        func _mesh(at i: Int) -> (Mesh, Bounds) {
            if i == meshes.count {
                let m = builders[i]()
                meshes.append((m, m.bounds))
            }
            return meshes[i]
        }
        var i = 0, count = builders.count
        while i < count {
            var (m, mb) = _mesh(at: i)
            var j = i + 1
            while j < count {
                let (n, nb) = _mesh(at: j)
                if mb.intersects(nb) {
                    if !callback() {
                        return false
                    }
                    m = fn(m, n)
                    mb = m.bounds
                    meshes[i] = (m, mb)
                    meshes.remove(at: j)
                    _ = builders.remove(at: j)
                    count -= 1
                    continue
                }
                j += 1
            }
            mesh = mesh?.merge(m)
            i += 1
        }
        return true
    }

    private func reduceMeshes(_ builders: [() -> Mesh],
                              with fn: (Mesh, Mesh) -> Mesh,
                              callback: () -> Bool) -> Bool
    {
        guard var m = builders.first?() else {
            mesh = Mesh([])
            return true
        }
        var mb = m.bounds
        for i in 1 ..< builders.count {
            let n = builders[i]()
            let nb = n.bounds
            if mb.intersects(nb) {
                if !callback() {
                    return false
                }
                m = fn(m, n)
                mb = m.bounds
            }
        }
        mesh = m
        return true
    }

    private func buildMesh(_ callback: () -> Bool) -> Bool {
        switch type {
        case .none, .path:
            mesh = Mesh([])
        case let .cone(segments):
            mesh = .cone(slices: segments)
        case let .cylinder(segments):
            mesh = .cylinder(slices: segments)
        case let .sphere(segments):
            mesh = .sphere(slices: segments, stacks: segments / 2)
        case .cube:
            mesh = .cube()
        case let .extrude(paths, along: along):
            let builders = along.isEmpty ? paths.map {
                path in { Mesh.extrude(path, depth: 1) }
            } : along.flatMap { along in
                paths.map { path in { Mesh.extrude(path, along: along) } }
            }
            if !mergeMeshes(builders, callback: callback) {
                return false
            }
        case let .lathe(paths, segments: segments):
            let builders = paths.map { path in { Mesh.lathe(path, slices: segments) } }
            if !mergeMeshes(builders, callback: callback) {
                return false
            }
        case let .loft(paths):
            mesh = Mesh.loft(paths)
        case let .fill(paths):
            let builders = paths.map { path in { Mesh.fill(path.closed()) } }
            if !mergeMeshes(builders, callback: callback) {
                return false
            }
        case .union:
            let builders = children.map { child in { child.flatten(with: self.material) } }
            if !mergeMeshes(builders, callback: callback) {
                return false
            }
        case .xor:
            let builders = children.map { child in { child.flatten(with: self.material) } }
            if !mergeMeshes(builders, with: { $0.xor($1) }, callback: callback) {
                return false
            }
        case .difference:
            let builders = children.map { child in { child.flatten(with: self.material) } }
            if !reduceMeshes(builders, with: { $0.subtract($1) }, callback: callback) {
                return false
            }
        case .intersection:
            let builders = children.map { child in { child.flatten(with: self.material) } }
            if !reduceMeshes(builders, with: { $0.intersect($1) }, callback: callback) {
                return false
            }
        case .stencil:
            var builders = children.map { child in { child.flatten(with: self.material) } }
            mesh = builders.first?()
            if let m = mesh {
                builders[0] = { m }
            }
            if !reduceMeshes(builders, with: { $0.stencil($1) }, callback: callback) {
                return false
            }
        case let .mesh(mesh):
            self.mesh = mesh
        }
        let m = mesh
        meshQueue.async { meshCache[self.cacheKey] = m }
        return callback()
    }

    // external data, e.g. SCNGeometry
    var associatedData: Any?

    public init(type: GeometryType,
                name: String?,
                transform: Transform,
                material: Material,
                children: [Geometry],
                sourceLocation: SourceLocation?)
    {
        var material = material
        switch type {
        case .cone, .cylinder, .sphere, .cube, .extrude, .lathe, .loft, .fill, .path:
            renderChildren = true
        case let .mesh(mesh):
            renderChildren = true
            material = mesh.polygons.first?.material as? Material ?? material
        case .none:
            renderChildren = true
            material = children.first?.material ?? .default
        case .union, .xor, .difference, .intersection, .stencil:
            renderChildren = false
            material = children.first?.material ?? .default
        }

        self.type = type
        self.name = name
        self.transform = transform
        self.material = material
        self.children = children
        self.sourceLocation = sourceLocation

        var isOpaque = material.isOpaque
        func flattenedCacheKey(for geometry: Geometry) -> MeshCacheKey {
            isOpaque = isOpaque && geometry.material.isOpaque
            return MeshCacheKey(
                type: geometry.type,
                material: geometry.material == material ? nil : geometry.material,
                transform: geometry.transform,
                children: geometry.children.map(flattenedCacheKey)
            )
        }

        cacheKey = MeshCacheKey(
            type: type,
            material: nil,
            transform: .identity,
            children: renderChildren ? [] : children.map(flattenedCacheKey)
        )

        // Must be set after cache key is generated
        self.isOpaque = isOpaque
    }

    // TODO: make this more efficient, and interruptible
    public func flatten(with material: Material?) -> Mesh {
        var result = mesh ?? Mesh([])
        if renderChildren {
            result = .union([result] + children.map { $0.flatten(with: material) })
        }
        if material != self.material {
            result = result.replacing(nil, with: self.material)
        }
        return result.transformed(by: transform)
    }

    public func merged() -> Mesh {
        var result = mesh ?? Mesh([])
        if renderChildren {
            children.forEach {
                result = result.merge($0.merged())
            }
        }
        return result
            .replacing(nil, with: material)
            .transformed(by: transform)
    }
}

// MARK: Stats

public extension Geometry {
    var objectCount: Int {
        if type == .none {
            var count = 0
            for child in children {
                count += child.objectCount
            }
            return count
        } else {
            return 1
        }
    }

    var polygonCount: Int {
        var count = mesh?.polygons.count ?? 0
        for child in children {
            count += child.polygonCount
        }
        return count
    }

    var triangleCount: Int {
        var count = 0
        for polygon in mesh?.polygons ?? [] {
            count += polygon.triangulate().count
        }
        for child in children {
            count += child.triangleCount
        }
        return count
    }

    var exactBounds: Bounds {
        merged().bounds
    }
}
