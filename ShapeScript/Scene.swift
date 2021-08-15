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
    public let cache: GeometryCache?

    public init(
        background: MaterialProperty,
        children: [Geometry],
        cache: GeometryCache?
    ) {
        self.background = background
        self.children = children
        self.cache = cache
        children.forEach { $0.cache = cache }
    }
}

public extension Scene {
    static let empty = Scene(background: .color(.clear), children: [], cache: nil)

    func build(_ callback: @escaping () -> Bool) -> Bool {
        for geometry in children where !geometry.build(callback) {
            return false
        }
        return true
    }
}
