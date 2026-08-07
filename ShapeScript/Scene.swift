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
    public let children: [Geometry]
    public let cameras: [Geometry]
    public let lights: [Geometry]
    public let cache: GeometryCache?

    public init(
        background: MaterialProperty,
        children: [Geometry],
        cache: GeometryCache?
    ) {
        self.background = background
        self.children = children
        self.cameras = children.flatMap(\._cameras)
        self.lights = children.flatMap(\._lights)
        self.cache = cache
        children.forEach { $0.cache = cache }
    }
}

extension Scene: Equatable {
    public static func == (lhs: Scene, rhs: Scene) -> Bool {
        lhs.background == rhs.background &&
            lhs.children == rhs.children &&
            lhs.cameras == rhs.cameras
    }
}

public extension Scene {
    static let empty = Scene(background: .color(.clear), children: [], cache: nil)

    /// Returns the raw scene geometry, including unfocused geometry.
    var geometry: Geometry {
        Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: children,
            sourceLocation: nil
        )
    }

    /// Returns the visible scene geometry, excluding unfocused geometry if any child is focused.
    var visibleGeometry: Geometry {
        geometry.withoutUnfocusedGeometry()
    }

    /// Returns the approximate bounds of the visible scene geometry.
    var visibleBounds: Bounds {
        let focus = children.contains(where: \.childIsFocused)
        return Bounds(children.map {
            $0.overestimatedBoundsForFocus(focus: focus)
        })
    }

    /// Returns the approximate (overestimated) bounds of the scene geometry.
    @available(*, deprecated, renamed: "visibleBounds")
    var overestimatedBounds: Bounds {
        visibleBounds
    }

    func build(_ isCancelled: @escaping CancellationHandler) -> Bool {
        for geometry in children where !geometry.build(isCancelled) {
            return false
        }
        return true
    }
}

private extension Geometry {
    func overestimatedBoundsForFocus(focus: Bool) -> Bounds {
        if focus, !isFocused, !childIsFocused {
            return .empty
        }
        if !focus || isFocused {
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
