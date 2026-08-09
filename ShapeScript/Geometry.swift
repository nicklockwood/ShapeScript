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
public typealias CancellationHandler = @Sendable () -> Bool

public final class Geometry: Hashable, @unchecked Sendable {
    public let type: GeometryType
    public let name: String?
    public let transform: Transform
    public let material: Material
    public let smoothing: Angle?
    public let children: [Geometry]
    public let isOpaque: Bool // Computed
    private let _overestimatedBounds: Bounds
    private let _sourceLocation: (@Sendable () -> SourceLocation?)?
    public private(set) lazy var sourceLocation: SourceLocation? = _sourceLocation?()
    public private(set) weak var parent: Geometry?

    /// The overestimated Geometry bounds *with* local transform applied
    public var overestimatedBounds: Bounds {
        _overestimatedBounds.transformed(by: transform)
    }

    /// The overestimated Geometry bounds *without* the local transform applied
    @available(*, deprecated, message: "Use overestimatedBounds instead")
    public var bounds: Bounds {
        _overestimatedBounds
    }

    // Note: equality and hashing describe the modeled geometry, not render/editor
    // state. Debug/focus flags affect how the geometry is presented, while opacity,
    // source locations, and parent links are derived or contextual metadata.

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(name)
        hasher.combine(transform)
        hasher.combine(material)
        hasher.combine(smoothing)
        hasher.combine(children)
        // Excludes isOpaque, sourceLocation, parent, debug and focus
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
        // Excludes isOpaque, sourceLocation, parent, debug and focus
        else {
            return false
        }
        return true
    }

    /// Whether children should be rendered separately or are included in mesh
    public var renderChildren: Bool {
        switch type {
        case .group:
            true
        case .lathe, .intersection, .difference, .stencil, .minkowski:
            false
        case .loft, .union, .xor, .extrude, .fill, .hull:
            mesh == nil
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .path, .mesh, .camera, .light:
            false // These don't have children
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

    /// Hide all other geometry
    public internal(set) var isFocused: Bool {
        didSet {
            if isFocused, type == .group {
                children.forEach { $0.isFocused = true }
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
        sourceLocation: (@Sendable () -> SourceLocation?)?,
        debug: Bool = false,
        isFocused: Bool = false
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
                type = .extrude(paths, .default)
            case (1, 1):
                var pair = (paths + options.along)
                (pair, material) = pair.vertexColorsToMaterial(material: material)
                options.along = [pair[1]]
                type = .extrude([pair[0]], options)
            case (_, 0):
                type = .extrude([], .default)
                children = paths.map { path in
                    let (temp, material) = path.vertexColorsToMaterial(material: material)
                    let (path, offset) = temp.withNormalizedPosition()
                    return Geometry(
                        type: .extrude([path], options),
                        name: nil,
                        transform: .translation(offset),
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
                        let (along, offset) = along.withNormalizedPosition()
                        let (pair, material) = [path, along].vertexColorsToMaterial(material: material)
                        var options = options
                        options.along = [pair[1]]
                        return Geometry(
                            type: .extrude([pair[0]], options),
                            name: nil,
                            transform: .translation(offset),
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
                    // TODO: normalize path y-position for better caching
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
                    let (temp, material) = path.vertexColorsToMaterial(material: material)
                    let (path, offset) = temp.withNormalizedPosition()
                    return Geometry(
                        type: .fill([path]),
                        name: nil,
                        transform: .translation(offset),
                        material: material,
                        smoothing: smoothing,
                        children: [],
                        sourceLocation: sourceLocation
                    )
                }
                material = children.first?.material ?? .default
            }
        case var .loft(paths):
            // TODO: normalize all paths by their collective offset for better caching
            (paths, material) = paths.vertexColorsToMaterial(material: material)
            type = .loft(paths)
        case var .path(path):
            (path, material) = path.vertexColorsToMaterial(material: material)
            type = .path(path)
        case let .mesh(mesh) where !mesh.isEmpty:
            material = mesh.materials.first as? Material ?? .default
        case .hull, .minkowski:
            useMaterialForCache = true
        case .union, .xor, .difference, .intersection, .stencil, .mesh:
            material = children.first?.material ?? .default
        case .group:
            if debug {
                children.forEach { $0.debug = true }
            }
            if isFocused {
                children.forEach { $0.isFocused = true }
            }
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .camera, .light:
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
        self.isFocused = isFocused

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

        let childKeys = type.isLeaf ? [] : children.map(flattenedCacheKey)

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
            self._overestimatedBounds = children.first.map(\.overestimatedBounds) ?? .empty
        case .intersection:
            self._overestimatedBounds = children.dropFirst().reduce(children.first?.overestimatedBounds ?? .empty) {
                $0.intersection($1.overestimatedBounds)
            }
        case .union, .xor, .group:
            self._overestimatedBounds = Bounds(children.map(\.overestimatedBounds))
        case .lathe, .fill, .extrude, .loft, .mesh, .hull:
            self._overestimatedBounds = type.bounds.union(Bounds(children.map(\.overestimatedBounds)))
        case .minkowski:
            self._overestimatedBounds = children.reduce(.empty) {
                $0.minkowskiSum(with: $1.overestimatedBounds)
            }
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square, .path:
            self._overestimatedBounds = type.bounds
        case .camera, .light:
            self._overestimatedBounds = .empty
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

    /// The path represented by this geometry, if any, in local coordinates.
    /// Semantic path primitives include the geometry's material color.
    var path: Path? {
        path(pretransformed: false)
    }

    /// Returns the path represented by this geometry, optionally with the geometry transform baked in.
    /// Semantic path primitives include the geometry's material color either way.
    func path(pretransformed: Bool) -> Path? {
        switch type {
        case let .circle(segments):
            let path = Path.circle(segments: segments, color: material.color)
            return pretransformed ? path.transformed(by: transform) : path
        case .square:
            let path = Path.square(color: material.color)
            return pretransformed ? path.transformed(by: transform) : path
        case let .path(path):
            return pretransformed ? path.transformed(by: transform) : path
        default:
            return nil
        }
    }

    /// Returns `true` if the geometry's' children should be rendered in debug mode
    var childDebug: Bool {
        debug || children.contains(where: \.childDebug)
    }

    /// Returns `true` if the geometry or any of its children are focused
    var childIsFocused: Bool {
        isFocused || children.contains(where: \.childIsFocused)
    }

    /// Returns `true` if this geometry is rendered as part of the scene
    func isRenderedInScene(focus: Bool) -> Bool {
        guard !focus || isFocused else {
            return false
        }
        let target = self
        var geometry = self
        while let parent = geometry.parent {
            guard parent.renderChildren ||
                (geometry === target && (geometry.debug || geometry.isFocused)) ||
                (geometry !== target && (geometry.childDebug || geometry.childIsFocused))
            else {
                return false
            }
            geometry = parent
        }
        return true
    }

    /// The absolute geometry transform relative to the world/scene
    var worldTransform: Transform {
        (parent?.worldTransform ?? .identity) * transform
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
            debug: debug,
            isFocused: isFocused
        )
    }

    /// Returns an inset copy by rewriting path-backed primitives where the operation is equivalent.
    func insetByRewritingPrimitives(
        by distance: Double,
        sourceLocation: @escaping @Sendable () -> SourceLocation?,
        isCancelled: @escaping CancellationHandler = { false }
    ) -> Geometry {
        func copy(
            type: GeometryType = type,
            transform: Transform = transform,
            children: [Geometry] = []
        ) -> Geometry {
            Geometry(
                type: type,
                name: name,
                transform: transform,
                material: material,
                smoothing: smoothing,
                children: children,
                sourceLocation: sourceLocation,
                debug: debug
            )
        }

        func insetMesh() -> Geometry {
            let sourceMesh = mesh(isCancelled) ?? .empty
            var mesh = sourceMesh.inset(by: distance, isCancelled: isCancelled)
            if material != .default {
                if sourceMesh.materials.contains(where: { $0 != nil }) {
                    mesh = mesh.replacing(nil, with: material)
                } else if !sourceMesh.hasVertexColors || sourceMesh.uniformVertexColor == .white {
                    mesh = mesh.withoutVertexColors().withMaterial(material)
                }
            }
            return copy(type: .mesh(mesh))
        }

        func insetChildren(by distance: Double = distance) -> [Geometry] {
            children.map {
                $0.insetByRewritingPrimitives(
                    by: distance,
                    sourceLocation: sourceLocation,
                    isCancelled: isCancelled
                )
            }
        }

        func circularApothem(segments: Int, radius: Double) -> Double {
            radius * cos(.pi / Double(max(3, segments)))
        }

        func insetScale(for apothems: Vector) -> Vector {
            [
                max(0, 1 - distance / apothems.x / abs(transform.scale.x)),
                max(0, 1 - distance / apothems.y / abs(transform.scale.y)),
                max(0, 1 - distance / apothems.z / abs(transform.scale.z)),
            ]
        }

        switch type {
        case .cube:
            return copy(transform: transform * .scale(insetScale(for: .init(size: 0.5))))
        case let .sphere(segments):
            let radius = 0.5
            let stacks = max(2, segments / 2)
            let verticalApothem = radius * cos(.pi / Double(stacks * 2))
            let radialApothem = circularApothem(segments: segments, radius: verticalApothem)
            return copy(transform: transform * .scale(insetScale(
                for: [radialApothem, verticalApothem, radialApothem]
            )))
        case let .icosphere(subdivisions):
            let mesh = Mesh.icosphere(subdivisions: subdivisions, wrapMode: .none)
            let apothem = mesh.polygons.reduce(0.5) { Swift.min($0, abs($1.plane.w)) }
            return copy(transform: transform * .scale(insetScale(for: .init(size: apothem))))
        case let .cylinder(segments):
            let radialApothem = circularApothem(segments: segments, radius: 0.5)
            return copy(transform: transform * .scale(insetScale(
                for: [radialApothem, 0.5, radialApothem]
            )))
        case let .cone(segments):
            let radius = 0.5 * (abs(transform.scale.x) + abs(transform.scale.z)) / 2
            let height = abs(transform.scale.y)
            let apothem = circularApothem(segments: segments, radius: radius)
            let sideLength = sqrt(apothem * apothem + height * height)
            let scale = max(0, 1 - distance * (sideLength / apothem + 1) / height)
            let offset = distance * (1 - sideLength / apothem) / 2
            return copy(transform: transform * .scale(scale) * .translation(.unitY * offset))
        case .group, .union, .xor:
            return copy(children: insetChildren())
        case .difference:
            let inset = children.enumerated().map { index, child in
                child.insetByRewritingPrimitives(
                    by: index == 0 ? distance : -distance,
                    sourceLocation: sourceLocation,
                    isCancelled: isCancelled
                )
            }
            return copy(children: inset)
        case let .loft(paths):
            return copy(type: .loft(paths.map { $0.inset(by: distance) }))
        case .circle, .square, .path:
            return copy(type: path.map { .path($0.inset(by: distance)) } ?? type)
        case let .fill(paths) where paths.count == 1:
            return copy(type: .fill([paths[0].inset(by: distance)]))
        case let .extrude(paths, options) where paths.count == 1 && options.along.isEmpty:
            if distance > 0 {
                if mesh(isCancelled)?.inset(by: distance, isCancelled: isCancelled).isEmpty == true {
                    return copy(type: .mesh(.empty))
                }
            }
            let depth = max(0, 1 - distance * 2)
            let path = paths[0].inset(by: distance)
            guard !path.isEmpty, depth > 0 else {
                return copy(type: .mesh(.empty))
            }
            let offset = path.faceNormal * depth
            return copy(type: .loft([
                path.translated(by: -offset / 2),
                path.translated(by: offset / 2),
            ]))
        case let .extrude(paths, options) where paths.count == 1 && options.along.count == 1:
            let path = paths[0].inset(by: distance)
            guard !path.isEmpty, let along = options.along[0].trimmingEnds(by: distance) else {
                return copy(type: .mesh(.empty))
            }
            var options = options
            options.along = [along]
            if material != .default {
                let mesh = Mesh.extrude(
                    path,
                    along: along,
                    twist: options.twist,
                    align: options.align,
                    miterLimit: options.miterLimit,
                    material: material
                )
                return copy(type: .mesh(mesh))
            }
            return copy(type: .extrude([path], options))
        case .fill, .extrude, .lathe:
            guard !children.isEmpty else {
                return insetMesh()
            }
            return copy(children: insetChildren())
        case .hull,
             .minkowski,
             .intersection,
             .stencil,
             .mesh:
            return insetMesh()
        case .camera, .light:
            return copy()
        }
    }

    @available(*, deprecated, message: "Do not use")
    func hasUniformMaterial(_: Material? = nil) -> Bool {
        true
    }

    /// Return a copy of the geometry with the specified properties updated
    /// - Note: transform is replaced and not combined like with `transformed(by:)`,
    func with(
        transform: Transform,
        material: Material?,
        smoothing: Angle?,
        sourceLocation: @escaping @Sendable () -> SourceLocation?
    ) -> Geometry {
        _with(
            name: nil,
            transform: transform,
            material: material,
            smoothing: smoothing,
            sourceLocation: sourceLocation,
            removingLights: false,
            removingGroupTransform: false,
            withoutDebug: false,
            withoutUnfocusedGeometry: false
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
            removingGroupTransform: false,
            withoutDebug: false,
            withoutUnfocusedGeometry: false
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
            removingGroupTransform: true,
            withoutDebug: false,
            withoutUnfocusedGeometry: false
        )
    }

    /// Returns a copy of the geometry with debug geometry and materials removed
    func withoutDebug() -> Geometry {
        guard childDebug else {
            return self
        }
        return _with(
            name: nil,
            transform: nil,
            material: nil,
            smoothing: nil,
            sourceLocation: nil,
            removingLights: false,
            removingGroupTransform: false,
            withoutDebug: true,
            withoutUnfocusedGeometry: false
        )
    }

    /// Returns a copy of the geometry with unfocused siblings removed
    func withoutUnfocusedGeometry() -> Geometry {
        guard childIsFocused else {
            return self
        }
        return _with(
            name: nil,
            transform: nil,
            material: nil,
            smoothing: nil,
            sourceLocation: nil,
            removingLights: false,
            removingGroupTransform: false,
            withoutDebug: false,
            withoutUnfocusedGeometry: true
        )
    }

    /// Builds the meshes for the receiver and all its descendents
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    /// - Returns: false if cancelled or true when completed
    func build(_ isCancelled: @escaping CancellationHandler) -> Bool {
        buildLeaves(isCancelled) && buildPreview(isCancelled) && buildFinal(isCancelled)
    }

    /// Returns the union mesh of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned.
    /// - Note: Includes both material and transform
    func flattened(_ isCancelled: @escaping CancellationHandler = { false }) -> Mesh {
        flattened(with: material, isCancelled)
    }

    /// Returns the meshes of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes both material and transform
    func meshes(_ isCancelled: @escaping CancellationHandler = { false }) -> [Mesh] {
        meshes(with: material, isCancelled)
    }

    /// Returns the combined mesh of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes both material and transform
    func merged(_ isCancelled: @escaping CancellationHandler = { false }) -> Mesh {
        var result = mesh ?? .empty
        if type.isLeaf {
            result = result.merge(mergedChildren(isCancelled))
        }
        return result
            .replacing(nil, with: material)
            .transformed(by: transform)
    }
}

extension Geometry {
    /// Returns `true` when this geometry's mesh can be built without first building
    /// its children. Child meshes may still need to be built separately for rendering
    var isLeaf: Bool {
        if case .mesh = type {
            return children.isEmpty
        }
        return type.isLeaf
    }

    /// Gathers all the named descendents of the receiver (including itself, potentially) into a dictionary
    func gatherNamedObjects(_ dictionary: inout [String: Geometry]) {
        if let name {
            dictionary[name] = self
        }
        children.forEach { $0.gatherNamedObjects(&dictionary) }
    }

    /// Builds the receiver's mesh if needed and returns the built local mesh.
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available.
    /// - Note: Does not include the receiver's transform. Use `merged()` or `flattened()`
    ///         for transform/material-applied output including descendants.
    func mesh(_ isCancelled: @escaping CancellationHandler = { false }) -> Mesh? {
        if mesh == nil, !build(isCancelled) {
            return nil
        }
        return mesh
    }
}

private extension Collection<Geometry> {
    /// Computes the union of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Results include both material (if specified) and transform
    func flattened(with material: Material?, _ isCancelled: @escaping Mesh.CancellationHandler) -> [Mesh] {
        compactMap { isCancelled() ? nil : $0.flattened(with: material, isCancelled) }
    }

    /// Returns the meshes of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Results include both material (if specified) and transform
    func meshes(with material: Material?, _ isCancelled: @escaping Mesh.CancellationHandler) -> [Mesh] {
        flatMap { isCancelled() ? [] : $0.meshes(with: material, isCancelled) }
    }

    /// Returns a merged mesh for all of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Results include both material and transform
    func merged(_ isCancelled: @escaping Mesh.CancellationHandler) -> Mesh {
        var result = Mesh.empty
        for child in self where !isCancelled() {
            result = result.merge(child.merged(isCancelled))
        }
        return result
    }
}

private extension Path {
    func trimmingEnds(by distance: Double) -> Path? {
        guard subpaths.count == 1, !isClosed else {
            return self
        }
        guard points.count > 1 else {
            return nil
        }
        if distance < 0 {
            return extendingEnds(by: -distance)
        }
        guard length > distance * 2 else {
            return nil
        }
        let start = point(atDistanceFromStart: distance)
        let end = point(atDistanceFromEnd: distance)
        guard let start, let end else {
            return nil
        }
        let startIndex = points.lastIndex { point in
            distanceFromStart(to: point) <= distance
        } ?? points.startIndex
        let endIndex = points.firstIndex { point in
            distanceFromEnd(to: point) <= distance
        } ?? points.index(before: points.endIndex)
        let middle = startIndex < endIndex ? Array(points[points.index(after: startIndex) ..< endIndex]) : []
        return Path([start] + middle + [end])
    }

    func extendingEnds(by distance: Double) -> Path {
        var points = points
        let firstDirection = (points[1].position - points[0].position).normalized()
        let lastDirection = (points[points.count - 1].position - points[points.count - 2].position).normalized()
        points[0].position -= firstDirection * distance
        points[points.count - 1].position += lastDirection * distance
        return Path(points)
    }

    func point(atDistanceFromStart distance: Double) -> PathPoint? {
        point(atDistance: distance, in: points)
    }

    func point(atDistanceFromEnd distance: Double) -> PathPoint? {
        point(atDistance: distance, in: points.reversed())
    }

    func point(atDistance distance: Double, in points: some Collection<PathPoint>) -> PathPoint? {
        var previous = points.first
        var remaining = distance
        for point in points.dropFirst() {
            guard let previousPoint = previous else {
                return nil
            }
            let length = (point.position - previousPoint.position).length
            if remaining <= length {
                return previousPoint.interpolated(with: point, by: remaining / length)
            }
            remaining -= length
            previous = point
        }
        return nil
    }

    func distanceFromStart(to target: PathPoint) -> Double {
        distance(to: target, in: points)
    }

    func distanceFromEnd(to target: PathPoint) -> Double {
        distance(to: target, in: points.reversed())
    }

    func distance(to target: PathPoint, in points: some Collection<PathPoint>) -> Double {
        var previous = points.first
        var distance = 0.0
        for point in points.dropFirst() {
            guard let previousPoint = previous else {
                return distance
            }
            if point.position == target.position {
                return distance + (point.position - previousPoint.position).length
            }
            distance += (point.position - previousPoint.position).length
            previous = point
        }
        return distance
    }
}

private extension Geometry {
    /// Computes the union of the meshes of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes the receiver's material but not its transform
    func flattenedChildren(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        children.flattened(with: material, isCancelled)
    }

    /// Returns a merged mesh for all of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Does not include the material or transform of the receiver
    func mergedChildren(_ isCancelled: @escaping CancellationHandler) -> Mesh {
        children.merged(isCancelled)
    }

    /// Computes the union of the meshes of the first child of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes the receiver's material but not its transform
    func flattenedFirstChild(_ isCancelled: @escaping CancellationHandler) -> Mesh {
        children.first.map { $0.flattened(with: self.material, isCancelled) } ?? .empty
    }

    /// Returns the meshes of the receivers children and their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes the receiver's material but not its transform
    func childMeshes(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        children.meshes(with: material, isCancelled)
    }

    /// Returns hull-compatible meshes for semantic path children such as circles and squares.
    /// Path-child vertices are intentionally generated here instead of being stored in
    /// `GeometryType.hull`, so exports can preserve the child semantics without also
    /// emitting duplicate fallback vertex geometry.
    /// - Note: Includes each child's material and transform, but not the receiver's transform.
    func childPathMeshes(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        children.compactMap { child in
            guard let path = child.path(pretransformed: true) else {
                return nil
            }
            let vertices = path
                .withColor(child.material.color)
                .subpaths
                .flatMap(\.edgeVertices)
            return .convexHull(
                of: vertices,
                material: child.material,
                isCancelled: isCancelled
            )
        }
    }

    /// Computes the union of the meshes of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes material (if specified) and the receiver's transform
    func flattened(with material: Material?, _ isCancelled: @escaping CancellationHandler) -> Mesh {
        .union(meshes(with: material, isCancelled), isCancelled: isCancelled)
    }

    /// Returns the meshes of the receiver and all its descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes both material (if specified) and transform
    func meshes(with material: Material?, _ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        var meshes = [Mesh]()
        if let mesh, mesh != .empty {
            meshes.append(mesh)
        }
        if type.isLeaf {
            meshes += childMeshes(isCancelled)
        }
        return meshes.map {
            let mesh = $0.transformed(by: transform)
            if material != self.material {
                return mesh.replacing(nil, with: self.material)
            }
            return mesh
        }
    }

    /// Build all geometries that don't have dependencies
    /// - Returns: false if cancelled or true when completed
    func buildLeaves(_ isCancelled: @escaping CancellationHandler) -> Bool {
        if isLeaf, !buildMesh(isCancelled) {
            return false
        }
        for child in children where !child.buildLeaves(isCancelled) {
            return false
        }
        return true
    }

    /// With leaves built, do a rough preview
    /// - Returns: false if cancelled or true when completed
    func buildPreview(_ isCancelled: @escaping CancellationHandler) -> Bool {
        for child in children where !child.buildPreview(isCancelled) {
            return false
        }
        if let mesh = cache?[mesh: self] {
            self.mesh = mesh
            return !isCancelled()
        }
        switch type {
        case .extrude([], _), .lathe([], _), .fill([]):
            mesh = nil
        case .mesh where children.isEmpty:
            break
        case .mesh:
            mesh = children.merged(isCancelled) // TODO: not really sure what to do here
        case .group, .circle, .square, .path,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(isLeaf) // Leaves
        case .stencil, .difference:
            mesh = children.first?.merged(isCancelled)
        case .union, .xor, .intersection, .hull, .minkowski, .camera, .light:
            mesh = nil
        }
        return !isCancelled()
    }

    /// Builds and caches the final mesh for the receiver and all its descendents
    /// - Returns: false if cancelled or true when completed
    func buildFinal(_ isCancelled: @escaping CancellationHandler) -> Bool {
        for child in children where !child.buildFinal(isCancelled) {
            return false
        }
        if !isLeaf {
            return buildMesh(isCancelled)
        }
        return !isCancelled()
    }

    /// Builds and caches the mesh for the receiver. Already-cached mesh will be re-used if available
    /// - Note: Child meshes should have already been built before calling (unchecked)
    /// - Returns: false if cancelled or true when completed
    func buildMesh(_ isCancelled: @escaping CancellationHandler) -> Bool {
        if let mesh = cache?[mesh: self] {
            self.mesh = mesh
            return !isCancelled()
        }
        guard !isCancelled() else { return false }
        switch type {
        case .group, .circle, .square, .path, .camera, .light:
            mesh = .empty
        case let .cone(segments):
            mesh = .cone(slices: segments, isCancelled: isCancelled)
        case let .cylinder(segments):
            mesh = .cylinder(slices: segments, isCancelled: isCancelled)
        case let .icosphere(subdivisions):
            mesh = .icosphere(subdivisions: subdivisions, isCancelled: isCancelled)
        case let .sphere(segments):
            mesh = .sphere(slices: segments, isCancelled: isCancelled)
        case .cube:
            mesh = .cube()
        case let .extrude(paths, options) where paths.count == 1 && options.along.isEmpty:
            mesh = .extrude(paths[0], isCancelled: isCancelled)
        case let .extrude(paths, options) where paths.count == 1 && options.along.count == 1:
            mesh = .extrude(
                paths[0].materialToVertexColors(material: material),
                along: options.along[0].materialToVertexColors(material: material).predividedBy(material),
                twist: options.twist,
                align: options.align,
                miterLimit: options.miterLimit,
                isCancelled: isCancelled
            ).vertexColorsToMaterial(material: material).replacing(material, with: nil)
        case let .lathe(paths, segments: segments) where paths.count == 1:
            mesh = .lathe(paths[0], slices: segments, isCancelled: isCancelled)
        case let .fill(paths) where paths.count == 1:
            mesh = .fill(paths[0], isCancelled: isCancelled)
        case let .loft(paths):
            mesh = .loft(paths, isCancelled: isCancelled)
        case let .hull(vertices):
            let base = Mesh.convexHull(of: vertices, material: material, isCancelled: isCancelled)
            let meshes = ([base] + childMeshes(isCancelled) + childPathMeshes(isCancelled)).map {
                $0.materialToVertexColors(material: material)
            }
            mesh = .convexHull(of: meshes, isCancelled: isCancelled)
                .vertexColorsToMaterial(material: material)
                .replacing(material, with: nil)
        case .minkowski:
            var children = ArraySlice(children.enumerated().sorted {
                switch ($0.1.path, $1.1.path) {
                case let (a?, b?):
                    // Put closed paths before open paths
                    if a.isClosed != b.isClosed {
                        return a.isClosed
                    }
                    // Put convex paths before concave paths
                    let aIsConvex = !a.isClosed || a.facePolygons().allSatisfy(\.isConvex)
                    let bIsConvex = !b.isClosed || b.facePolygons().allSatisfy(\.isConvex)
                    if aIsConvex != bIsConvex {
                        return aIsConvex
                    }
                    // Put smaller paths before larger paths
                    if a.bounds.size != b.bounds.size {
                        return a.bounds.size < b.bounds.size
                    }
                    // Preserve original order
                    return $0.0 < $1.0
                case (_?, nil):
                    // Put meshes before paths
                    return false
                case (nil, _?):
                    return true
                case (nil, nil):
                    // Preserve order (Euclid handles minkowski mesh reordering)
                    return $0.0 < $1.0
                }
            }.map { $1 })
            guard let first = children.popFirst() else {
                mesh = .empty
                break
            }
            var sum: Mesh
            if let shape = first.path(pretransformed: true) {
                guard let next = children.popFirst() else {
                    mesh = .empty
                    break
                }
                let shape = shape.materialToVertexColors(material: first.material)
                if let path = next.path(pretransformed: true) {
                    sum = .fill(shape).minkowskiSum(
                        with: path.materialToVertexColors(material: next.material),
                        isCancelled: isCancelled
                    )
                } else {
                    sum = next.flattened(isCancelled).materialToVertexColors(material: next.material)
                        .minkowskiSum(with: shape, isCancelled: isCancelled)
                }
            } else {
                sum = first.flattened(isCancelled).materialToVertexColors(material: first.material)
            }
            while let next = children.popFirst() {
                if let path = next.path(pretransformed: true) {
                    sum = sum.minkowskiSum(
                        with: path.materialToVertexColors(material: next.material).predividedBy(first.material),
                        isCancelled: isCancelled
                    )
                } else {
                    sum = sum.minkowskiSum(
                        with: next.flattened(isCancelled).materialToVertexColors(material: next.material),
                        isCancelled: isCancelled
                    )
                }
            }
            mesh = sum.vertexColorsToMaterial(material: material).replacing(material, with: nil)
        case .union, .lathe, .extrude, .fill:
            mesh = .union(childMeshes(isCancelled), isCancelled: isCancelled)
        case .xor:
            mesh = .symmetricDifference(flattenedChildren(isCancelled), isCancelled: isCancelled)
        case .difference:
            let first = flattenedFirstChild(isCancelled)
            let meshes = [first] + children.dropFirst().meshes(with: material, isCancelled)
            mesh = .difference(meshes, isCancelled: isCancelled)
        case .intersection:
            let meshes = flattenedChildren(isCancelled)
            mesh = .intersection(meshes, isCancelled: isCancelled)
        case .stencil:
            let first = flattenedFirstChild(isCancelled)
            let meshes = [first] + children.dropFirst().meshes(with: material, isCancelled)
            mesh = .stencil(meshes, isCancelled: isCancelled)
        case let .mesh(mesh):
            self.mesh = .merge([mesh] + childMeshes(isCancelled))
        }
        if !isCancelled() {
            mesh = mesh?.makeWatertight(isCancelled: isCancelled)
            if shouldDetessellate {
                mesh = mesh?.detessellate(isCancelled: isCancelled)
            }
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
        sourceLocation: (@Sendable () -> SourceLocation?)?,
        removingLights: Bool,
        removingGroupTransform: Bool,
        withoutDebug: Bool,
        withoutUnfocusedGeometry: Bool
    ) -> Geometry {
        var type = type
        if removingLights, case .light = type {
            preconditionFailure()
        }
        var m = self.material
        if let material, case let .mesh(mesh) = type {
            if m.opacityPropertyAverageOpacity == 1 {
                m.opacity = material.opacity
            } else if material.opacity?.color != nil {
                let opacity = material.opacity?.averageOpacity ?? 1
                switch m.opacity ?? .color(.white) {
                case let .color(color):
                    let opacity = color.alpha * opacity
                    m.opacity = .color(.init(white: opacity, alpha: opacity))
                case let .texture(texture):
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
        let isRemovingUnfocusedChildren = withoutUnfocusedGeometry && !isFocused
        if isRemovingUnfocusedChildren {
            type = .group
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
                if isRemovingUnfocusedChildren, !$0.childIsFocused {
                    return nil
                }
                return $0._with(
                    name: nil,
                    transform: childTransform,
                    material: material,
                    smoothing: nil,
                    sourceLocation: sourceLocation,
                    removingLights: removingLights,
                    removingGroupTransform: removingGroupTransform,
                    withoutDebug: withoutDebug,
                    withoutUnfocusedGeometry: withoutUnfocusedGeometry
                )
            },
            sourceLocation: _sourceLocation ?? sourceLocation,
            debug: withoutDebug ? false : debug,
            isFocused: isFocused
        )
        copy.mesh = isRemovingUnfocusedChildren ? nil : mesh
        return copy
    }

    /// Determine heuristically whether it's worth detessellating the mesh output
    var shouldDetessellate: Bool {
        switch type {
        case let .extrude(paths, options) where paths.count == 1 && options.along.count <= 1:
            paths[0].subpaths.count > 1 && options.along.allSatisfy { !$0.isClosed }
        case let .fill(paths) where paths.count == 1:
            paths[0].subpaths.count > 1
        case let .loft(paths) where paths.first != paths.last:
            paths[0].subpaths.count > 1 || paths.last!.subpaths.count > 1
        case .hull, .minkowski:
            true
        default:
            false
        }
    }
}

private extension Color {
    func predividedBy(_ other: Color) -> Color {
        .init(
            red: other.red > 0 ? red / other.red : red,
            green: other.green > 0 ? green / other.green : green,
            blue: other.blue > 0 ? blue / other.blue : blue,
            alpha: other.alpha > 0 ? alpha / other.alpha : alpha
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
        mapPolygons { $0.materialToVertexColors(material: material) }
    }
}

// MARK: Stats

public extension Geometry {
    /// Returns if the geometry is a mesh type
    /// - Note: this will return `true` even if mesh is empty has not been built yet
    var hasMesh: Bool {
        switch type {
        case .camera, .light, .circle, .square, .path:
            false
        case .cone, .cylinder, .icosphere, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .group, .mesh:
            true // TODO: should group return false if it has no child meshes?
        }
    }

    /// Returns `true` if this geometry and all descendants have any required meshes built.
    /// This can be used to inspect geometry without triggering additional mesh generation.
    var hasBuiltMeshes: Bool {
        switch type {
        case .camera, .light, .circle, .square, .path, .group:
            break
        case .cone, .cylinder, .icosphere, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .mesh:
            guard mesh != nil else {
                return false
            }
        }
        return children.allSatisfy(\.hasBuiltMeshes)
    }

    /// Returns the total number of distinct objects (paths or meshes) in the shape
    /// - Note: for groups this returns the child count, but children are ignored for other types
    var objectCount: Int {
        switch type {
        case .group:
            children.reduce(0) { $0 + $1.objectCount }
        case .camera, .light:
            0
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .path, .mesh:
            1
        }
    }

    /// Returns the child count for the shape, not including grandchildren
    /// - Note: only child meshes or groups are counted
    var childCount: Int {
        switch type {
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .extrude, .lathe, .fill, .loft,
             .mesh, .path, .camera, .light:
            0 // TODO: should paths/points/submeshes be treated as children?
        case .union, .xor, .difference, .intersection, .stencil, .group, .hull, .minkowski:
            children.count
        }
    }

    /// Builds the mesh (if needed) and returns the polygon count
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    func polygons(_ isCancelled: @escaping CancellationHandler) -> [Polygon] {
        switch type {
        case .group:
            children.reduce(into: []) { $0 += $1.polygons(isCancelled) }
        default:
            mesh(isCancelled)?.polygons ?? []
        }
    }

    /// Builds the mesh (if needed) and returns the triangle count
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    func triangles(_ isCancelled: @escaping CancellationHandler) -> [Polygon] {
        polygons(isCancelled).flatMap { $0.triangulate() }
    }

    /// Returns if the geometry is watertight
    /// Builds and caches the mesh (if required). Already-cached meshes will be re-used if available
    func isWatertight(_ isCancelled: @escaping CancellationHandler) -> Bool {
        switch type {
        case .cone, .cylinder, .icosphere, .sphere, .cube:
            true
        case .group:
            children.allSatisfy { $0.isWatertight(isCancelled) }
        default:
            mesh(isCancelled)?.isWatertight ?? true
        }
    }

    /// Returns the exact bounds with specified transform
    /// Builds and caches the mesh if required. Already-cached meshes will be re-used if available
    func exactBounds(
        with transform: Transform,
        _ isCancelled: @escaping CancellationHandler = { false }
    ) -> Bounds {
        switch type {
        case .camera, .light:
            return .empty
        case .group, .union, .lathe([], _), .extrude([], _), .fill([]):
            return Bounds(children.map {
                $0.exactBounds(with: $0.transform * transform, isCancelled)
            })
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .path, .extrude, .lathe:
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
        case .hull, .mesh:
            let bounds: Bounds = if transform.rotation == .identity {
                type.bounds.transformed(by: transform)
            } else {
                Bounds(type.representativePoints.transformed(by: transform))
            }
            return children.reduce(bounds) {
                $0.union($1.exactBounds(with: $1.transform * transform, isCancelled))
            }
        case .minkowski:
            return children.reduce(.empty) {
                $0.minkowskiSum(with: $1.exactBounds(with: $1.transform * transform, isCancelled))
            }
        case .xor, .difference, .intersection:
            if transform.rotation == .identity {
                return mesh(isCancelled)?.bounds.transformed(by: transform) ?? .empty
            }
            return mesh(isCancelled)?.transformed(by: transform).bounds ?? .empty
        case .stencil:
            return children.first.map {
                $0.exactBounds(with: $0.transform * transform, isCancelled)
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
        return switch type {
        case .cube:
            scaleFactor
        case .group:
            children.reduce(0) { $0 + $1.volume(with: $1.transform, isCancelled) } * scaleFactor
        default:
            (mesh(isCancelled)?.signedVolume ?? 0) * scaleFactor
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
