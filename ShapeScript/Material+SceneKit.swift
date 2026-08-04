//
//  Material+SceneKit.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/11/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(SceneKit)

import SceneKit

public extension MaterialProperty {
    init?(_ scnMaterialProperty: SCNMaterialProperty) {
        switch scnMaterialProperty.contents {
        case let number as NSNumber:
            self = .color(Color(white: number.doubleValue, alpha: number.doubleValue))
        case let color as OSColor:
            self = .color(Color(color))
        case let image as OSImage:
            guard let texture = Texture(image, intensity: scnMaterialProperty.intensity) else {
                return nil
            }
            self = .texture(texture)
        case let data as Data:
            self = .texture(.data(data, intensity: scnMaterialProperty.intensity))
        case let url as URL:
            guard let texture = try? Texture.file(
                name: url.lastPathComponent,
                url: url,
                intensity: scnMaterialProperty.intensity
            ) else {
                return nil
            }
            self = .texture(texture)
        default:
            return nil
        }
    }

    func configureProperty(_ property: SCNMaterialProperty) {
        switch self {
        case let .color(color):
            property.contents = OSColor(color)
            property.intensity = 1
        case let .texture(texture):
            property.magnificationFilter = .nearest
            property.minificationFilter = .linear
            if texture.intensity > 0 {
                if let url = texture.url {
                    property.contents = url
                    property.intensity = texture.intensity
                } else {
                    property.contents = texture.data
                    property.intensity = texture.intensity
                }
            } else {
                property.contents = OSColor.clear
            }
        }
    }

    func configureOpacityProperty(_ property: SCNMaterialProperty) {
        switch self {
        case .color:
            configureProperty(property)
        case let .texture(texture):
            property.magnificationFilter = .nearest
            property.minificationFilter = .linear
            if texture.intensity > 0 {
                if let data = texture.opacityMaskData {
                    property.contents = data
                } else if let url = texture.url {
                    property.contents = url
                } else {
                    property.contents = texture.data
                }
                property.intensity = texture.intensity
            } else {
                property.contents = OSColor.clear
            }
        }
    }
}

public extension SCNMaterial {
    convenience init(_ m: Material, isOpaque: Bool, writesToDepthBuffer: Bool = true) {
        self.init()
        m.normals.flatMap(MaterialProperty.init)?.configureProperty(normal)
        m.opacity?.configureOpacityProperty(transparent)
        if case let .color(albedo)? = m.albedo, albedo.alpha < 1 {
            // Workaround for SceneKit blending bugs with translucent colors
            diffuse.contents = OSColor(albedo.withAlphaComponent(1))
            switch m.opacity {
            case let .texture(texture):
                let intensity = texture.intensity * albedo.alpha
                if intensity > 0 {
                    transparent.intensity = intensity
                } else {
                    transparent.contents = 0
                }
            case let .color(color):
                transparent.contents = color.alpha * albedo.alpha
            case nil:
                transparent.contents = albedo.alpha
            }
        } else {
            m.albedo?.configureProperty(diffuse)
        }

        isDoubleSided = !isOpaque
        transparencyMode = .dualLayer
        self.writesToDepthBuffer = writesToDepthBuffer

        m.glow?.configureProperty(emission)
        if m.roughness != nil || m.metallicity != nil {
            lightingModel = .physicallyBased
            m.metallicity?.configureProperty(metalness)
            m.roughness?.configureProperty(roughness)
        } else {
            lightingModel = .blinn
        }
    }
}

private extension MaterialProperty {
    func ifNot(_ color: Color) -> MaterialProperty? {
        self == .color(color) ? nil : self
    }
}

public extension Material {
    init?(_ scnMaterial: SCNMaterial) {
        opacity = (MaterialProperty(scnMaterial.transparent) ?? .color(.init(
            white: scnMaterial.transparency,
            alpha: scnMaterial.transparency
        )))?.ifNot(.white)
        albedo = MaterialProperty(scnMaterial.diffuse)?.ifNot(.white)
        normals = MaterialProperty(scnMaterial.normal)?.texture
        glow = MaterialProperty(scnMaterial.emission)?.ifNot(.black)
        switch scnMaterial.lightingModel {
        case .physicallyBased:
            metallicity = MaterialProperty(scnMaterial.metalness)
            roughness = MaterialProperty(scnMaterial.roughness)
        default:
            metallicity = nil
            roughness = nil
        }
    }
}

extension Texture {
    init?(_ image: OSImage, intensity: Double = 1) {
        #if canImport(UIKit)
        guard let data = image.pngData() else {
            return nil
        }
        #else
        guard let cgImage = image
            .cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])
        else {
            return nil
        }
        #endif
        self = .data(data, intensity: intensity)
    }
}

extension OSImage {
    convenience init?(_ texture: Texture) {
        self.init(data: texture.data)
    }
}

#endif
