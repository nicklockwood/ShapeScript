//
//  Material.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 16/01/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import Foundation

public struct Color: Hashable {
    public let r, g, b, a: Double

    public static var clear = Color(unchecked: [0, 0, 0, 0])
    public static var white = Color(unchecked: [1])

    public init(unchecked components: [Double]) {
        var a = 1.0
        switch components.count {
        case 4:
            a = components[3]
            fallthrough
        case 3:
            r = components[0]
            g = components[1]
            b = components[2]
        case 2:
            a = components[1]
            fallthrough
        case 1:
            r = components[0]
            g = r
            b = r
        default:
            preconditionFailure()
        }
        self.a = a
    }
}

public enum Texture: Hashable {
    case file(name: String, url: URL)
    case data(Data)
}

public enum MaterialProperty: Hashable {
    case color(Color)
    case texture(Texture)

    init?(_ value: Any) {
        switch value {
        case let color as Color:
            self = .color(color)
        case let texture as Texture:
            self = .texture(texture)
        default:
            return nil
        }
    }
}

public struct Material: Hashable {
    public var opacity = 1.0
    public var texture: Texture?
    public var color: Color? = .white {
        // Color and texture are mutually exclusive
        didSet { texture = (color != nil) ? nil : texture }
    }

    public var isOpaque: Bool {
        opacity > 0.999 && (color?.a ?? 1) > 0.999
    }

    public static let `default` = Material()

    public init() {}
}
