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

    init(background: MaterialProperty, children: [Geometry]) {
        self.background = background
        self.children = children
    }
}

public extension Scene {
    static let empty = Scene(background: .color(.clear), children: [])

    func deepCopy() -> Scene {
        Scene(background: background, children: children.map { $0.deepCopy() })
    }

    func build(_ callback: @escaping () -> Bool) -> Bool {
        for geometry in children where !geometry.build(callback) {
            return false
        }
        return true
    }
}
