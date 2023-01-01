//
//  Scene.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public final class Scene {
    public let background: MaterialProperty
    public let children: [Geometry]
    public let cameras: [Geometry]
    public let lights: [Geometry]
    public let exports: [Export]
    public let cache: GeometryCache?

    public init(
        background: MaterialProperty,
        children: [Geometry],
        exports: [Export],
        cache: GeometryCache?
    ) {
        self.background = background
        self.children = children
        self.cameras = children.flatMap { $0._cameras }
        self.lights = children.flatMap { $0._lights }
        self.exports = exports
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
    static let empty = Scene(background: .color(.clear), children: [], exports: [], cache: nil)

    /// Returns the approximate (overestimated) bounds of the scene geometry.
    var bounds: Bounds {
        children.reduce(into: .empty) {
            $0.formUnion($1.bounds.transformed(by: $1.transform))
        }
    }

    func build(_ callback: @escaping () -> Bool) -> Bool {
        for geometry in children where !geometry.build(callback) {
            return false
        }
        return true
    }
}

private extension Geometry {
    var _cameras: [Geometry] {
        guard case .camera = type else {
            return children.flatMap { $0._cameras }
        }
        return [self]
    }

    var _lights: [Geometry] {
        guard case .light = type else {
            return children.flatMap { $0._lights }
        }
        return [self]
    }
}
