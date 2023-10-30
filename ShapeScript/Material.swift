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
}

public extension MaterialProperty {
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

    var opacity: Double {
        averageColor.a
    }

    var color: Color? {
        switch self {
        case let .color(color):
            return color
        case .texture:
            return nil
        }
    }

    var texture: Texture? {
        switch self {
        case let .texture(texture):
            return texture
        case .color:
            return nil
        }
    }
}

public struct Material: Hashable {
    public var opacity: Optional<MaterialProperty>
    public var diffuse: Optional<MaterialProperty>
    public var metallicity: Optional<MaterialProperty>
    public var roughness: Optional<MaterialProperty>
    public var glow: Optional<MaterialProperty>
}

public extension Material {
    static let `default`: Material = .init()

    init(color: Color? = nil) {
        self.init(
            opacity: nil,
            diffuse: color.map { .color($0) },
            metallicity: nil,
            roughness: nil,
            glow: nil
        )
    }

    var isOpaque: Bool {
        (opacity?.opacity ?? 1) > 0.999 && (diffuse?.opacity ?? 1) > 0.999
    }

    var isUniform: Bool {
        opacity?.texture == nil
            && diffuse?.texture == nil
            && metallicity?.texture == nil
            && roughness?.texture == nil
            && glow?.texture == nil
    }

    var color: Color? {
        diffuse?.color
    }

    var texture: Texture? {
        diffuse?.texture
    }
}
