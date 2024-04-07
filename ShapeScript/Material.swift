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
    case file(name: String, url: URL, intensity: Double)
    case data(Data, intensity: Double)
}

public extension Texture {
    var intensity: Double {
        switch self {
        case let .file(name: _, url: _, intensity: intensity),
             let .data(_, intensity: intensity):
            return intensity
        }
    }

    func withIntensity(_ intensity: Double) -> Self {
        switch self {
        case let .file(name: name, url: url, intensity: _):
            return .file(name: name, url: url, intensity: intensity)
        case let .data(data, intensity: _):
            return .data(data, intensity: intensity)
        }
    }
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
        (opacity?.opacity ?? 1) * (albedo?.opacity ?? 1) > 0.999
    }

    var isVisible: Bool {
        (opacity?.opacity ?? 1) * (albedo?.opacity ?? 1) > 0.001
    }

    var color: Color? {
        albedo?.color
    }

    var texture: Texture? {
        albedo?.texture
    }
}
