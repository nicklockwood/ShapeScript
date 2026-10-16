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
public typealias CancellationHandler = Euclid.CancellationHandler

private struct GeometryBuildProgressPlan {
    let totalUnitCount: Int
    let unitCounts: [ObjectIdentifier: Int]

    func unitCount(for geometry: Geometry) -> Int {
        unitCounts[ObjectIdentifier(geometry)] ?? 1
    }
}

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

    // Note: equality and hashing describe the modeled geometry, not render/editor
    // state. Debug/focus/hide flags affect how the geometry is presented, while opacity,
    // source locations, and parent links are derived or contextual metadata.

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(name)
        hasher.combine(transform)
        hasher.combine(material)
        hasher.combine(smoothing)
        hasher.combine(children)
        // Excludes isOpaque, sourceLocation, parent, debug, focus and hide
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
        // Excludes isOpaque, sourceLocation, parent, debug, focus and hide
        else {
            return false
        }
        return true
    }

    /// The children currently rendered in place of, or in addition to, this geometry.
    var renderedChildren: [Geometry] {
        renderedChildren(focus: childIsFocused)
    }

    /// The children currently rendered in place of, or in addition to, this geometry.
    func renderedChildren(focus: Bool) -> [Geometry] {
        let rendered: [Geometry] = switch type {
        case .group:
            children
        case .difference, .stencil:
            if childDebug || childIsFocused {
                children
            } else {
                mesh == nil ? Array(children.prefix(1)) : []
            }
        case .loft, .union, .xor, .extrude, .fill, .hull, .mesh:
            mesh == nil || childDebug || childIsFocused ? children : []
        case .minkowski:
            if childDebug || childIsFocused {
                children
            } else if mesh == nil {
                children.filter { !$0.isHidden }.max {
                    $0.overestimatedBounds.size < $1.overestimatedBounds.size
                }.map { [$0] } ?? []
            } else {
                []
            }
        case .intersection, .lathe:
            childDebug || childIsFocused ? children : []
        case .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .path, .camera, .light:
            []
        }
        guard focus, !isFocused else {
            return rendered.filter { !$0.isHidden }
        }
        return rendered.filter {
            !$0.isHidden && ($0.isFocused || $0.childIsFocused)
        }
    }

    /// Whether `renderedChildren` should be traversed as debug/focus overlay content.
    var rendersChildrenAsDebugOverlay: Bool {
        switch type {
        case .difference, .stencil, .intersection, .lathe, .minkowski:
            childDebug || childIsFocused
        case .loft, .union, .xor, .extrude, .fill, .hull:
            mesh != nil && (childDebug || childIsFocused)
        case .group,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .path, .mesh, .camera, .light:
            false
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

    /// Prevent geometry from being rendered
    public internal(set) var isHidden: Bool {
        didSet {
            if isHidden, type == .group {
                children.forEach { $0.isHidden = true }
            }
        }
    }

    let cacheKey: GeometryCache.Key
    let indexesByMaterial: [Material: Int]
    let materialsByIndex: [Material]

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
        isFocused: Bool = false,
        isHidden: Bool = false
    ) {
        var material = material
        var useMaterialForCache = false
        var children = children
        var type = type
        // Keep semantic path children alongside any explicit paths. The explicit paths
        // retain the existing normalization and per-glyph mesh caching behavior.
        if children.contains(where: { $0.path != nil }) {
            let pathType: GeometryType?
            switch type {
            case let .extrude(paths, options) where !paths.isEmpty:
                pathType = type
                type = .extrude([], options)
            case let .lathe(paths, options) where !paths.isEmpty:
                pathType = type
                type = .lathe([], options)
            case let .fill(paths) where !paths.isEmpty:
                pathType = type
                type = .fill([])
            case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
                 .circle, .square, .text, .path, .mesh, .camera, .light,
                 .extrude, .lathe, .loft, .fill, .hull, .minkowski,
                 .union, .difference, .intersection, .xor, .stencil:
                pathType = nil
            }
            if let pathType {
                children.append(Geometry(
                    type: pathType,
                    name: nil,
                    transform: .identity,
                    material: material,
                    smoothing: smoothing,
                    children: [],
                    sourceLocation: sourceLocation
                ))
            }
        }
        switch type {
        case var .extrude(paths, options):
            switch (paths.count, options.along.count) {
            case (0, _):
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
        case var .lathe(paths, options):
            switch (paths.count, options.along.count) {
            case (0, _):
                break
            case (1, 0):
                (paths, material) = paths.vertexColorsToMaterial(material: material)
                type = .lathe(paths, options)
            case (1, 1):
                var pair = (paths + options.along)
                (pair, material) = pair.vertexColorsToMaterial(material: material)
                options.along = [pair[1]]
                type = .lathe([pair[0]], options)
            case (_, 0):
                // For lathes with multiple paths, convert each path to a
                // separate child geometry so they can be renderered individually
                type = .lathe([], .init(segments: 0))
                children = paths.map { path in
                    // TODO: normalize path y-position for better caching
                    let (path, material) = path.vertexColorsToMaterial(material: material)
                    return Geometry(
                        type: .lathe([path], options),
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
                // For lathes with multiple paths, convert each path to a
                // separate child geometry so they can be renderered individually
                type = .lathe([], .init(segments: 0))
                children = paths.flatMap { path in
                    options.along.map { along in
                        let (along, offset) = along.withNormalizedPosition()
                        let (pair, material) = [path, along].vertexColorsToMaterial(material: material)
                        var options = options
                        options.along = [pair[1]]
                        return Geometry(
                            type: .lathe([pair[0]], options),
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
        case let .text(text):
            let paths: [Path]
            (paths, material) = text.paths.vertexColorsToMaterial(material: material)
            type = .text(TextPath(
                text: text.text,
                wrapWidth: text.wrapWidth,
                detail: text.detail,
                paths: paths
            ))
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
            if isHidden {
                children.forEach { $0.isHidden = true }
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
        self.isHidden = isHidden

        var hasVariedMaterials = false
        var isOpaque = material.isOpaque
        var cacheIndexesByMaterial = [Material: Int]()
        var cacheMaterialsByIndex = [Material]()

        func materialKey(
            for geometry: Geometry,
            inheritedMaterial: Material
        ) -> GeometryCache.MaterialKey? {
            guard geometry.material != inheritedMaterial else {
                return nil
            }
            if useMaterialForCache || geometry.type.usesMaterialInMeshGeneration {
                return .value(geometry.material)
            }
            if let index = cacheIndexesByMaterial[geometry.material] {
                return .index(index)
            }
            let index = cacheIndexesByMaterial.count
            cacheIndexesByMaterial[geometry.material] = index
            cacheMaterialsByIndex.append(geometry.material)
            return .index(index)
        }

        func flattenedCacheKey(for geometry: Geometry) -> GeometryCache.Key {
            isOpaque = isOpaque && geometry.material.isOpaque
            if !hasVariedMaterials, geometry.material != material {
                hasVariedMaterials = true
            }
            return GeometryCache.Key(
                type: geometry.type,
                material: materialKey(for: geometry, inheritedMaterial: material),
                smoothing: geometry.smoothing,
                transform: geometry.transform,
                flipped: geometry.transform.isFlipped,
                children: geometry.visibleChildren.map(flattenedCacheKey)
            )
        }

        let visibleChildren = type.visibleChildren(in: children)
        let childKeys = type.isLeaf ? [] : visibleChildren.map(flattenedCacheKey)

        // Must be set after child keys are generated
        self.isOpaque = isOpaque
        self.indexesByMaterial = cacheIndexesByMaterial
        self.materialsByIndex = cacheMaterialsByIndex
        self.cacheKey = .init(
            type: type,
            material: useMaterialForCache && hasVariedMaterials ? .value(material) : nil,
            smoothing: smoothing,
            transform: .identity,
            flipped: transform.isFlipped,
            children: childKeys
        )

        // Compute the overestimated, non-transformed bounds
        switch type {
        case .difference, .stencil:
            self._overestimatedBounds = visibleChildren.first.map(\.overestimatedBounds) ?? .empty
        case .intersection:
            self._overestimatedBounds = visibleChildren.dropFirst()
                .reduce(visibleChildren.first?.overestimatedBounds ?? .empty) {
                    $0.intersection($1.overestimatedBounds)
                }
        case .union, .xor, .group:
            self._overestimatedBounds = Bounds(visibleChildren.map(\.overestimatedBounds))
        case let .extrude([], options):
            let paths = visibleChildren.flatMap { $0.paths(pretransformed: true) }
            self._overestimatedBounds = GeometryType.extrude(paths, options).bounds
                .union(Bounds(visibleChildren.filter(\.hasMesh).map(\.overestimatedBounds)))
        case let .lathe([], options):
            let paths = visibleChildren.flatMap { $0.paths(pretransformed: true) }
            self._overestimatedBounds = GeometryType.lathe(paths, options).bounds
                .union(Bounds(visibleChildren.filter(\.hasMesh).map(\.overestimatedBounds)))
        case .lathe, .fill, .extrude, .loft, .mesh, .hull:
            self._overestimatedBounds = type.bounds.union(Bounds(visibleChildren.map(\.overestimatedBounds)))
        case .minkowski:
            self._overestimatedBounds = visibleChildren.reduce(.empty) {
                $0.minkowskiSum(with: $1.overestimatedBounds)
            }
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square, .text, .path:
            self._overestimatedBounds = type.bounds
        case .camera, .light:
            self._overestimatedBounds = .empty
        }

        // Must be set after all other properties
        children.forEach { $0.parent = self }
    }
}

public extension Geometry {
    /// Non-hidden children
    var visibleChildren: [Geometry] {
        type.visibleChildren(in: children)
    }

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
        case let .text(text):
            let path = Path(subpaths: text.paths.map { $0.materialToVertexColors(material: material) })
            return pretransformed ? path.transformed(by: transform) : path
        case let .path(path):
            let path = path.materialToVertexColors(material: material)
            return pretransformed ? path.transformed(by: transform) : path
        case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
             .extrude, .lathe, .loft, .fill, .hull, .minkowski,
             .union, .difference, .intersection, .xor, .stencil,
             .mesh, .camera, .light:
            return nil
        }
    }

    /// Paths represented by a primitive, preserving individual text glyphs for caching.
    func paths(pretransformed: Bool) -> [Path] {
        let paths: [Path] = if case let .text(text) = type {
            text.paths.map { $0.materialToVertexColors(material: material) }
        } else {
            path.map { [$0] } ?? []
        }
        return pretransformed ? paths.transformed(by: transform) : paths
    }

    /// Returns `true` if the geometry's' children should be rendered in debug mode
    var childDebug: Bool {
        !isHidden && (debug || children.contains(where: \.childDebug))
    }

    /// Returns `true` if the geometry or any of its children are focused
    var childIsFocused: Bool {
        !isHidden && (isFocused || children.contains(where: \.childIsFocused))
    }

    /// Returns `true` if this geometry is rendered as part of the scene
    func isRenderedInScene(focus: Bool) -> Bool {
        guard !isHidden, !focus || isFocused else {
            return false
        }
        let target = self
        var geometry = self
        while let parent = geometry.parent {
            guard parent.renderedChildren(focus: focus).contains(where: { $0 === geometry }) ||
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
            isFocused: isFocused,
            isHidden: isHidden
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

        if !children.isEmpty, children.allSatisfy({ $0.path != nil }) {
            let paths = children.flatMap { $0.paths(pretransformed: true) }
            let builderType: GeometryType? = switch type {
            case let .extrude([], options): .extrude(paths, options)
            case let .lathe([], options): .lathe(paths, options)
            case .fill([]): .fill(paths)
            case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
                 .circle, .square, .text, .path, .mesh, .camera, .light,
                 .extrude, .lathe, .loft, .fill, .hull, .minkowski,
                 .union, .difference, .intersection, .xor, .stencil:
                nil
            }
            if let builderType {
                return copy(type: builderType).insetByRewritingPrimitives(
                    by: distance,
                    sourceLocation: sourceLocation,
                    isCancelled: isCancelled
                )
            }
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
            let mesh = Mesh.icosphere(
                subdivisions: subdivisions,
                wrapMode: .none,
                isCancelled: isCancelled
            )
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
            return copy(type: .loft(paths.map { $0.inset(by: distance, isCancelled: isCancelled) }))
        case .circle, .square, .text, .path:
            return copy(type: path(pretransformed: true).map {
                .path($0.inset(by: distance, isCancelled: isCancelled))
            } ?? type, transform: .identity)
        case let .fill(paths) where paths.count == 1:
            return copy(type: .fill([paths[0].inset(by: distance, isCancelled: isCancelled)]))
        case let .extrude(paths, options) where paths.count == 1 && options.along.isEmpty:
            if distance > 0 {
                if mesh(isCancelled)?.inset(by: distance, isCancelled: isCancelled).isEmpty == true {
                    return copy(type: .mesh(.empty))
                }
            }
            let depth = max(0, 1 - distance * 2)
            let path = paths[0].inset(by: distance, isCancelled: isCancelled)
            guard !path.isEmpty, depth > 0 else {
                return copy(type: .mesh(.empty))
            }
            let offset = path.faceNormal * depth
            return copy(type: .loft([
                path.translated(by: -offset / 2),
                path.translated(by: offset / 2),
            ]))
        case let .extrude(paths, options) where paths.count == 1 && options.along.count == 1:
            let path = paths[0].inset(by: distance, isCancelled: isCancelled)
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
                    material: material,
                    isCancelled: isCancelled
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
            withoutHiddenOrUnfocused: false
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
            withoutHiddenOrUnfocused: false
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
            withoutHiddenOrUnfocused: false
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
            withoutHiddenOrUnfocused: false
        )
    }

    /// Returns a copy of the geometry with hidden or unfocussed children removed
    func withoutHiddenOrUnfocused() -> Geometry {
        guard childIsFocused || childIsHidden else {
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
            withoutHiddenOrUnfocused: true
        )
    }

    /// Builds the meshes for the receiver and all its descendents
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    /// - Parameter progress: An optional object for monitoring or cancelling the build
    /// - Returns: false if cancelled or true when completed
    func build(progress: RenderProgress? = nil) -> Bool {
        _build(progress: progress, isCancelled: { false })
    }

    /// Builds the meshes for the receiver and all its descendents
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    /// - Parameter isCancelled: A closure that returns true when the build should be cancelled
    /// - Returns: false if cancelled or true when completed
    func build(_ isCancelled: @escaping CancellationHandler) -> Bool {
        _build(progress: nil, isCancelled: isCancelled)
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
        guard !isHidden else {
            return .empty
        }
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

    /// Returns `true` if the geometry or any of its children are hidden
    var childIsHidden: Bool {
        isHidden || children.contains(where: \.childIsHidden)
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

private extension GeometryType {
    var usesMaterialInMeshGeneration: Bool {
        switch self {
        case let .extrude(_, options) where options.along.count == 1:
            true
        case .hull, .minkowski:
            true
        case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .extrude, .lathe, .loft, .fill,
             .union, .difference, .intersection, .xor, .stencil,
             .path, .mesh, .camera, .light:
            false
        }
    }

    func visibleChildren(in children: [Geometry]) -> [Geometry] {
        switch self {
        case .difference, .stencil:
            guard let first = children.first, !first.isHidden else {
                return []
            }
            return [first] + children.dropFirst().filter { !$0.isHidden }
        case .camera, .light,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .path:
            return []
        case .group, .union, .xor, .intersection, .lathe, .extrude, .loft, .fill,
             .hull, .minkowski, .mesh:
            return children.filter { !$0.isHidden }
        }
    }
}

private extension Collection<Geometry> {
    /// Computes the union of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Results include both material (if specified) and transform
    func flattened(with material: Material?, _ isCancelled: @escaping Euclid.CancellationHandler) -> [Mesh] {
        compactMap { isCancelled() ? nil : $0.flattened(with: material, isCancelled) }
    }

    /// Returns the meshes of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Results include both material (if specified) and transform
    func meshes(with material: Material?, _ isCancelled: @escaping Euclid.CancellationHandler) -> [Mesh] {
        flatMap { isCancelled() ? [] : $0.meshes(with: material, isCancelled) }
    }

    /// Returns a merged mesh for all of the geometries in the collection and all their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Results include both material and transform
    func merged(_ isCancelled: @escaping Euclid.CancellationHandler) -> Mesh {
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
    static let maximumEstimatedPolygonCount = 100_000
    static let maximumCSGProgressUnitCount = 10_000_000
    // Union estimates are especially noisy because Euclid groups disjoint meshes before clipping.
    // Keep enclosing unions from outweighing the complex child operations they contain.
    static let maximumUnionProgressUnitCount = 1_000_000

    /// The estimated progress units needed to build this geometry's leaf meshes
    var leafProgressUnitCount: Int {
        let childUnitCount = switch type {
        case .difference, .stencil:
            visibleChildren.first?.leafProgressUnitCount ?? 0
        case .group, .union, .xor, .intersection, .hull, .minkowski,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .extrude, .lathe, .loft, .fill,
             .path, .mesh, .camera, .light:
            visibleChildren.reduce(0) { $0 + $1.leafProgressUnitCount }
        }
        return (isLeaf ? ownBuildProgressUnitCount : 1) + childUnitCount
    }

    /// The estimated progress units needed to build this geometry's preview meshes
    var previewProgressUnitCount: Int {
        1 + visibleChildren.reduce(0) { $0 + $1.previewProgressUnitCount }
    }

    /// The estimated progress units needed to build this geometry's final meshes
    var finalProgressUnitCount: Int {
        (isLeaf ? 1 : ownBuildProgressUnitCount) +
            finalBuildChildren.reduce(0) { $0 + $1.finalProgressUnitCount }
    }

    /// The estimated total progress units needed to build this geometry
    var buildProgressUnitCount: Int {
        leafProgressUnitCount + previewProgressUnitCount + finalProgressUnitCount
    }

    /// The estimated progress units needed to build this geometry's own mesh
    var ownBuildProgressUnitCount: Int {
        func bounded(_ count: Int) -> Int {
            min(max(1, count), 5000)
        }

        func pathPointCount(_ paths: [Path]) -> Int {
            max(1, paths.reduce(0) { $0 + $1.points.count })
        }

        switch type {
        case .group, .circle, .square, .text, .path, .camera, .light, .cube:
            return 1
        case let .cone(segments), let .cylinder(segments), let .sphere(segments):
            return bounded(segments)
        case let .icosphere(subdivisions):
            return bounded(20 << min(max(0, subdivisions), 8))
        case let .extrude(paths, options):
            let profileCount = pathPointCount(paths + visibleChildren.flatMap {
                $0.paths(pretransformed: true)
            })
            let alongCount = pathPointCount(options.along)
            return bounded(profileCount * max(1, alongCount))
        case let .lathe(paths, options):
            return bounded(pathPointCount(paths + visibleChildren.flatMap {
                $0.paths(pretransformed: true)
            }) * max(1, options.segments))
        case let .loft(paths), let .fill(paths):
            return bounded(pathPointCount(paths + visibleChildren.flatMap {
                $0.paths(pretransformed: true)
            }))
        case let .hull(vertices):
            return bounded(vertices.count)
        case let .mesh(mesh):
            return bounded(mesh.polygons.count)
        case .union:
            return min(
                csgProgressUnitCount + estimatedPolygonCount * 2,
                Self.maximumUnionProgressUnitCount
            )
        case .xor, .difference, .intersection, .stencil:
            return min(
                csgProgressUnitCount + estimatedPolygonCount * 2,
                Self.maximumCSGProgressUnitCount
            )
        case .minkowski:
            return min(csgProgressUnitCount * 2, Self.maximumCSGProgressUnitCount)
        }
    }

    /// An estimate of the polygon count produced by this geometry, without building its mesh.
    /// Container estimates deliberately include descendants so nested CSG operations retain
    /// the complexity of the meshes they consume.
    var estimatedPolygonCount: Int {
        func bounded(_ count: Int) -> Int {
            min(max(0, count), Self.maximumEstimatedPolygonCount)
        }

        func product(_ lhs: Int, _ rhs: Int) -> Int {
            guard lhs > 0, rhs > 0 else {
                return 0
            }
            return lhs > Self.maximumEstimatedPolygonCount / rhs ?
                Self.maximumEstimatedPolygonCount : lhs * rhs
        }

        func childPolygonCount() -> Int {
            visibleChildren.reduce(0) {
                bounded($0 + $1.estimatedPolygonCount)
            }
        }

        if let mesh {
            return bounded(mesh.polygons.count)
        }
        switch type {
        case .group:
            return childPolygonCount()
        case .union, .xor, .difference, .intersection, .stencil, .minkowski:
            return csgProgressEstimate.polygonCount
        case let .mesh(mesh):
            return bounded(mesh.polygons.count + childPolygonCount())
        case .hull:
            return bounded(ownBuildProgressUnitCount + childPolygonCount())
        case .circle, .square, .text, .path, .camera, .light:
            return 0
        case let .cone(segments):
            return product(segments, 2)
        case let .cylinder(segments):
            return product(segments, 3)
        case let .sphere(segments):
            return product(segments, max(2, segments / 2))
        case let .icosphere(subdivisions):
            return bounded(20 << (min(max(0, subdivisions), 8) * 2))
        case .cube:
            return 6
        case .extrude, .lathe, .loft, .fill:
            return bounded(ownBuildProgressUnitCount)
        }
    }

    /// The estimated progress units needed for this geometry's CSG operation
    var csgProgressUnitCount: Int {
        csgProgressEstimate.unitCount
    }

    /// Estimates both the work and intermediate polygon growth for this CSG operation.
    var csgProgressEstimate: (unitCount: Int, polygonCount: Int) {
        let children = visibleChildren
        let counts = children.map(\.estimatedPolygonCount)
        let maximumUnits = Self.maximumCSGProgressUnitCount
        let maximumPolygons = Self.maximumEstimatedPolygonCount

        func adding(_ lhs: Int, _ rhs: Int, maximum: Int) -> Int {
            let rhs = min(max(0, rhs), maximum)
            return min(lhs, maximum - rhs) + rhs
        }

        func sum(_ values: some Sequence<Int>, maximum: Int) -> Int {
            values.reduce(0) { adding($0, $1, maximum: maximum) }
        }

        func product(_ lhs: Int, _ rhs: Int, maximum: Int) -> Int {
            guard lhs > 0, rhs > 0 else { return 0 }
            return lhs > maximum / rhs ? maximum : lhs * rhs
        }

        func scaledProduct(_ lhs: Int, _ rhs: Int, by scale: Double, maximum: Int) -> Int {
            guard lhs > 0, rhs > 0, scale > 0 else { return 0 }
            return min(
                Int((Double(lhs) * Double(rhs) * min(scale, 1)).rounded(.up)),
                maximum
            )
        }

        func overlapFraction(_ lhs: Bounds, _ rhs: Bounds) -> Double {
            func volume(of bounds: Bounds) -> Double {
                let size = bounds.size
                return size.x * size.y * size.z
            }

            let intersectionVolume = volume(of: lhs.intersection(rhs))
            let smallerVolume = min(volume(of: lhs), volume(of: rhs))
            guard smallerVolume > 0 else { return lhs.intersects(rhs) ? 1 : 0 }
            return min(intersectionVolume / smallerVolume, 1)
        }

        var unitCount = max(1, sum(counts, maximum: maximumUnits))
        var polygonCount = sum(counts, maximum: maximumPolygons)

        func addWork(_ lhs: Int, _ rhs: Int, scale: Double = 1) {
            unitCount = adding(
                unitCount,
                scaledProduct(
                    lhs,
                    rhs,
                    by: scale,
                    maximum: maximumUnits
                ),
                maximum: maximumUnits
            )
        }

        func estimateSequentialBoolean() {
            polygonCount = counts[0]
            for index in counts.indices.dropFirst() {
                let inputPolygonCount = polygonCount
                addWork(inputPolygonCount, counts[index])
                // Boolean clipping can add fragments from the next operand, but treating
                // the result size as a product would compound exponentially. The work for
                // the next operation still grows because it uses this larger result.
                polygonCount = adding(
                    polygonCount,
                    counts[index],
                    maximum: maximumPolygons
                )
            }
        }

        switch type {
        case .difference, .stencil:
            guard let first = children.first else {
                return (unitCount, polygonCount)
            }
            polygonCount = counts[0]
            for index in children.indices.dropFirst()
                where first.overestimatedBounds.intersects(children[index].overestimatedBounds)
            {
                let inputPolygonCount = polygonCount
                addWork(inputPolygonCount, counts[index])
                polygonCount = adding(
                    polygonCount,
                    counts[index],
                    maximum: maximumPolygons
                )
            }
        case .intersection:
            if !counts.isEmpty {
                estimateSequentialBoolean()
            }
        case .union:
            for lhs in children.indices {
                for rhs in children.indices where rhs > lhs {
                    addWork(
                        counts[lhs],
                        counts[rhs],
                        scale: overlapFraction(
                            children[lhs].overestimatedBounds,
                            children[rhs].overestimatedBounds
                        )
                    )
                }
            }
        case .xor:
            for lhs in children.indices {
                for rhs in children.indices where rhs > lhs &&
                    children[lhs].overestimatedBounds.intersects(children[rhs].overestimatedBounds)
                {
                    addWork(counts[lhs], counts[rhs])
                }
            }
        case .minkowski:
            if let first = counts.first {
                polygonCount = first
                for count in counts.dropFirst() {
                    addWork(polygonCount, count)
                    polygonCount = product(polygonCount, count, maximum: maximumPolygons)
                }
            }
        case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .extrude, .lathe, .loft, .fill,
             .hull, .path, .mesh, .camera, .light:
            break
        }
        return (unitCount, max(1, polygonCount))
    }

    func _build(progress: RenderProgress?, isCancelled: @escaping CancellationHandler) -> Bool {
        let progress = progress ?? RenderProgress()
        let plan = buildProgressPlan
        progress.beginTracking(
            totalUnitCount: plan.totalUnitCount,
            isCancelled: isCancelled
        )
        defer { progress.endTracking() }
        let didBuild = buildLeaves(progress, plan: plan) &&
            buildPreview(progress) &&
            buildFinal(progress, plan: plan)
        if didBuild {
            progress.finish()
        }
        return didBuild
    }

    var buildProgressPlan: GeometryBuildProgressPlan {
        var result = [ObjectIdentifier: Int]()
        collectBuildUnitCounts(into: &result)
        return GeometryBuildProgressPlan(
            totalUnitCount: buildProgressUnitCount,
            unitCounts: result
        )
    }

    func collectBuildUnitCounts(into result: inout [ObjectIdentifier: Int]) {
        result[ObjectIdentifier(self)] = ownBuildProgressUnitCount
        for child in visibleChildren {
            child.collectBuildUnitCounts(into: &result)
        }
    }

    /// Computes the union of the meshes of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes the receiver's material but not its transform
    func flattenedChildren(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        visibleChildren.flattened(with: material, isCancelled)
    }

    /// Returns a merged mesh for all of the descendents of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Does not include the material or transform of the receiver
    func mergedChildren(_ isCancelled: @escaping CancellationHandler) -> Mesh {
        visibleChildren.merged(isCancelled)
    }

    /// Computes the union of the meshes of the first child of the receiver
    /// The cache is neither checked nor updated. Only already-built meshes are included in the union result
    /// - Note: Includes the receiver's material but not its transform
    func flattenedFirstChild(_ isCancelled: @escaping CancellationHandler) -> Mesh {
        visibleChildren.first.map { $0.flattened(with: self.material, isCancelled) } ?? .empty
    }

    /// Returns the meshes of the receivers children and their descendents
    /// The cache is neither checked nor updated. Only already-built meshes are returned
    /// - Note: Includes the receiver's material but not its transform
    func childMeshes(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        visibleChildren.meshes(with: material, isCancelled)
    }

    /// Returns hull-compatible meshes for semantic path children such as circles and squares.
    /// Path-child vertices are intentionally generated here instead of being stored in
    /// `GeometryType.hull`, so exports can preserve the child semantics without also
    /// emitting duplicate fallback vertex geometry.
    /// - Note: Includes each child's material and transform, but not the receiver's transform.
    func childPathMeshes(_ isCancelled: @escaping CancellationHandler) -> [Mesh] {
        visibleChildren.compactMap { child in
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
        guard !isHidden else {
            return []
        }
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
    func buildLeaves(_ progress: RenderProgress, plan: GeometryBuildProgressPlan) -> Bool {
        guard progress.enter(.buildingLeaves) else {
            return false
        }
        let unitCount = isLeaf ? plan.unitCount(for: self) : 1
        guard progress.beginUnit(.buildingLeaves, unitCount: unitCount) else {
            return false
        }
        if isLeaf {
            let isCancelled: CancellationHandler = { progress.isCancelled }
            if !buildMesh(isCancelled) {
                return false
            }
        }
        guard progress.completeUnit(.buildingLeaves, by: unitCount) else {
            return false
        }
        switch type {
        case .difference, .stencil:
            return visibleChildren.first?.buildLeaves(progress, plan: plan) ?? true
        case .group, .union, .xor, .intersection, .hull, .minkowski,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .circle, .square, .text, .extrude, .lathe, .loft, .fill,
             .path, .mesh, .camera, .light:
            for child in visibleChildren where !child.buildLeaves(progress, plan: plan) {
                return false
            }
            return true
        }
    }

    /// With leaves built, do a rough preview
    /// - Returns: false if cancelled or true when completed
    func buildPreview(_ progress: RenderProgress) -> Bool {
        guard progress.enter(.buildingPreview) else {
            return false
        }
        for child in visibleChildren where !child.buildPreview(progress) {
            return false
        }
        if let mesh = cache?[mesh: self] {
            self.mesh = mesh
            return progress.completeUnit(.buildingPreview)
        }
        guard progress.beginUnit(.buildingPreview, unitCount: 1) else {
            return false
        }
        switch type {
        case .extrude([], _), .lathe([], _), .fill([]):
            mesh = nil
        case .mesh where children.isEmpty:
            assert(mesh != nil) // Already built by buildLeaves
        case .mesh:
            break // Children-only or mesh + children
        case .group, .circle, .square, .text, .path,
             .cone, .cylinder, .icosphere, .sphere, .cube,
             .extrude, .lathe, .loft, .fill:
            assert(isLeaf) // Leaves
        case .union, .xor, .intersection, .stencil, .difference,
             .hull, .minkowski, .camera, .light:
            mesh = nil
        }
        return progress.completeUnit(.buildingPreview)
    }

    /// Builds and caches the final mesh for the receiver and all its descendents
    /// - Returns: false if cancelled or true when completed
    func buildFinal(_ progress: RenderProgress, plan: GeometryBuildProgressPlan) -> Bool {
        guard progress.enter(.buildingFinal) else {
            return false
        }
        for child in finalBuildChildren {
            if !child.buildFinal(progress, plan: plan) {
                return false
            }
        }
        let unitCount = isLeaf ? 1 : plan.unitCount(for: self)
        guard progress.beginUnit(.buildingFinal, unitCount: unitCount) else {
            return false
        }
        if !isLeaf || mesh == nil {
            let isCancelled: CancellationHandler = { progress.isCancelled }
            if !buildMesh(isCancelled) {
                return false
            }
        }
        return progress.completeUnit(.buildingFinal, by: unitCount)
    }

    /// A direct union operand over which the Minkowski sum can be distributed.
    var distributableMinkowskiUnion: Geometry? {
        guard case .minkowski = type else {
            return nil
        }
        return visibleChildren.first { child in
            if case .union = child.type {
                return !child.visibleChildren.isEmpty
            }
            return false
        }
    }

    /// Children whose final meshes are needed to build this geometry.
    var finalBuildChildren: [Geometry] {
        guard let distributedUnion = distributableMinkowskiUnion else {
            return visibleChildren
        }
        return visibleChildren.flatMap { child in
            child === distributedUnion ? child.visibleChildren : [child]
        }
    }

    /// Builds and caches the mesh for the receiver. Already-cached mesh will be re-used if available
    /// - Note: Child meshes should have already been built before calling (unchecked)
    /// - Returns: false if cancelled or true when completed
    func buildMesh(_ isCancelled: @escaping CancellationHandler) -> Bool {
        if !hasMesh || type == .group {
            mesh = .empty
            return !isCancelled()
        }
        return cache?.buildMesh(for: self) { mesh in
            if let mesh {
                self.mesh = mesh
                return !isCancelled()
            }
            return buildUncachedMesh(isCancelled)
        } ?? buildUncachedMesh(isCancelled)
    }

    /// Builds and sets the mesh
    /// - Note: Child meshes should have already been built before calling (unchecked)
    /// - Returns: false if cancelled or true when completed
    func buildUncachedMesh(_ isCancelled: @escaping CancellationHandler) -> Bool {
        guard !isCancelled() else { return false }
        switch type {
        case .group, .circle, .square, .text, .path, .camera, .light:
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
        case let .lathe(paths, options) where paths.count == 1 && options.along.isEmpty:
            mesh = .lathe(paths[0], slices: options.segments, isCancelled: isCancelled)
        case let .lathe(paths, options) where paths.count == 1 && options.along.count == 1:
            mesh = .lathe(
                paths[0].materialToVertexColors(material: material),
                along: options.along[0].materialToVertexColors(material: material).predividedBy(material),
                slices: options.segments,
                miterLimit: options.miterLimit,
                isCancelled: isCancelled
            ).vertexColorsToMaterial(material: material).replacing(material, with: nil)
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
            func minkowskiSum(replacing union: Geometry? = nil, with replacement: Mesh? = nil) -> Mesh {
                var children = ArraySlice(children.enumerated().sorted {
                    switch ($0.1.path, $1.1.path) {
                    case let (a?, b?):
                        // Put closed paths before open paths
                        if a.isClosed != b.isClosed {
                            return a.isClosed
                        }
                        // Put convex paths before concave paths
                        let aIsConvex = !a.isClosed || a.facePolygons(
                            isCancelled: isCancelled
                        ).allSatisfy(\.isConvex)
                        let bIsConvex = !b.isClosed || b.facePolygons(
                            isCancelled: isCancelled
                        ).allSatisfy(\.isConvex)
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
                        // Preserve original order (Euclid handles minkowski mesh reordering)
                        return $0.0 < $1.0
                    }
                }.map { $1 })
                guard let first = children.popFirst() else {
                    return .empty
                }
                func mesh(for child: Geometry) -> Mesh {
                    if child === union, let replacement {
                        return replacement
                    }
                    return child.flattened(isCancelled)
                }
                var sum: Mesh
                if let shape = first.path(pretransformed: true) {
                    guard let next = children.popFirst() else {
                        return .empty
                    }
                    let shape = shape.materialToVertexColors(material: first.material)
                    if let path = next.path(pretransformed: true) {
                        sum = .fill(shape, isCancelled: isCancelled).minkowskiSum(
                            with: path.materialToVertexColors(material: next.material),
                            isCancelled: isCancelled
                        )
                    } else {
                        sum = mesh(for: next).materialToVertexColors(material: next.material)
                            .minkowskiSum(with: shape, isCancelled: isCancelled)
                    }
                } else {
                    sum = mesh(for: first).materialToVertexColors(material: first.material)
                }
                while let next = children.popFirst() {
                    if let path = next.path(pretransformed: true) {
                        sum = sum.minkowskiSum(
                            with: path.materialToVertexColors(material: next.material)
                                .predividedBy(first.material),
                            isCancelled: isCancelled
                        )
                    } else {
                        sum = sum.minkowskiSum(
                            with: mesh(for: next).materialToVertexColors(material: next.material),
                            isCancelled: isCancelled
                        )
                    }
                }
                return sum
            }
            let sum: Mesh
            if let union = distributableMinkowskiUnion {
                let components = union.childMeshes(isCancelled).map {
                    $0.transformed(by: union.transform)
                }
                sum = components.isEmpty ? minkowskiSum() : .union(components.map {
                    minkowskiSum(replacing: union, with: $0)
                }, isCancelled: isCancelled)
            } else {
                sum = minkowskiSum()
            }
            mesh = sum.vertexColorsToMaterial(material: material).replacing(material, with: nil)
        case .union, .lathe, .extrude, .fill:
            let meshes = visibleChildren.compactMap { child -> Mesh? in
                let paths = child.paths(pretransformed: true)
                guard !paths.isEmpty else {
                    return child.flattened(with: material, isCancelled)
                }
                let builderType: GeometryType
                switch type {
                case let .extrude(_, options): builderType = .extrude(paths, options)
                case let .lathe(_, options): builderType = .lathe(paths, options)
                case .fill: builderType = .fill(paths)
                case .group, .cone, .cylinder, .icosphere, .sphere, .cube,
                     .circle, .square, .text, .path, .mesh, .camera, .light,
                     .loft, .hull, .minkowski, .union, .difference,
                     .intersection, .xor, .stencil:
                    return child.flattened(with: material, isCancelled)
                }
                let builder = Geometry(
                    type: builderType,
                    name: nil,
                    transform: .identity,
                    material: material,
                    smoothing: smoothing,
                    children: [],
                    sourceLocation: _sourceLocation
                )
                if builder.children.isEmpty {
                    builder.cache = cache
                } else {
                    builder.children.forEach { $0.cache = cache }
                }
                guard builder.build(isCancelled) else { return nil }
                return builder.flattened(with: material, isCancelled)
            }
            mesh = .union(meshes, isCancelled: isCancelled)
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
        withoutHiddenOrUnfocused: Bool
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
        let isRemovingUnfocusedChildren = withoutHiddenOrUnfocused && childIsFocused && !isFocused
        let isRemovingHiddenGeometry = withoutHiddenOrUnfocused && isHidden
        if isRemovingUnfocusedChildren || isRemovingHiddenGeometry {
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
                if withoutHiddenOrUnfocused, $0.isHidden {
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
                    withoutHiddenOrUnfocused: withoutHiddenOrUnfocused
                )
            },
            sourceLocation: _sourceLocation ?? sourceLocation,
            debug: withoutDebug ? false : debug,
            isFocused: isFocused,
            isHidden: isHidden
        )
        copy.mesh = isRemovingUnfocusedChildren || isRemovingHiddenGeometry ? nil : mesh
        return copy
    }

    /// Determine heuristically whether it's worth detessellating the mesh output
    var shouldDetessellate: Bool {
        switch type {
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
        var vertexColorMaterial = material
        vertexColorMaterial.albedo = .color(.white)
        guard materials.allSatisfy({ value in
            guard let value else { return true }
            guard let value = value as? ShapeScript.Material else { return false }
            return value == material || value == vertexColorMaterial
        }) else {
            return self
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
        case .camera, .light, .circle, .square, .text, .path:
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
        case .camera, .light, .circle, .square, .text, .path, .group:
            break
        case .union where parent?.distributableMinkowskiUnion === self && parent?.mesh != nil:
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
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square, .text,
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
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square, .text,
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
        guard !isHidden else {
            return []
        }
        switch type {
        case .group:
            return visibleChildren.reduce(into: []) { $0 += $1.polygons(isCancelled) }
        default:
            return mesh(isCancelled)?.polygons ?? []
        }
    }

    /// Builds the mesh (if needed) and returns the triangle count
    /// Built meshes will be stored in the cache. Already-cached meshes will be re-used if available
    func triangles(_ isCancelled: @escaping CancellationHandler) -> [Polygon] {
        polygons(isCancelled).flatMap { $0.triangulate(isCancelled: isCancelled) }
    }

    /// Returns if the geometry is watertight
    /// Builds and caches the mesh (if required). Already-cached meshes will be re-used if available
    func isWatertight(_ isCancelled: @escaping CancellationHandler) -> Bool {
        guard !isHidden else {
            return true
        }
        switch type {
        case .cone, .cylinder, .icosphere, .sphere, .cube:
            return true
        case .group:
            return visibleChildren.allSatisfy { $0.isWatertight(isCancelled) }
        default:
            return mesh(isCancelled)?.isWatertight ?? true
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
        case .lathe([], _) where visibleChildren.contains(where: { $0.path != nil }),
             .extrude([], _) where visibleChildren.contains(where: { $0.path != nil }):
            return mesh(isCancelled)?.transformed(by: transform).bounds ?? .empty
        case .group, .union, .lathe([], _), .extrude([], _), .fill([]):
            return Bounds(visibleChildren.map {
                $0.exactBounds(with: $0.transform * transform, isCancelled)
            })
        case .cone, .cylinder, .icosphere, .sphere, .cube, .circle, .square,
             .text, .path, .extrude, .lathe:
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
            return visibleChildren.reduce(bounds) {
                $0.union($1.exactBounds(with: $1.transform * transform, isCancelled))
            }
        case .minkowski:
            return visibleChildren.reduce(.empty) {
                $0.minkowskiSum(with: $1.exactBounds(with: $1.transform * transform, isCancelled))
            }
        case .xor, .difference, .intersection:
            if transform.rotation == .identity {
                return mesh(isCancelled)?.bounds.transformed(by: transform) ?? .empty
            }
            return mesh(isCancelled)?.transformed(by: transform).bounds ?? .empty
        case .stencil:
            return visibleChildren.first.map {
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
}
