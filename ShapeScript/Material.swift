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
    public var opacity: Double = 1
    public var diffuse: MaterialProperty?
}

public extension Material {
    static let `default`: Material = .init()

    init(color: Color? = nil) {
        self.diffuse = color.map { .color($0) }
    }

    var isOpaque: Bool {
        opacity > 0.999 && (color?.a ?? 1) > 0.999
    }

    var color: Color? {
        switch diffuse {
        case let .color(color)?:
            return color
        case .texture, nil:
            return nil
        }
    }

    var texture: Texture? {
        switch diffuse {
        case let .texture(texture)?:
            return texture
        case .color, nil:
            return nil
        }
    }
}
