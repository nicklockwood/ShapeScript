//
//  Geometry.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public final class Geometry: Hashable {
    public let type: GeometryType
    public let name: String?
    public let transform: Transform
    public let material: Material
    public let children: [Geometry]
    public let isOpaque: Bool // Computed
    public let sourceLocation: SourceLocation?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(name)
        hasher.combine(transform)
        hasher.combine(material)
        hasher.combine(children)
    }

    public static func == (lhs: Geometry, rhs: Geometry) -> Bool {
        if lhs === rhs {
            return true
        }
        // TODO: Find a way to synthesize this logic
        guard lhs.type == rhs.type,
              lhs.name == rhs.name,
              lhs.transform == rhs.transform,
              lhs.material == rhs.material,
              lhs.children == rhs.children,
              lhs.isOpaque == rhs.isOpaque,
              lhs.sourceLocation == rhs.sourceLocation
        else {
            return false
        }
        return true
    }

    /// Whether children should be rendered separately or are included in mesh
    public var renderChildren: Bool {
        switch type {
        case .cone, .cylinder, .sphere, .cube,
             .lathe, .loft, .path, .mesh, .group:
            return true
        case .intersection, .difference, .stencil:
            return false
        case .union, .xor, .extrude, .fill:
            return mesh == nil
        }
    }

    // Render with debug mode
    var debug: Bool {
        didSet {
            if debug, type == .group {
                children.forEach { $0.debug = true }
            }
        }
    }

    let cacheKey: GeometryCache.Key
    var cache: GeometryCache? {
        didSet {
            children.forEach { $0.cache = cache }
        }
    }

    private let lock: NSLock = .init()
    private var _mesh: Mesh?
    private(set) var mesh: Mesh? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _mesh
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _mesh = newValue
            _associatedData = nil
        }
    }

    // External data, e.g. SCNGeometry
    private var _associatedData: Any?
    var associatedData: Any? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _associatedData
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _associatedData = newValue
        }
    }

    public init(type: GeometryType,
                name: String?,
                transform: Transform,
                material: Material,
                children: [Geometry],
                sourceLocation: SourceLocation?,
                debug: Bool = false)
    {
        var material = material
        var children = children
        var type = type
        switch type {
        case let .extrude(paths, along):
            let along = along.flatMap { $0.subpaths }
            switch (paths.count, along.count) {
            case (0, 0):
                break
            case (1, 1), (1, 0):
                assert(children.isEmpty)
            case (_, 0):
                assert(children.isEmpty)
                type = .extrude([], along: [])
                children = paths.map { path in
                    Geometry(
                        type: .extrude([path], along: []),
                        name: nil,
                        transform: .identity,
                        material: material,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
            default:
                assert(children.isEmpty)
                type = .extrude([], along: [])
                children = along.flatMap { along in
                    paths.map { path in
                        Geometry(
                            type: .extrude([path], along: [along]),
                            name: nil,
                            transform: .identity,
                            material: material,
                            children: [],
                            sourceLocation: sourceLocation
                        )
                    }
                }
            }
        case let .lathe(paths, segments):
            switch paths.count {
            case 0:
                break
            case 1:
                assert(children.isEmpty)
            default:
                assert(children.isEmpty)
                type = .lathe([], segments: 0)
                children = paths.map {
                    Geometry(
                        type: .lathe([$0], segments: segments),
                        name: nil,
                        transform: .identity,
                        material: material,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
            }
        case let .fill(paths):
            switch paths.count {
            case 0:
                break
            case 1:
                assert(children.isEmpty)
            default:
                assert(children.isEmpty)
                type = .fill([])
                children = paths.map {
                    Geometry(
                        type: .fill([$0]),
                        name: nil,
                        transform: .identity,
                        material: material,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
            }
        case .cone, .cylinder, .sphere, .cube, .loft, .path:
            assert(children.isEmpty)
        case let .mesh(mesh):
            material = mesh.polygons.first?.material as? Material ?? material
        case .union, .xor, .difference, .intersection, .stencil:
            material = children.first?.material ?? .default
        case .group:
            if debug {
                children.forEach { $0.debug = true }
            }
        }

        self.type = type
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.transform = transform
        self.material = material
        self.children = children
        self.sourceLocation = sourceLocation
        self.debug = debug

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
            children: type.isLeafGeometry ? [] : children.map(flattenedCacheKey)
        )

        // Must be set after cache key is generated
        self.isOpaque = isOpaque
    }
}

public extension Geometry {
    var isEmpty: Bool {
        type.isEmpty && children.allSatisfy { $0.isEmpty }
    }

    var bounds: Bounds {
        switch type {
        case .difference, .stencil:
            return children.first.map { $0.bounds.transformed(by: $0.transform) } ?? .empty
        case .intersection:
            var bounds = children.first.map { $0.bounds.transformed(by: $0.transform) } ?? .empty
            for child in children.dropFirst() {
                bounds.formIntersection(child.bounds.transformed(by: child.transform))
            }
            return bounds
        case .union, .xor, .group:
            var bounds = Bounds.empty
            for child in children {
                bounds.formUnion(child.bounds.transformed(by: child.transform))
            }
            return bounds
        case .cone, .cube, .cylinder, .sphere, .extrude, .lathe, .loft, .fill, .path, .mesh:
            var bounds = type.bounds
            for child in children {
                bounds.formUnion(child.bounds.transformed(by: child.transform))
            }
            return bounds
        }
    }

    internal func gatherNamedObjects(_ dictionary: inout [String: Geometry]) {
        if let name = self.name {
            dictionary[name] = self
        }
        children.forEach { $0.gatherNamedObjects(&dictionary) }
    }

    var childDebug: Bool {
        debug || children.contains(where: { $0.childDebug })
    }

    func transformed(by transform: Transform) -> Geometry {
        Geometry(
            type: type,
            name: name,
            transform: self.transform * transform,
            material: material,
            children: children,
            sourceLocation: sourceLocation,
            debug: debug
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
        if type.isLeafGeometry {
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
        if type.isLeafGeometry {
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
        if type.isLeafGeometry, !buildMesh(callback) {
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
        case let .extrude(paths, along) where paths.isEmpty && along.count <= 1:
            mesh = nil
        case let .lathe(paths, _) where paths.isEmpty,
             let .fill(paths) where paths.isEmpty:
            mesh = nil
        case .group, .path, .mesh,
             .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(type.isLeafGeometry) // Leaves
        case .stencil, .difference:
            mesh = children.first?.merged(callback)
        case .union, .xor, .intersection:
            mesh = nil
        }
        return callback()
    }

    // Build final pass
    func buildFinal(_ callback: @escaping () -> Bool) -> Bool {
        for child in children where !child.buildFinal(callback) {
            return false
        }
        if !type.isLeafGeometry {
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
        case .group, .path:
            mesh = Mesh([])
        case let .cone(segments):
            mesh = .cone(slices: segments)
        case let .cylinder(segments):
            mesh = .cylinder(slices: segments)
        case let .sphere(segments):
            mesh = .sphere(slices: segments, stacks: segments / 2)
        case .cube:
            mesh = .cube()
        case let .extrude(paths, along: along) where paths.count == 1 && along.count <= 1:
            assert(along.reduce(0) { $0 + $1.subpaths.count } <= 1)
            mesh = along.first.map { .extrude(paths[0], along: $0) } ?? .extrude(paths[0])
        case let .lathe(paths, segments: segments) where paths.count == 1:
            mesh = .lathe(paths[0], slices: segments)
        case let .loft(paths):
            mesh = Mesh.loft(paths)
        case let .fill(paths) where paths.count == 1:
            mesh = .fill(paths[0].closed())
        case .union, .extrude, .lathe, .fill:
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
            sourceLocation: self.sourceLocation ?? sourceLocation,
            debug: debug
        )
        copy.mesh = mesh
        copy.associatedData = associatedData
        return copy
    }
}

// MARK: Stats

public extension Geometry {
    var objectCount: Int {
        if case .group = type {
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
