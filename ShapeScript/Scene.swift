//
//  Scene.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public final class Scene: Sendable {
    public let background: MaterialProperty
    public let geometry: Geometry
    public let cameras: [Geometry]
    public let lights: [Geometry]
    public let cache: GeometryCache?
    public let warnings: [String]
    public let zUp: Bool

    public convenience init(
        background: MaterialProperty,
        children: [Geometry],
        cache: GeometryCache?,
        warnings: [String] = [],
        zUp: Bool = false
    ) {
        self.init(
            background: background,
            geometry: Geometry(
                type: .group,
                name: nil,
                transform: .identity,
                material: .default,
                smoothing: nil,
                children: children,
                sourceLocation: nil
            ),
            cache: cache,
            warnings: warnings,
            zUp: zUp
        )
    }

    private init(
        background: MaterialProperty,
        geometry: Geometry,
        cache: GeometryCache?,
        warnings: [String],
        zUp: Bool
    ) {
        self.background = background
        self.geometry = geometry // The raw scene geometry, including unfocused geometry
        self.cameras = geometry.children.flatMap(\._cameras)
        self.lights = geometry.children.flatMap(\._lights)
        self.cache = cache
        self.warnings = warnings
        self.zUp = zUp
        geometry.cache = cache
    }
}

extension Scene: Equatable {
    public static func == (lhs: Scene, rhs: Scene) -> Bool {
        lhs.background == rhs.background &&
            lhs.children == rhs.children &&
            lhs.cameras == rhs.cameras &&
            lhs.warnings == rhs.warnings &&
            lhs.zUp == rhs.zUp
    }
}

public extension Scene {
    static let empty = Scene(background: .color(.clear), children: [], cache: nil)

    var children: [Geometry] {
        geometry.children
    }

    /// Returns the visible scene geometry, excluding unfocused geometry if any child is focused.
    var visibleGeometry: Geometry {
        geometry.withoutHiddenOrUnfocused()
    }

    /// Returns the approximate bounds of the visible scene geometry.
    var visibleBounds: Bounds {
        let focus = children.contains(where: \.childIsFocused)
        return Bounds(children.map {
            $0.overestimatedBoundsForFocus(focus: focus)
        })
    }

    func with(zUp: Bool) -> Scene {
        self.zUp == zUp ? self : Scene(
            background: background,
            geometry: geometry,
            cache: cache,
            warnings: warnings,
            zUp: zUp
        )
    }

    func build(progress: RenderProgress? = nil) -> Bool {
        defer { flushPendingCacheWrites() }
        return geometry.build(progress: progress)
    }

    func build(_ isCancelled: @escaping CancellationHandler) -> Bool {
        defer { flushPendingCacheWrites() }
        return geometry.build(isCancelled)
    }

    private func flushPendingCacheWrites() {
        Task { [cache] in
            await cache?.flushPendingDiskWrites()
        }
    }
}

private extension Geometry {
    func overestimatedBoundsForFocus(focus: Bool) -> Bounds {
        if isHidden || (focus && !isFocused && !childIsFocused) {
            return .empty
        }
        if !focus || isFocused {
            let children = visibleChildren
            if cachedMesh == nil, children.count != self.children.count {
                return Bounds(children.map {
                    $0.overestimatedBoundsForFocus(focus: focus)
                }).transformed(by: transform)
            }
            return overestimatedBounds
        }
        return Bounds(children.map {
            $0.overestimatedBoundsForFocus(focus: focus)
        }).transformed(by: transform)
    }

    var _cameras: [Geometry] {
        guard case .camera = type else {
            return children.flatMap(\._cameras)
        }
        return [self]
    }

    var _lights: [Geometry] {
        guard case .light = type else {
            return children.flatMap(\._lights)
        }
        return [self]
    }
}
