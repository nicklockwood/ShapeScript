//
//  Material+SceneKit.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/11/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(SceneKit)

import ImageIO
import SceneKit
import SceneKit.ModelIO

public extension MaterialProperty {
    init?(_ scnMaterialProperty: SCNMaterialProperty) {
        self.init(scnMaterialProperty, linearColor: true)
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
        self.writesToDepthBuffer = isOpaque || writesToDepthBuffer

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
    init?(_ mdlMaterial: MDLMaterial) {
        let material = SCNMaterial(mdlMaterial: mdlMaterial)
        // Model I/O scalar opacity textures use red rather than alpha.
        if let texture = mdlMaterial.property(with: .opacity)?.textureSamplerValue?.texture,
           texture.channelCount == 1
        {
            material.transparent.contents = texture
            material.transparent.textureComponents = .red
        }
        self.init(material)
    }

    init?(_ scnMaterial: SCNMaterial) {
        opacity = scnMaterial.importedOpacity?.ifNot(.white)
        albedo = MaterialProperty(scnMaterial.diffuse)?.ifNot(.white)
        normals = MaterialProperty(scnMaterial.normal)?.texture
        glow = MaterialProperty(scnMaterial.emission)?.ifNot(.black)
        switch scnMaterial.lightingModel {
        case .physicallyBased:
            metallicity = MaterialProperty(scnMaterial.metalness, linearColor: false)
            roughness = MaterialProperty(scnMaterial.roughness, linearColor: false)
        default:
            metallicity = nil
            roughness = nil
        }
    }
}

extension MaterialProperty {
    init?(_ scnMaterialProperty: SCNMaterialProperty, linearColor: Bool) {
        func scaled(_ color: Color) -> Color {
            let intensity = scnMaterialProperty.intensity
            guard intensity != 1 else { return color }
            var result = linearColor ? color.toLinear() : color
            result.red *= intensity
            result.green *= intensity
            result.blue *= intensity
            return linearColor ? result.toSRGB() : result
        }
        let contents: Any? = (scnMaterialProperty.contents as? MDLTexture).map {
            $0.imageFromTexture()?.takeUnretainedValue()
        } ?? scnMaterialProperty.contents
        switch contents {
        case let number as NSNumber:
            self = .color(scaled(Color(white: number.doubleValue, alpha: number.doubleValue)))
        case let color as OSColor:
            self = .color(scaled(Color(color)))
        case let color as CGColor where CFGetTypeID(color) == CGColor.typeID:
            self = .color(scaled(Color(color)))
        case let image as CGImage where CFGetTypeID(image) == CGImage.typeID:
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            self = .texture(.data(data as Data, intensity: scnMaterialProperty.intensity))
        case let image as OSImage:
            guard let texture = Texture(image, intensity: scnMaterialProperty.intensity) else {
                return nil
            }
            self = .texture(texture)
        case let data as Data:
            self = .texture(.data(data, intensity: scnMaterialProperty.intensity))
        case let path as String:
            let url = URL(string: path).flatMap { $0.isFileURL ? $0 : nil } ?? URL(fileURLWithPath: path)
            guard let texture = try? Texture.file(
                name: url.displayName, url: url, intensity: scnMaterialProperty.intensity
            ) else { return nil }
            self = .texture(texture)
        case let url as URL:
            guard let texture = try? Texture.file(
                name: url.displayName,
                url: url,
                intensity: scnMaterialProperty.intensity
            ) else {
                return nil
            }
            self = .texture(texture)
        default:
            return nil
        }
        if case let .texture(texture) = self {
            guard let selected = texture.selectingComponents(scnMaterialProperty.textureComponents) else {
                return nil
            }
            self = .texture(selected)
        }
    }
}

private extension SCNMaterial {
    var importedOpacity: MaterialProperty? {
        // Decode the source channel explicitly. ShapeScript's grayscale fallback
        // must not reinterpret an opaque alpha mask as a luminance mask.
        let property = SCNMaterialProperty(contents: transparent.contents ?? OSColor.black)
        property.textureComponents = transparent.textureComponents
        let intensity = transparent.intensity
        let scalar = Double(transparency)
        let rgbZero = transparencyMode == .rgbZero
        func opacity(_ color: Color) -> Double {
            let value = rgbZero ? 1 - color.luminance * intensity * scalar : color.alpha * intensity * scalar
            return max(0, min(1, value))
        }
        switch MaterialProperty(property) {
        case let .color(color):
            let alpha = opacity(color)
            return .color(Color(white: alpha, alpha: alpha))
        case let .texture(texture):
            guard let source = CGImageSourceCreateWithData(texture.data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            guard let context = CGContext(
                data: &bytes, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Double(bytes[i + 3]) / 255
                let divisor = max(Double(bytes[i + 3]), 1)
                let color = Color(
                    red: Double(bytes[i]) / divisor,
                    green: Double(bytes[i + 1]) / divisor,
                    blue: Double(bytes[i + 2]) / divisor, alpha: alpha
                )
                let value = UInt8(
                    (max(0, min(1, rgbZero ? 1 - color.luminance * intensity * scalar : alpha)) * 255).rounded()
                )
                // White with premultiplied alpha, including white for opaque pixels.
                for channel in 0 ..< 4 {
                    bytes[i + channel] = value
                }
            }
            guard let output = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, output, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return .texture(.data(data as Data, intensity: rgbZero ? 1 : scalar * intensity))
        case nil:
            return .color(Color(white: scalar, alpha: scalar))
        }
    }
}

private extension Texture {
    /// Bake SceneKit's channel selection because ShapeScript textures use RGBA.
    func selectingComponents(_ components: SCNColorMask) -> Texture? {
        guard components != .all else { return self }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let channels: [SCNColorMask] = [.red, .green, .blue, .alpha]
        let selected = channels.indices.filter { components.contains(channels[$0]) }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[i + 3]) / 255
            let divisor = max(Double(bytes[i + 3]), 1)
            var values = (0 ..< 3).map { Double(bytes[i + $0]) / divisor } + [alpha]
            if selected.count == 1, let channel = selected.first {
                values = Array(repeating: values[channel], count: 4)
            } else {
                for channel in 0 ..< 3 where !components.contains(channels[channel]) {
                    values[channel] = 0
                }
                if !components.contains(.alpha) { values[3] = 1 }
            }
            for channel in 0 ..< 4 {
                let value = values[channel] * (channel == 3 ? 1 : values[3])
                bytes[i + channel] = UInt8((max(0, min(1, value)) * 255).rounded())
            }
        }
        guard let output = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return .data(data as Data, intensity: intensity)
    }
}

