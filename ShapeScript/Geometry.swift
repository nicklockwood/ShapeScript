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
    public let smoothing: Angle?
    public let children: [Geometry]
    public let isOpaque: Bool // Computed
    private let _sourceLocation: (() -> SourceLocation?)?
    public private(set) lazy var sourceLocation: SourceLocation? = _sourceLocation?()
    public private(set) weak var parent: Geometry?

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
        guard lhs.type == rhs.type,
              lhs.name == rhs.name,
              lhs.transform == rhs.transform,
              lhs.material == rhs.material,
              lhs.children == rhs.children
        // Exclude isOpaque, sourceLocation and parent
        else {
            return false
        }
        return true
    }

    /// Whether children should be rendered separately or are included in mesh
    public var renderChildren: Bool {
        switch type {
        case .group:
            return true
        case .cone, .cylinder, .sphere, .cube,
             .lathe, .loft, .path, .mesh, .camera, .light,
             .intersection, .difference, .stencil:
            return false
        case .union, .xor, .extrude, .fill, .hull:
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
            if let data = _associatedData {
                return data
            }
            _associatedData = cache?[associatedData: self]
            return _associatedData
        }
        set {
            cache?[associatedData: self] = newValue
            lock.lock()
            defer { lock.unlock() }
            _associatedData = newValue
        }
    }

    public init(
        type: GeometryType,
        name: String?,
        transform: Transform,
        material: Material,
        smoothing: Angle?,
        children: [Geometry],
        sourceLocation: (() -> SourceLocation?)?,
        debug: Bool = false
    ) {
        var material = material
        var children = children
        var type = type
        switch type {
        case var .extrude(paths, options):
            (paths, material) = paths.fixupColors(material: material)
            (options.along, material) = options.along.fixupColors(material: material)
            type = .extrude(paths, options)
            switch (paths.count, options.along.count) {
            case (0, 0):
                break
            case (1, _), (_, 0):
                assert(children.isEmpty)
            default:
                assert(children.isEmpty)
                type = .extrude([], .default)
                children = paths.map { path in
                    Geometry(
                        type: .extrude([path], options),
                        name: nil,
                        transform: .identity,
                        material: material,
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
            }
        case .lathe(var paths, let segments):
            (paths, material) = paths.fixupColors(material: material)
            type = .lathe(paths, segments: segments)
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
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
            }
        case var .fill(paths):
            (paths, material) = paths.fixupColors(material: material)
            type = .fill(paths)
            switch paths.count {
            case 0:
                break
            default:
                assert(children.isEmpty)
            }
        case .hull:
            break // TODO: what needs to be done here?
        case .cone, .cylinder, .sphere, .cube, .loft, .path, .camera, .light:
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
        self.smoothing = smoothing
        self.children = children
        self._sourceLocation = sourceLocation
        self.debug = debug

        var isOpaque = material.isOpaque
        func flattenedCacheKey(for geometry: Geometry) -> GeometryCache.Key {
            isOpaque = isOpaque && geometry.material.isOpaque
            return GeometryCache.Key(
                type: geometry.type,
                material: geometry.material == material ? nil : geometry.material,
                smoothing: geometry.smoothing,
                transform: geometry.transform,
                flipped: geometry.transform.isFlipped,
                children: geometry.children.map(flattenedCacheKey)
            )
        }

        self.cacheKey = GeometryCache.Key(
            type: type,
            material: nil,
            smoothing: smoothing,
            transform: .identity,
            flipped: transform.isFlipped,
            children: type.isLeafGeometry ? [] : children.map(flattenedCacheKey)
        )

        // Must be set after cache key is generated
        self.isOpaque = isOpaque

        // Must be set after all other properties
        children.forEach { $0.parent = self }
    }
}

public extension Geometry {
    var isEmpty: Bool {
        type.isEmpty && children.allSatisfy { $0.isEmpty }
    }

    /// Returns the overestimated Geometry bounds *without* the local transform applied
    var bounds: Bounds {
        switch type {
        case .difference, .stencil:
            return children.first.map {
                $0.bounds.transformed(by: $0.transform)
            } ?? .empty
        case .intersection:
            return children.dropFirst().reduce(into: children.first.map {
                $0.bounds.transformed(by: $0.transform)
            } ?? .empty) { bounds, child in
                bounds.formIntersection(child.bounds.transformed(by: child.transform))
            }
        case .union, .xor, .group:
            return Bounds(children.map {
                $0.bounds.transformed(by: $0.transform)
            })
        case .lathe, .fill, .extrude, .loft, .hull:
            return type.bounds.union(Bounds(children.map {
                $0.bounds.transformed(by: $0.transform)
            }))
        case .cone, .cube, .cylinder, .sphere, .path, .mesh:
            return type.bounds
        case .camera, .light:
            return .empty
        }
    }

    var camera: Camera? {
        guard case let .camera(camera) = type else {
            return nil
        }
        return camera
    }

    var light: Light? {
        guard case let .light(light) = type else {
            return nil
        }
        return light
    }

    var worldTransform: Transform {
        (parent?.worldTransform ?? .identity) * transform
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
            smoothing: smoothing,
            children: children,
            sourceLocation: _sourceLocation,
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
        return children.allSatisfy {
            $0.hasUniformMaterial(material ?? self.material)
        }
    }

    /// Deprecated, do not use.
    @available(*, deprecated, message: "No longer needed")
    func with(name: String?) -> Geometry {
        _with(
            name: name,
            transform: nil,
            material: nil,
            sourceLocation: nil,
            removingLights: false,
            removingGroupTransform: false
        )
    }

    func with(
        transform: Transform,
        material: Material?,
        sourceLocation: @escaping () -> SourceLocation?
    ) -> Geometry {
        var material = material
        if material != nil, !hasUniformMaterial() {
            material?.diffuse = nil
        }
        return _with(
            name: nil,
            transform: transform,
            material: material,
            sourceLocation: sourceLocation,
            removingLights: false,
            removingGroupTransform: false
        )
    }

    /// Returns a copy of the geometry with light nodes removed
    func withoutLights() -> Geometry {
        _with(
            name: nil,
            transform: nil,
            material: nil,
            sourceLocation: nil,
            removingLights: true,
            removingGroupTransform: false
        )
    }

    /// Returns a copy of the geometry with group transforms transferred to their children
    func withoutGroupTransform() -> Geometry {
        _with(
            name: nil,
            transform: nil,
            material: nil,
            sourceLocation: nil,
            removingLights: false,
            removingGroupTransform: true
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

    func flattened(_ callback: @escaping () -> Bool = { true }) -> Mesh {
        flattened(with: material, callback)
    }

    func merged(_ callback: @escaping () -> Bool = { true }) -> Mesh {
        var result = mesh ?? .empty
        if type.isLeafGeometry {
            result = result.merge(mergedChildren(callback))
        }
        return result
            .replacing(nil, with: material)
            .transformed(by: transform)
    }
}

extension Geometry {
    func gatherNamedObjects(_ dictionary: inout [String: Geometry]) {
        if let name = name {
            dictionary[name] = self
        }
        children.forEach { $0.gatherNamedObjects(&dictionary) }
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
        var result = Mesh.empty
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
        children.first.map { $0.flattened(with: self.material, callback) } ?? .empty
    }

    func childMeshes(_ callback: @escaping () -> Bool) -> [Mesh] {
        children.meshes(with: material, callback)
    }

    func flattened(with material: Material?, _ callback: @escaping () -> Bool) -> Mesh {
        .union(meshes(with: material, callback), isCancelled: { !callback() })
    }

    func meshes(with material: Material?, _ callback: @escaping () -> Bool) -> [Mesh] {
        var meshes = [Mesh]()
        if var mesh = mesh, mesh != .empty {
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
        if let mesh = cache?[mesh: self] {
            self.mesh = mesh
            return callback()
        }
        switch type {
        case .extrude([], _), .lathe([], _), .fill([]):
            mesh = nil
        case .hull:
            mesh = nil
        case .group, .path, .mesh,
             .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(type.isLeafGeometry) // Leaves
        case .stencil, .difference:
            mesh = children.first?.merged(callback)
        case .union, .xor, .intersection, .camera, .light:
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
        if let mesh = cache?[mesh: self] {
            self.mesh = mesh
            return callback()
        }
        let isCancelled = { !callback() }
        switch type {
        case .group, .path, .camera, .light:
            mesh = .empty
        case let .cone(segments):
            mesh = .cone(slices: segments)
        case let .cylinder(segments):
            mesh = .cylinder(slices: segments)
        case let .sphere(segments):
            mesh = .sphere(slices: segments, stacks: segments / 2)
        case .cube:
            mesh = .cube()
        case let .extrude(paths, .default) where paths.count >= 1:
            mesh = Mesh.extrude(paths, isCancelled: isCancelled).makeWatertight()
        case let .extrude(paths, options) where paths.count == 1:
            mesh = Mesh.merge(options.along.map { along in
                Mesh.extrude(
                    paths[0],
                    along: along,
                    twist: options.twist,
                    align: options.align,
                    isCancelled: isCancelled
                ).makeWatertight()
            })
        case let .lathe(paths, segments: segments) where paths.count == 1:
            mesh = Mesh.lathe(paths[0], slices: segments).makeWatertight()
        case let .loft(paths):
            mesh = Mesh.loft(paths).makeWatertight()
        case let .hull(vertices):
            let meshes = childMeshes(callback)
            let vertices = vertices + meshes.flatMap { $0.polygons.flatMap { $0.vertices } }
            mesh = Mesh.convexHull(of: vertices, material: material).makeWatertight()
        case let .fill(paths):
            mesh = Mesh.fill(paths.map { $0.closed() }, isCancelled: isCancelled).makeWatertight()
        case .union, .lathe, .extrude:
            mesh = Mesh.union(childMeshes(callback), isCancelled: isCancelled).makeWatertight()
        case .xor:
            mesh = Mesh.symmetricDifference(flattenedChildren(callback), isCancelled: isCancelled).makeWatertight()
        case .difference:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = Mesh.difference(meshes, isCancelled: isCancelled).makeWatertight()
        case .intersection:
            let meshes = flattenedChildren(callback)
            mesh = Mesh.intersection(meshes, isCancelled: isCancelled).makeWatertight()
        case .stencil:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = Mesh.stencil(meshes, isCancelled: isCancelled).makeWatertight()
        case let .mesh(mesh):
            self.mesh = mesh
        }
        if callback() {
            if let smoothing = smoothing {
                mesh = mesh?.smoothingNormals(forAnglesGreaterThan: smoothing)
            }
            cache?[mesh: self] = mesh
            return true
        }
        return false
    }

    func _with(
        name: String?,
        transform: Transform?,
        material: Material?,
        sourceLocation: (() -> SourceLocation?)?,
        removingLights: Bool,
        removingGroupTransform: Bool
    ) -> Geometry {
        var type = self.type
        if removingLights, case .light = type {
            preconditionFailure()
        }
        var m = self.material
        if let material = material, case let .mesh(mesh) = type {
            m.opacity *= material.opacity
            m.diffuse = material.diffuse ?? self.material.diffuse
            type = .mesh(mesh.replacing(self.material, with: m))
        }
        var transform = transform.map { self.transform * $0 } ?? self.transform
        var childTransform = Transform.identity
        if case .group = type, removingGroupTransform {
            childTransform = transform
            transform = .identity
        }
        let copy = Geometry(
            type: type,
            name: name ?? self.name,
            transform: transform,
            material: m,
            smoothing: smoothing,
            children: children.compactMap {
                if case .light = $0.type, removingLights {
                    return nil
                }
                return $0._with(
                    name: nil,
                    transform: childTransform,
                    material: material,
                    sourceLocation: sourceLocation,
                    removingLights: removingLights,
                    removingGroupTransform: removingGroupTransform
                )
            },
            sourceLocation: _sourceLocation ?? sourceLocation,
            debug: debug
        )
        copy.mesh = mesh
        return copy
    }
}

private extension Collection where Element == Path {
    func fixupColors(material: Material) -> ([Path], Material) {
        guard material.texture == nil else {
            return (Array(self), material)
        }
        var current: Color?
        for path in self {
            for point in path.points {
                if current == nil {
                    current = point.color
                } else if point.color != current {
                    var material = material
                    material.diffuse = .color(.white)
                    return (Array(self), material)
                }
            }
        }
        var material = material
        material.diffuse = (current ?? material.color).map { .color($0) }
        return (map { $0.withColor(nil) }, material)
    }
}

// MARK: Stats

public extension Geometry {
    var hasMesh: Bool {
        switch type {
        case .camera, .light, .path:
            return false
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull,
             .union, .difference, .intersection, .xor, .stencil,
             .group, .mesh:
            return true
        }
    }

    var objectCount: Int {
        switch type {
        case .group:
            return children.reduce(0) { $0 + $1.objectCount }
        case .camera, .light:
            return 0
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull,
             .union, .difference, .intersection, .xor, .stencil,
             .path, .mesh:
            return 1
        }
    }

    var polygonCount: Int {
        if let mesh = mesh, !mesh.polygons.isEmpty {
            return mesh.polygons.count
        }
        return children.reduce(0) { $0 + $1.polygonCount }
    }

    var triangleCount: Int {
        if let mesh = mesh, !mesh.polygons.isEmpty {
            return mesh.polygons.reduce(0) { $0 + $1.vertices.count - 2 }
        }
        return children.reduce(0) { $0 + $1.triangleCount }
    }

    var childCount: Int {
        switch type {
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .fill, .loft,
             .mesh, .path, .camera, .light:
            return 0 // TODO: should paths/points be treated as children?
        case .union, .xor, .difference, .intersection, .stencil, .group, .hull:
            return children.count
        }
    }

    /// Returns the exact bounds with specified transform
    func exactBounds(
        with transform: Transform,
        _ callback: @escaping () -> Bool = { true }
    ) -> Bounds {
        switch type {
        case .camera, .light:
            return .empty
        case let .extrude(paths, _) where paths.count >= 1,
             let .lathe(paths, _) where paths.count >= 1:
            fallthrough
        case .cone, .cylinder, .sphere, .cube, .mesh:
            if transform.rotation == .identity {
                return type.bounds.transformed(by: transform)
            }
            return Bounds(type.representativePoints.transformed(by: transform))
        case .hull:
            var bounds = Bounds(type.representativePoints.transformed(by: transform))
            for child in children {
                bounds.formUnion(child.exactBounds(with: child.transform * transform))
            }
            return bounds
        case let .path(path):
            return path.transformed(by: transform).bounds
        case let .fill(paths), let .loft(paths):
            return paths.transformed(by: transform).bounds
        case .group, .union, .lathe, .extrude:
            return Bounds(children.map {
                $0.exactBounds(with: $0.transform * transform)
            })
        case .xor, .difference, .intersection:
            _ = build(callback)
            if transform.rotation == .identity {
                return mesh?.bounds.transformed(by: transform) ?? .empty
            }
            return mesh?.transformed(by: transform).bounds ?? .empty
        case .stencil:
            return children.first.map {
                $0.exactBounds(with: $0.transform * transform)
            } ?? .empty
        }
    }

    /// Returns the exact bounds transformed to world coordinates
    @available(*, deprecated, message: "Use exactBounds(with:) instead")
    var exactBounds: Bounds {
        if let mesh = mesh, !mesh.polygons.isEmpty {
            if worldTransform.rotation == .identity {
                return mesh.bounds.transformed(by: worldTransform)
            }
            return mesh.transformed(by: worldTransform).bounds
        } else if let path = path {
            return path.bounds
        }
        let bounds = children.map { $0.exactBounds }
        return Bounds(bounds: bounds)
    }

    var isWatertight: Bool {
        if let mesh = mesh, !mesh.polygons.isEmpty {
            return mesh.isWatertight
        }
        return children.reduce(true) { $0 && $1.isWatertight }
    }
}
