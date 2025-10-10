//
//  Geometry.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public typealias Polygon = Euclid.Polygon

/// Cancellation handler - return true to cancel
public typealias CancellationHandler = () -> Bool

/// Legacy callback type - return false to cancel
public typealias LegacyCallback = () -> Bool

public final class Geometry: Hashable {
    public let type: GeometryType
    public let name: String?
    public let transform: Transform
    public let material: Material
    public let smoothing: Angle?
    public let children: [Geometry]
    public let isOpaque: Bool // Computed
    /// The overestimated Geometry bounds *without* the local transform applied
    public let bounds: Bounds
    private let _sourceLocation: (() -> SourceLocation?)?
    public private(set) lazy var sourceLocation: SourceLocation? = _sourceLocation?()
    public private(set) weak var parent: Geometry?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(name)
        hasher.combine(transform)
        hasher.combine(material)
        hasher.combine(smoothing)
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
              lhs.smoothing == rhs.smoothing,
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
        case .lathe, .intersection, .difference, .stencil, .minkowski:
            return false
        case .loft, .union, .xor, .extrude, .fill, .hull:
            return mesh == nil
        case .cone, .cylinder, .sphere, .cube, .path, .mesh, .camera, .light:
            return false // These don't have children
        }
    }

    /// Render with debug mode
    var debug: Bool {
        didSet {
            if debug, type == .group {
                children.forEach { $0.debug = true }
            }
        }
    }

    let cacheKey: GeometryCache.Key

    /// The cache used for storing computed meshes
    var cache: GeometryCache? {
        didSet {
            children.forEach { $0.cache = cache }
        }
    }

    private let lock: NSLock = .init()
    private var _mesh: Mesh?

    /// Returns the pre-built mesh
    /// If the mesh has not yet been built, this will return nil
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

    private var _associatedData: Any?

    /// External data, e.g. SCNGeometry
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
        var useMaterialForCache = false
        var children = children
        var type = type
        switch type {
        case var .extrude(paths, options):
            switch (paths.count, options.along.count) {
            case (0, 0):
                break
            case (1, 0):
                (paths, material) = paths.vertexColorsToMaterial(material: material)
                type = .extrude(paths, options)
            case (1, 1):
                var pair = (paths + options.along)
                (pair, material) = pair.vertexColorsToMaterial(material: material)
                options.along = [pair[1]]
                type = .extrude([pair[0]], options)
            case (_, 0):
                type = .extrude([], .default)
                children = paths.map { path in
                    let (path, material) = path.vertexColorsToMaterial(material: material)
                    return Geometry(
                        type: .extrude([path], options),
                        name: nil,
                        transform: .identity,
                        material: material,
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
                material = children.first?.material ?? .default
            default:
                // For extrusions with multiple paths, convert each path to a
                // separate child geometry so they can be renderered individually
                type = .extrude([], .default)
                children = paths.flatMap { path in
                    options.along.map { along in
                        let (pair, material) = [path, along].vertexColorsToMaterial(material: material)
                        var options = options
                        options.along = [pair[1]]
                        return Geometry(
                            type: .extrude([pair[0]], options),
                            name: nil,
                            transform: .identity,
                            material: material,
                            smoothing: smoothing,
                            children: [],
                            sourceLocation: sourceLocation
                        )
                    }
                }
                material = children.first?.material ?? .default
            }
        case .lathe(var paths, let segments):
            switch paths.count {
            case 0:
                break
            case 1:
                (paths, material) = paths.vertexColorsToMaterial(material: material)
                type = .lathe(paths, segments: segments)
            default:
                // For lathes with multiple paths, convert each path to a
                // separate child geometry so they can be renderered individually
                type = .lathe([], segments: 0)
                children = paths.map { path in
                    let (path, material) = path.vertexColorsToMaterial(material: material)
                    return Geometry(
                        type: .lathe([path], segments: segments),
                        name: nil,
                        transform: .identity,
                        material: material,
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
                material = children.first?.material ?? .default
            }
        case var .fill(paths):
            switch paths.count {
            case 0:
                break
            case 1:
                (paths, material) = paths.vertexColorsToMaterial(material: material)
                type = .fill(paths)
            default:
                // For fills with multiple paths, convert each path to a
                // separate child geometry so they can be renderered individually
                type = .fill([])
                children = paths.map { path in
                    let (path, material) = path.vertexColorsToMaterial(material: material)
                    return Geometry(
                        type: .fill([path]),
                        name: nil,
                        transform: .identity,
                        material: material,
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
                material = children.first?.material ?? .default
            }
        case var .loft(paths):
            (paths, material) = paths.vertexColorsToMaterial(material: material)
            type = .loft(paths)
        case var .path(path):
            (path, material) = path.vertexColorsToMaterial(material: material)
            type = .path(path)
        case let .mesh(mesh):
            material = mesh.polygons.first?.material as? Material ?? material
        case .hull, .minkowski:
            useMaterialForCache = true
        case .union, .xor, .difference, .intersection, .stencil:
            material = children.first?.material ?? .default
        case .group:
            if debug {
                children.forEach { $0.debug = true }
            }
        case .cone, .cylinder, .sphere, .cube, .camera, .light:
            break
        }

        self.type = type
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.transform = transform
        self.material = material
        self.smoothing = smoothing
        self.children = children
        self._sourceLocation = sourceLocation
        self.debug = debug

        var hasVariedMaterials = false
        var isOpaque = material.isOpaque
        func flattenedCacheKey(for geometry: Geometry) -> GeometryCache.Key {
            isOpaque = isOpaque && geometry.material.isOpaque
            if !hasVariedMaterials, geometry.material != material {
                hasVariedMaterials = true
            }
            return GeometryCache.Key(
                type: geometry.type,
                material: geometry.material == material ? nil : geometry.material,
                smoothing: geometry.smoothing,
                transform: geometry.transform,
                flipped: geometry.transform.isFlipped,
                children: geometry.children.map(flattenedCacheKey)
            )
        }

        let childKeys = type.isLeafGeometry ? [] : children.map(flattenedCacheKey)

        // Must be set after child keys are generated
        self.isOpaque = isOpaque
        self.cacheKey = .init(
            type: type,
            material: useMaterialForCache && hasVariedMaterials ? material : nil,
            smoothing: smoothing,
            transform: .identity,
            flipped: transform.isFlipped,
            children: childKeys
        )

        // Compute the overestimated, non-transformed bounds
        switch type {
        case .difference, .stencil:
            self.bounds = children.first.map {
                $0.bounds.transformed(by: $0.transform)
            } ?? .empty
        case .intersection:
            self.bounds = children.dropFirst().reduce(into: children.first.map {
                $0.bounds.transformed(by: $0.transform)
            } ?? .empty) { bounds, child in
                bounds.formIntersection(child.bounds.transformed(by: child.transform))
            }
        case .union, .xor, .group:
            self.bounds = Bounds(children.map {
                $0.bounds.transformed(by: $0.transform)
            })
        case .lathe, .fill, .extrude, .loft, .hull:
            self.bounds = type.bounds.union(Bounds(children.map {
                $0.bounds.transformed(by: $0.transform)
            }))
        case .minkowski:
            var bounds = Bounds(min: .zero, max: .zero)
            for child in children {
                bounds.formMinkowskiSum(with: child.bounds.transformed(by: child.transform))
            }
            self.bounds = bounds
        case .cone, .cylinder, .sphere, .cube, .mesh, .path:
            self.bounds = type.bounds
        case .camera, .light:
            self.bounds = .empty
        }

        // Must be set after all other properties
        children.forEach { $0.parent = self }
    }
}

public extension Geometry {
    /// Geometry and its children produce no output
    var isEmpty: Bool {
        type.isEmpty && children.allSatisfy(\.isEmpty)
    }

    /// The camera (if geometry is a camera)
    var camera: Camera? {
        guard case let .camera(camera) = type else {
            return nil
        }
        return camera
    }

    /// The light (if geometry is a light)
    var light: Light? {
        guard case let .light(light) = type else {
            return nil
        }
        return light
    }

    /// The path (if geometry is a path)
    var path: Path? {
        guard case let .path(path) = type else {
            return nil
        }
        return path
    }

    /// The absolute geometry transform relative to the world/scene
    var worldTransform: Transform {
        (parent?.worldTransform ?? .identity) * transform
    }

    /// Returns `true` if the geometry's' children should be rendered in debug mode
    var childDebug: Bool {
        debug || children.contains(where: \.childDebug)
    }

    /// Return a copy of the geometry with the specified transform applied
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

    @available(*, deprecated, message: "Do not use")
    func hasUniformMaterial(_: Material? = nil) -> Bool {
        true
    }

    /// Return a copy of the geometry with the specified properties updated
    /// - Note: transform is replaced annd not combined like with `transformed(by:)`,
    func with(
        transform: Transform,
        material: Material?,
        smoothing: Angle?,
        sourceLocation: @escaping () -> SourceLocation?
    ) -> Geometry {
        _with(
            name: nil,
            transform: transform,
            material: material,
            smoothing: smoothing,
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
            smoothing: nil,
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
            smoothing: nil,
            sourceLocation: nil,
            removingLights: false,
            removingGroupTransform: true
        )
    }

    /// Builds the meshes for the receiver and all its children
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    /// - Returns: false if cancelled or true when completed
    func build(_ callback: @escaping LegacyCallback) -> Bool {
        buildLeaves(callback) && buildPreview(callback) && buildFinal(callback)
    }

    /// Returns the union mesh of the receiver and all its children
    /// - Note: Includes both material and transform
    func flattened(_ callback: @escaping LegacyCallback = { true }) -> Mesh {
        flattened(with: material, callback)
    }

    /// Returns the combined mesh of the receiver and all its children
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Result is does *not* include the material or transform for the receiver
    func merged(_ callback: @escaping LegacyCallback = { true }) -> Mesh {
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
    /// Gathers all the named descendents of the receiver (including itself, potentially) into a dictionary
    func gatherNamedObjects(_ dictionary: inout [String: Geometry]) {
        if let name {
            dictionary[name] = self
        }
        children.forEach { $0.gatherNamedObjects(&dictionary) }
    }
}

private extension Collection<Geometry> {
    /// Computes the union of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Results include both material (if specified) and transform
    func flattened(with material: Material?, _ callback: @escaping LegacyCallback) -> [Mesh] {
        compactMap { callback() ? $0.flattened(with: material, callback) : nil }
    }

    /// Returns the meshes of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Results include both material (if specified) and transform
    func meshes(with material: Material?, _ callback: @escaping LegacyCallback) -> [Mesh] {
        flatMap { callback() ? $0.meshes(with: material, callback) : [] }
    }

    /// Returns a merged mesh for all of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Does not include the material or transform of the top-level geometries in the collection
    func merged(_ callback: @escaping LegacyCallback) -> Mesh {
        var result = Mesh.empty
        for child in self where callback() {
            result = result.merge(child.merged(callback))
        }
        return result
    }
}

private extension Geometry {
    /// Computes the union of the meshes of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes both material (if specified) and transform
    func flattenedChildren(_ callback: @escaping LegacyCallback) -> [Mesh] {
        children.flattened(with: material, callback)
    }

    /// Returns a merged mesh for all of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Does not include the material or transform of the top-level geometries in the collection
    func mergedChildren(_ callback: @escaping LegacyCallback) -> Mesh {
        children.merged(callback)
    }

    /// Computes the union of the meshes of the first child of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes both material (if specified) and transform
    func flattenedFirstChild(_ callback: @escaping LegacyCallback) -> Mesh {
        children.first.map { $0.flattened(with: self.material, callback) } ?? .empty
    }

    /// Returns the meshes of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes both the material and transform
    func childMeshes(_ callback: @escaping () -> Bool) -> [Mesh] {
        children.meshes(with: material, callback)
    }

    /// Computes the union of the meshes of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes material (if specified) and the receiver's transform
    func flattened(with material: Material?, _ callback: @escaping LegacyCallback) -> Mesh {
        .union(meshes(with: material, callback), isCancelled: { !callback() })
    }

    /// Returns the meshes of the receiver and all its children
    /// The cache is neither checked nor updated. Only already-built meshes are returned.
    /// - Note: Includes both material (if specified) and transform
    func meshes(with material: Material?, _ callback: @escaping LegacyCallback) -> [Mesh] {
        var meshes = [Mesh]()
        if var mesh, mesh != .empty {
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

    /// Build all geometries that don't have dependencies
    /// - Returns: false if cancelled or true when completed
    func buildLeaves(_ callback: @escaping LegacyCallback) -> Bool {
        if type.isLeafGeometry, !buildMesh(callback) {
            return false
        }
        for child in children where !child.buildLeaves(callback) {
            return false
        }
        return true
    }

    /// With leaves built, do a rough preview
    /// - Returns: false if cancelled or true when completed
    func buildPreview(_ callback: @escaping LegacyCallback) -> Bool {
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
        case .group, .path, .mesh,
             .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(type.isLeafGeometry) // Leaves
        case .stencil, .difference:
            mesh = children.first?.merged(callback)
        case .union, .xor, .intersection, .hull, .minkowski, .camera, .light:
            mesh = nil
        }
        return callback()
    }

    /// Builds and caches the final mesh for the receiver and all its descendents
    /// - Returns: false if cancelled or true when completed
    func buildFinal(_ callback: @escaping LegacyCallback) -> Bool {
        for child in children where !child.buildFinal(callback) {
            return false
        }
        if !type.isLeafGeometry {
            return buildMesh(callback)
        }
        return callback()
    }

    /// Builds and caches the mesh for the receiver. Already-cached mesh will be re-used if available
    /// - Note: Child meshes should have already been built before calling (unchecked)
    /// - Returns: false if cancelled or true when completed
    func buildMesh(_ callback: @escaping LegacyCallback) -> Bool {
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
        case let .extrude(paths, .default) where paths.count == 1:
            mesh = .extrude(paths[0]).makeWatertight()
        case let .extrude(paths, options) where paths.count == 1 && options.along.count == 1:
            mesh = .extrude(
                paths[0].materialToVertexColors(material: material),
                along: options.along[0].materialToVertexColors(material: material).predividedBy(material),
                twist: options.twist,
                align: options.align,
                isCancelled: isCancelled
            )
            .vertexColorsToMaterial(material: material)
            .replacing(material, with: nil)
            .makeWatertight()
        case let .lathe(paths, segments: segments) where paths.count == 1:
            mesh = .lathe(paths[0], slices: segments, isCancelled: isCancelled).makeWatertight()
        case let .fill(paths) where paths.count == 1:
            mesh = .fill(paths[0].closed()).makeWatertight()
        case let .loft(paths):
            mesh = .loft(paths, isCancelled: isCancelled).makeWatertight()
        case let .hull(vertices):
            let base = Mesh.convexHull(of: vertices, material: material, isCancelled: isCancelled)
            let meshes = ([base] + childMeshes(callback)).map { $0.materialToVertexColors(material: material) }
            mesh = .convexHull(of: meshes, isCancelled: isCancelled)
                .vertexColorsToMaterial(material: material)
                .replacing(material, with: nil)
        case .minkowski:
            var children = ArraySlice(children.enumerated().sorted {
                switch ($0.1.type, $1.1.type) {
                case let (.path(a), .path(b)):
                    // Put closed paths before open paths
                    if a.isClosed != b.isClosed {
                        return a.isClosed
                    }
                    // TODO: put convex paths before concave paths
                    // Put smaller paths before larger paths
                    return a.bounds.size < b.bounds.size
                case (.path, _):
                    // Put meshes before paths
                    return false
                case (_, .path):
                    return true
                case (_, _):
                    // TODO: put convex meshes before concave meshes
                    // TODO: put smaller meshes before larger meshes
                    // Preserve original order
                    return $0.0 < $1.0
                }
            }.map { $1 })
            guard let first = children.popFirst() else {
                mesh = .empty
                break
            }
            var sum: Mesh
            if let shape = first.path?.transformed(by: first.transform) {
                guard let next = children.popFirst() else {
                    mesh = .empty
                    break
                }
                let shape = shape.materialToVertexColors(material: first.material)
                if let path = next.path?.transformed(by: next.transform) {
                    sum = .fill(shape).minkowskiSum(
                        with: path.materialToVertexColors(material: next.material),
                        isCancelled: isCancelled
                    )
                } else {
                    sum = next.flattened(callback).materialToVertexColors(material: next.material).minkowskiSum(
                        with: shape,
                        isCancelled: isCancelled
                    )
                }
            } else {
                sum = first.flattened(callback).materialToVertexColors(material: first.material)
            }
            while let next = children.popFirst() {
                if let path = next.path?.transformed(by: next.transform) {
                    sum = sum.minkowskiSum(
                        with: path.materialToVertexColors(material: next.material).predividedBy(first.material),
                        isCancelled: isCancelled
                    )
                } else {
                    sum = sum.minkowskiSum(
                        with: next.flattened(callback).materialToVertexColors(material: next.material),
                        isCancelled: isCancelled
                    )
                }
            }
            mesh = sum.vertexColorsToMaterial(material: material)
                .replacing(material, with: nil)
                .makeWatertight()
        case .union, .lathe, .extrude, .fill:
            mesh = .union(childMeshes(callback), isCancelled: isCancelled).makeWatertight()
        case .xor:
            mesh = .symmetricDifference(flattenedChildren(callback), isCancelled: isCancelled).makeWatertight()
        case .difference:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = .difference(meshes, isCancelled: isCancelled).makeWatertight()
        case .intersection:
            let meshes = flattenedChildren(callback)
            mesh = .intersection(meshes, isCancelled: isCancelled).makeWatertight()
        case .stencil:
            let first = flattenedFirstChild(callback)
            let meshes = [first] + children.dropFirst().meshes(with: material, callback)
            mesh = .stencil(meshes, isCancelled: isCancelled).makeWatertight()
        case let .mesh(mesh):
            self.mesh = mesh
        }
        if callback() {
            if let smoothing {
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
        smoothing: Angle?,
        sourceLocation: (() -> SourceLocation?)?,
        removingLights: Bool,
        removingGroupTransform: Bool
    ) -> Geometry {
        var type = type
        if removingLights, case .light = type {
            preconditionFailure()
        }
        var m = self.material
        if let material, case let .mesh(mesh) = type {
            if m.opacity?.opacity ?? 1 == 1 {
                m.opacity = material.opacity
            } else if material.opacity?.color != nil {
                let opacity = material.opacity?.opacity ?? 1
                switch m.opacity ?? .color(.white) {
                case let .color(color):
                    let opacity = color.a * opacity
                    m.opacity = .color(.init(opacity, opacity))
                case let .texture(texture):
                    // Since user cannot specify texture opacity, this should always be 1
                    let opacity = texture.intensity * opacity
                    m.opacity = .texture(texture.withIntensity(opacity))
                }
            }
            m.albedo = material.albedo ?? m.albedo
            m.glow = material.glow ?? m.glow
            m.metallicity = material.metallicity ?? m.metallicity
            m.roughness = material.roughness ?? m.roughness
            // Note: this only replaces the mesh base material, not merged mesh materials
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
            smoothing: smoothing ?? self.smoothing,
            children: children.compactMap {
                if case .light = $0.type, removingLights {
                    return nil
                }
                return $0._with(
                    name: nil,
                    transform: childTransform,
                    material: material,
                    smoothing: nil,
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

private extension Color {
    func predividedBy(_ other: Color) -> Color {
        .init(
            other.r > 0 ? r / other.r : r,
            other.g > 0 ? g / other.g : g,
            other.b > 0 ? b / other.b : b,
            other.a > 0 ? a / other.a : a
        )
    }
}

private extension Material {
    func predividedBy(_ other: Material) -> Material {
        var result = self
        result.albedo = .color({
            let lhs = color ?? .white
            let rhs = other.color ?? .white
            return lhs.predividedBy(rhs)
        }())
        return result
    }
}

private extension [Path] {
    /// Returns the uniform color of all vertices, or nil if they have different colors
    var uniformVertexColor: Color? {
        let uniformColor = first?.uniformVertexColor ?? .white
        return allSatisfy { [uniformColor, .white].contains($0.uniformVertexColor) } ? uniformColor : nil
    }

    /// Convert uniform point colors to a material instead
    func vertexColorsToMaterial(material: Material) -> ([Path], Material) {
        guard material.texture == nil else {
            return (self, material)
        }
        if let uniformVertexColor {
            if uniformVertexColor == .white {
                return (self, material)
            }
            var material = material
            material.albedo = .color(uniformVertexColor)
            return (map { $0.withColor(nil) }, material)
        }
        var material = material
        material.albedo = .color(.white)
        return (self, material)
    }
}

extension Path {
    /// Returns the uniform color of all vertices, or nil if they have different colors
    var uniformVertexColor: Color? {
        let uniformColor = points.first?.color ?? .white
        return points.allSatisfy { $0.color ?? .white == uniformColor } ? uniformColor : nil
    }

    /// Convert uniform point colors to a material instead
    func vertexColorsToMaterial(material: Material) -> (Path, Material) {
        guard material.texture == nil else {
            return (self, material)
        }
        if let uniformVertexColor {
            if uniformVertexColor == .white {
                return (self, material)
            }
            var material = material
            material.albedo = .color(uniformVertexColor)
            return (withColor(nil), material)
        }
        var material = material
        material.albedo = .color(.white)
        return (self, material)
    }

    /// Convert material color to vertex colors, preserving the existing vertex colors if set
    func materialToVertexColors(material: ShapeScript.Material?) -> Path {
        guard let color = material?.color, color != .white, !hasColors else {
            return self
        }
        return withColor(color)
    }

    func predividedBy(_ other: Material) -> Path {
        mapColors { $0?.predividedBy(other.color ?? .white) }
    }
}

extension Polygon {
    /// Returns the uniform color of all vertices, or nil if they have different colors
    var uniformVertexColor: Color? {
        let uniformColor = vertices.first?.color ?? .white
        return vertices.allSatisfy { $0.color == uniformColor } ? uniformColor : nil
    }

    /// Convert uniform vertex colors to a material instead
    func vertexColorsToMaterial(material: ShapeScript.Material) -> Polygon {
        var material = self.material as? ShapeScript.Material ?? material
        guard material.texture == nil else {
            return withMaterial(material)
        }
        if let uniformVertexColor {
            if uniformVertexColor == .white {
                return withMaterial(material)
            }
            var material = material
            material.albedo = .color(uniformVertexColor)
            return withoutVertexColors().withMaterial(material)
        }
        material.albedo = .color(.white)
        return withMaterial(material)
    }

    /// Convert material colors to vertex colors, preserving the existing vertex colors if set
    func materialToVertexColors(material: ShapeScript.Material?) -> Polygon {
        guard var material = self.material as? ShapeScript.Material ?? material,
              let color = material.color, color != .white,
              !hasVertexColors
        else {
            return self
        }
        material.albedo = .color(.white)
        return mapVertexColors { _ in color }.withMaterial(material)
    }
}

extension Mesh {
    /// Returns the uniform color of all vertices, or nil if they have different colors
    var uniformVertexColor: Color? {
        let uniformColor = polygons.first?.uniformVertexColor ?? .white
        return polygons.allSatisfy { $0.uniformVertexColor == uniformColor } ? uniformColor : nil
    }

    /// Convert uniform vertex colors to a material instead
    func vertexColorsToMaterial(material: ShapeScript.Material) -> Mesh {
        guard material.texture == nil else {
            return withMaterial(material)
        }
        if let uniformVertexColor {
            if uniformVertexColor == .white {
                return withMaterial(material)
            }
            var material = material
            material.albedo = .color(uniformVertexColor)
            return withoutVertexColors().withMaterial(material)
        }
        var material = material
        material.albedo = .color(.white)
        return withMaterial(material)
    }

    /// Convert material colors to vertex colors, preserving the existing vertex colors if set
    func materialToVertexColors(material: ShapeScript.Material?) -> Mesh {
        .init(polygons.map { $0.materialToVertexColors(material: material) })
    }
}

// MARK: Stats

public extension Geometry {
    /// Returns if the geometry is a mesh type
    /// - Note: this will return `true` even if mesh is empty has not been built yet
    var hasMesh: Bool {
        switch type {
        case .camera, .light, .path:
            return false
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .group, .mesh:
            return true // TODO: should group return false if it has no child meshes?
        }
    }

    /// Returns the total number of distinct objects (paths or meshes) in the shape
    /// - Note: for groups this returns the child count, but children are ignored for other types
    var objectCount: Int {
        switch type {
        case .group:
            return children.reduce(0) { $0 + $1.objectCount }
        case .camera, .light:
            return 0
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .path, .mesh:
            return 1
        }
    }

    /// Returns the child count for the shape, not including grandchildren
    /// - Note: only child meshes or groups are counted
    var childCount: Int {
        switch type {
        case .cone, .cylinder, .sphere, .cube,
             .extrude, .lathe, .fill, .loft,
             .mesh, .path, .camera, .light:
            return 0 // TODO: should paths/points be treated as children?
        case .union, .xor, .difference, .intersection, .stencil, .group, .hull, .minkowski:
            return children.count
        }
    }

    /// Builds the mesh (if needed) and returns the polygon count
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    func polygons(_ isCancelled: @escaping CancellationHandler) -> [Polygon] {
        switch type {
        case .group:
            return children.reduce(into: []) { $0 += $1.polygons(isCancelled) }
        default:
            _ = build { !isCancelled() }
            return mesh?.polygons ?? []
        }
    }

    /// Builds the mesh (if needed) and returns the triangle count
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    func triangles(_ isCancelled: @escaping CancellationHandler) -> [Polygon] {
        switch type {
        case .group:
            return children.reduce(into: []) { $0 += $1.triangles(isCancelled) }
        default:
            _ = build { !isCancelled() }
            return mesh?.triangulate().polygons ?? []
        }
    }

    /// Returns if the geometry is watertight
    /// Builds and caches the mesh (if required). Already-cached meshes will be re-used if available
    func isWatertight(_ isCancelled: @escaping CancellationHandler) -> Bool {
        switch type {
        case .cone, .cylinder, .sphere, .cube:
            return true
        case .group:
            return children.reduce(true) { $0 && $1.isWatertight(isCancelled) }
        default:
            _ = build { !isCancelled() }
            return mesh?.isWatertight ?? true
        }
    }

    /// Returns the exact bounds with specified transform
    /// Builds and caches the mesh if required. Already-cached meshes will be re-used if available
    func exactBounds(
        with transform: Transform,
        _ callback: @escaping LegacyCallback = { true }
    ) -> Bounds {
        switch type {
        case .camera, .light:
            return .empty
        case .group, .union, .lathe([], _), .extrude([], _), .fill([]):
            return Bounds(children.map {
                $0.exactBounds(with: $0.transform * transform, callback)
            })
        case .cone, .cylinder, .sphere, .cube, .path, .extrude, .lathe, .mesh:
            assert(children.isEmpty)
            if transform.rotation == .identity {
                return type.bounds.transformed(by: transform)
            }
            return Bounds(type.representativePoints.transformed(by: transform))
        case let .fill(paths), let .loft(paths):
            assert(children.isEmpty)
            if transform.rotation == .identity {
                return type.bounds.transformed(by: transform)
            }
            return Bounds(paths.transformed(by: transform))
        case .hull:
            let bounds: Bounds
            if transform.rotation == .identity {
                bounds = type.bounds.transformed(by: transform)
            } else {
                bounds = Bounds(type.representativePoints.transformed(by: transform))
            }
            return children.reduce(bounds) {
                $0.union($1.exactBounds(with: $1.transform * transform, callback))
            }
        case .minkowski:
            return children.reduce(.empty) {
                $0.minkowskiSum(with: $1.exactBounds(with: $1.transform * transform, callback))
            }
        case .xor, .difference, .intersection:
            _ = build(callback)
            if transform.rotation == .identity {
                return mesh?.bounds.transformed(by: transform) ?? .empty
            }
            return mesh?.transformed(by: transform).bounds ?? .empty
        case .stencil:
            return children.first.map {
                $0.exactBounds(with: $0.transform * transform, callback)
            } ?? .empty
        }
    }

    /// Returns the exact mesh volume, in world units
    /// Builds and caches the mesh if required. Already-cached meshes will be re-used if available
    func volume(_ isCancelled: @escaping CancellationHandler) -> Double {
        volume(with: worldTransform, isCancelled)
    }

    /// Returns the exact mesh volume with the specified transform
    /// Builds and caches the mesh if required. Already-cached meshes will be re-used if available
    private func volume(with transform: Transform, _ isCancelled: @escaping CancellationHandler) -> Double {
        let scaleFactor = transform.scale.x * transform.scale.y * transform.scale.z
        switch type {
        case .cube:
            return scaleFactor
        case .group:
            return children.reduce(0) { $0 + $1.volume(with: $1.transform, isCancelled) } * scaleFactor
        default:
            _ = build { !isCancelled() }
            return (mesh?.signedVolume ?? 0) * scaleFactor
        }
    }

    // MARK: Deprecated

    @available(*, deprecated, message: "Use polygons.count instead")
    var polygonCount: Int {
        polygons { false }.count
    }

    @available(*, deprecated, message: "Use triangles().count instead")
    var triangleCount: Int {
        triangles { false }.count
    }

    @available(*, deprecated, message: "Use isWatertight() instead")
    var isWatertight: Bool {
        isWatertight { false }
    }
}
