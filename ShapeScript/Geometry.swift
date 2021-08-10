//
//  Geometry.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

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
                    let offset = path.faceNormal / 2
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

public final class Geometry {
    public let type: GeometryType
    public let name: String?
    public let transform: Transform
    public let material: Material
    public let children: [Geometry]
    public let isOpaque: Bool
    public let sourceLocation: SourceLocation?
    public let renderChildren: Bool
    public var isSelected: Bool = false

    let cacheKey: GeometryCache.Key
    var cache: GeometryCache? {
        didSet {
            children.forEach { $0.cache = cache }
        }
    }

    private(set) var mesh: Mesh? {
        didSet {
            associatedData = nil
        }
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
        func flattenedCacheKey(for geometry: Geometry) -> GeometryCache.Key {
            isOpaque = isOpaque && geometry.material.isOpaque
            return GeometryCache.Key(
                type: geometry.type,
                material: geometry.material == material ? nil : geometry.material,
                transform: geometry.transform,
                children: geometry.children.map(flattenedCacheKey)
            )
        }

        cacheKey = GeometryCache.Key(
            type: type,
            material: nil,
            transform: .identity,
            children: renderChildren ? [] : children.map(flattenedCacheKey)
        )

        // Must be set after cache key is generated
        self.isOpaque = isOpaque
    }
}

public extension Geometry {
    var isEmpty: Bool {
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

    var bounds: Bounds {
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

    func transformed(by transform: Transform) -> Geometry {
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

    func with(
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

    func deepCopy() -> Geometry {
        let copy = Geometry(
            type: type,
            name: name,
            transform: transform,
            material: material,
            children: children.map { $0.deepCopy() },
            sourceLocation: sourceLocation
        )
        copy.cache = cache
        copy.mesh = mesh
        copy.associatedData = associatedData
        copy.isSelected = isSelected
        return copy
    }

    var path: Path? {
        guard case let .path(path) = type else {
            return nil
        }
        return path
    }

    func build(_ callback: @escaping () -> Bool) -> Bool {
        buildLeaves(callback) && buildPreview(callback) && buildFinal(callback)
    }

    @available(*, deprecated, message: "Use flattened() instead")
    func flatten(with material: Material?, callback: @escaping () -> Bool) -> Mesh {
        flattened(with: material, callback)
    }

    func flattened(_ callback: @escaping () -> Bool = { true }) -> Mesh {
        flattened(with: material, callback)
    }

    func merged(_ callback: @escaping () -> Bool = { true }) -> Mesh {
        var result = mesh ?? Mesh([])
        if renderChildren {
            result = result.merge(mergedChildren(callback))
        }
        return result
            .replacing(nil, with: material)
            .transformed(by: transform)
    }
}

private extension Collection where Element == Geometry {
    func flattened(with material: Material?, _ callback: @escaping () -> Bool) -> [Mesh] {
        compactMap { callback() ? $0.flattened(with: material, callback) : nil }
    }

    func meshes(with material: Material?, _ callback: @escaping () -> Bool) -> [Mesh] {
        flatMap { callback() ? $0.meshes(with: material, callback) : [] }
    }

    func merged(_ callback: @escaping () -> Bool) -> Mesh {
        var result = Mesh([])
        for child in self where callback() {
            result = result.merge(child.merged(callback))
        }
        return result
    }
}

private extension Geometry {
    func flattenedChildren(_ callback: @escaping () -> Bool) -> [Mesh] {
        children.flattened(with: material, callback)
    }

    func mergedChildren(_ callback: @escaping () -> Bool) -> Mesh {
        children.merged(callback)
    }

    func flattenedFirstChild(_ callback: @escaping () -> Bool) -> Mesh {
        children.first.map { $0.flattened(with: self.material, callback) } ?? Mesh([])
    }

    func childMeshes(_ callback: @escaping () -> Bool) -> [Mesh] {
        children.meshes(with: material, callback)
    }

    func flattened(with material: Material?, _ callback: @escaping () -> Bool) -> Mesh {
        .union(meshes(with: material, callback), isCancelled: { !callback() })
    }

    func meshes(with material: Material?, _ callback: @escaping () -> Bool) -> [Mesh] {
        var meshes = [Mesh]()
        if var mesh = mesh {
            mesh = mesh.transformed(by: transform)
            if material != self.material {
                mesh = mesh.replacing(nil, with: self.material)
            }
            meshes.append(mesh)
        }
        if renderChildren {
            meshes += childMeshes(callback).map {
                let mesh = $0.transformed(by: transform)
                if material != self.material {
                    return mesh.replacing(nil, with: self.material)
                }
                return mesh
            }
        }
        return meshes
    }

    // Build all geometries that don't have dependencies
    func buildLeaves(_ callback: @escaping () -> Bool) -> Bool {
        if renderChildren, !buildMesh(callback) {
            return false
        }
        for child in children where !child.buildLeaves(callback) {
            return false
        }
        return true
    }

    // With leaves built, do a rough preview
    func buildPreview(_ callback: @escaping () -> Bool) -> Bool {
        for child in children where !child.buildPreview(callback) {
            return false
        }
        if let mesh = cache?[self] {
            self.mesh = mesh
            return callback()
        }
        switch type {
        case .none, .path, .mesh,
             .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(renderChildren) // Leaves
        case .union, .xor:
            mesh = mergedChildren(callback)
        case .stencil, .difference:
            mesh = children.first?.merged(callback)
        case .intersection:
            mesh = nil
        }
        return callback()
    }

    // Build final pass
    func buildFinal(_ callback: @escaping () -> Bool) -> Bool {
        for child in children where !child.buildFinal(callback) {
            return false
        }
        if !renderChildren {
            return buildMesh(callback)
        }
        return callback()
    }

    // Build mesh (without children)
    func buildMesh(_ callback: @escaping () -> Bool) -> Bool {
        if let mesh = cache?[self] {
            self.mesh = mesh
            return callback()
        }
        let isCancelled = { !callback() }
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
            let meshes = along.isEmpty ? paths.map {
                Mesh.extrude($0, depth: 1)
            } : along.flatMap { along in
                paths.map { Mesh.extrude($0, along: along) }
            }
            mesh = .union(meshes, isCancelled: isCancelled)
        case let .lathe(paths, segments: segments):
            mesh = .union(paths.map { .lathe($0, slices: segments) }, isCancelled: isCancelled)
        case let .loft(paths):
            mesh = Mesh.loft(paths)
        case let .fill(paths):
            mesh = .union(paths.map { .fill($0.closed()) }, isCancelled: isCancelled)
        case .union:
            mesh = .union(childMeshes(callback), isCancelled: isCancelled)
        case .xor:
            mesh = .xor(flattenedChildren(callback), isCancelled: isCancelled)
        case .difference:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = .difference(meshes, isCancelled: isCancelled)
        case .intersection:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = .intersection(meshes, isCancelled: isCancelled)
        case .stencil:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = .stencil(meshes, isCancelled: isCancelled)
        case let .mesh(mesh):
            self.mesh = mesh
        }
        if callback() {
            cache?[self] = mesh
            return true
        }
        return false
    }

    func _with(
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
