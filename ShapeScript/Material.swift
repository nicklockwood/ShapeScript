//
//  Material.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 16/01/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

public typealias Color = Euclid.Color

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
    public var color: Color? {
        // Color and texture are mutually exclusive
        didSet { texture = (color != nil) ? nil : texture }
    }

    public var isOpaque: Bool {
        opacity > 0.999 && (color?.a ?? 1) > 0.999
    }

    public static let `default` = Material()

    public init(color: Color? = .white) {
        self.color = color
    }
}
