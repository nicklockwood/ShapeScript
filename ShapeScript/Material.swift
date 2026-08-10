//
//  Material.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 16/01/2019.
//  Copyright © 2019 Nick Lockwood. All rights reserved.
//

import Euclid

public typealias Color = Euclid.Color

public enum MaterialProperty: Hashable, Sendable {
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

    var color: Color? {
        switch self {
        case let .color(color):
            color
        case .texture:
            nil
        }
    }

    var texture: Texture? {
        switch self {
        case let .texture(texture):
            texture
        case .color:
            nil
        }
    }
}

extension MaterialProperty {
    var averageOpacity: Double {
        switch self {
        case let .color(color):
            color.alpha
        case let .texture(texture):
            texture.averageOpacity
        }
    }

    var averageLuminance: Double {
        switch self {
        case let .color(color):
            color.luminance
        case let .texture(texture):
            texture.averageLuminance
        }
    }
}

public struct Material: Hashable, Sendable {
    public var opacity: Optional<MaterialProperty>
    public var albedo: Optional<MaterialProperty>
    public var normals: Optional<Texture>
    public var metallicity: Optional<MaterialProperty>
    public var roughness: Optional<MaterialProperty>
    public var glow: Optional<MaterialProperty>
}

public extension Material {
    static let `default`: Material = .init()

    init(color: Color? = nil) {
        self.init(
            opacity: nil,
            albedo: color.map { .color($0) },
            normals: nil,
            metallicity: nil,
            roughness: nil,
            glow: nil
        )
    }

    var isOpaque: Bool {
        averageOpacity > 0.999
    }

    var isVisible: Bool {
        averageOpacity > 0.001
    }

    var color: Color? {
        albedo?.color
    }

    var texture: Texture? {
        albedo?.texture
    }
}

extension Material {
    var averageOpacity: Double {
        opacityPropertyAverageOpacity * (albedo?.averageOpacity ?? 1)
    }

    /// Opacity properties use alpha when present; opaque properties fall back
    /// to luminance so grayscale opacity masks work without alpha channels.
    var opacityPropertyAverageOpacity: Double {
        guard let opacity else {
            return 1
        }
        let alphaOpacity = opacity.averageOpacity
        return alphaOpacity < 1 ? alphaOpacity : opacity.averageLuminance
    }
}