extension Texture {
    init?(_ image: OSImage, intensity: Double = 1) {
        #if canImport(UIKit)
        guard let data = image.pngData() else {
            return nil
        }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
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

extension SCNNode {
    /// SceneKit passes Collada vertex RGB through unchanged; Euclid’s SceneKit bridge expects linear RGB.
    func prepareImportedVertexColors(fileExtension: String) {
        guard fileExtension.lowercased() == "dae" else { return }
        if let geometry {
            let sources = geometry.sources.map { source -> SCNGeometrySource in
                guard source.semantic == .color, source.usesFloatComponents,
                      source.componentsPerVector >= 3, [4, 8].contains(source.bytesPerComponent)
                else { return source }
                var values = [Float]()
                for index in 0 ..< source.vectorCount {
                    let components = (0 ..< source.componentsPerVector).map { channel -> Double in
                        let offset = source.dataOffset + index * source.dataStride + channel * source.bytesPerComponent
                        return source.data.withUnsafeBytes { bytes in
                            source.bytesPerComponent == 8
                                ? bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
                                : Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                        }
                    }
                    let color = Color(
                        red: components[0],
                        green: components[1],
                        blue: components[2],
                        alpha: components.count > 3 ? components[3] : 1
                    ).toLinear()
                    values += [Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha)]
                }
                return SCNGeometrySource(
                    data: values.withUnsafeBytes { Data($0) }, semantic: .color,
                    vectorCount: source.vectorCount, usesFloatComponents: true,
                    componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0, dataStride: 4 * MemoryLayout<Float>.size
                )
            }
            let copy = SCNGeometry(sources: sources, elements: geometry.elements)
            copy.materials = geometry.materials
            copy.name = geometry.name
            self.geometry = copy
        }
        childNodes.forEach { $0.prepareImportedVertexColors(fileExtension: fileExtension) }
    }

    /// USD's default is linear Rec.709. SceneKit can attach a linear Display P3 profile
    /// without converting the stored components. Correct that tag only for USD assets.
    func prepareImportedUSDColors(fileExtension: String) {
        guard ["usd", "usda", "usdc", "usdz"].contains(fileExtension.lowercased()),
              let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB)
        else { return }
        let incorrectSpaces = [CGColorSpace.linearDisplayP3, CGColorSpace.extendedLinearDisplayP3]
            .compactMap { CGColorSpace(name: $0)?.name }
        for material in geometry?.materials ?? [] {
            for property in [
                material.diffuse,
                material.emission,
                material.specular,
                material.ambient,
                material.reflective,
                material.multiply,
            ] {
                let color: CGColor? = switch property.contents {
                case let value as OSColor: value.cgColor
                case let value as CGColor where CFGetTypeID(value) == CGColor.typeID: value
                default: nil
                }
                guard let color, let space = color.colorSpace?.name,
                      incorrectSpaces.contains(space), let components = color.components,
                      let corrected = CGColor(colorSpace: linearSRGB, components: components)
                else { continue }
                property.contents = corrected
            }
        }
        childNodes.forEach { $0.prepareImportedUSDColors(fileExtension: fileExtension) }
    }
}

#endif
