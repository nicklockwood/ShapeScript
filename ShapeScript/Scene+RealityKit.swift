//
//  Scene+RealityKit.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if canImport(RealityKit)

import CoreImage
import Euclid
import Foundation
import ImageIO
import Metal
import RealityKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
public extension Entity {
    /// Creates a RealityKit entity for the visible geometry in a ShapeScript scene.
    ///
    /// The scene must already have been built. This initializer converts the
    /// visible ShapeScript geometry to a single Euclid mesh and then relies on
    /// Euclid's RealityKit bridge to create the rendered model entity.
    convenience init(_ scene: Scene, options: Scene.OutputOptions = .default) throws {
        self.init()
        let sourceMesh = scene.visibleGeometry.realityKitMesh(with: options)
        let mesh = sourceMesh
        guard mesh != .empty else {
            return
        }
        try addChild(ModelEntity(triangles: mesh, materialLookup: { realityKitMaterial($0) }))
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
public struct RealityKitEntityReference: @unchecked Sendable {
    public let entity: Entity
    public let geometry: Geometry
    public let collisionMesh: MeshResource?
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
public struct RealityKitEntityDescriptor: @unchecked Sendable {
    let geometry: Geometry
    let mesh: Mesh
    let transform: Euclid.Transform
    let debug: Bool
    let options: Scene.OutputOptions

    /// Whether the rendered mesh contains materials that need environment lighting.
    public var usesPhysicallyBasedMaterials: Bool {
        guard geometry.previewPath == nil else { return false }
        return mesh.materials.contains { value in
            guard let material = value as? Material else { return false }
            return material.roughness != nil || material.metallicity != nil
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
public extension Scene {
    /// Creates descriptors for the visible geometry in a ShapeScript scene.
    ///
    /// This performs ShapeScript/Euclid mesh preparation without creating any
    /// RealityKit resources, so callers can run it on their loading thread
    /// before handing the descriptors to RealityKit on the main actor.
    func realityKitEntityDescriptors(
        with options: OutputOptions = .default
    ) -> [RealityKitEntityDescriptor] {
        let focus = children.contains(where: \.childIsFocused)
        return children.realityKitEntityDescriptors(
            with: options,
            debug: false,
            focus: focus
        )
    }

    /// Creates RealityKit entities for the visible geometry in a ShapeScript scene.
    ///
    /// Each returned entity is paired with the `Geometry` it represents so
    /// callers can map RealityKit hit-test results back to ShapeScript shapes.
    /// Uniform vertex colors are applied to each material. Vertex-color gradients
    /// require the asynchronous overload on platforms that support LowLevelMesh.
    @MainActor func realityKitEntityReferences(
        with options: OutputOptions = .default
    ) throws -> [RealityKitEntityReference] {
        try realityKitEntityReferences(from: realityKitEntityDescriptors(with: options))
    }

    /// Asynchronously creates RealityKit entities for the visible geometry in a
    /// ShapeScript scene.
    ///
    /// Each returned entity is paired with the `Geometry` it represents so
    /// callers can map RealityKit hit-test results back to ShapeScript shapes.
    func realityKitEntityReferences(
        with options: OutputOptions = .default
    ) async throws -> [RealityKitEntityReference] {
        try await realityKitEntityReferences(from: realityKitEntityDescriptors(with: options))
    }

    /// Creates RealityKit entities from descriptors produced by
    /// `realityKitEntityDescriptors(with:)`.
    ///
    /// RealityKit resource generation and material creation are main-actor
    /// operations, but descriptor preparation can be done before calling this.
    @MainActor func realityKitEntityReferences(
        from descriptors: [RealityKitEntityDescriptor]
    ) throws -> [RealityKitEntityReference] {
        try descriptors.map { try $0.realityKitEntityReference() }
    }

    /// Asynchronously creates RealityKit entities from descriptors produced by
    /// `realityKitEntityDescriptors(with:)`.
    ///
    /// This uses RealityKit's async mesh resource generation while preserving
    /// ShapeScript's per-geometry resource cache and collision mesh references.
    func realityKitEntityReferences(
        from descriptors: [RealityKitEntityDescriptor]
    ) async throws -> [RealityKitEntityReference] {
        var references = [RealityKitEntityReference]()
        references.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            try await references.append(descriptor.realityKitEntityReference())
        }
        return references
    }
}

#if compiler(>=6)

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
@MainActor public extension Scene {
    /// Creates scene lights, approximating ambient lights with a uniform environment.
    /// Add the result beside the model entities and use it as their image-based light receiver's source.
    /// An explicit scene light suppresses default environment lighting even without ambient lights.
    /// RealityKit's light units and shadow controls differ from SceneKit's, so appearance can vary.
    func realityKitLightingEntity() async throws -> Entity {
        try Task.checkCancellation()
        let entity = Entity()
        var radiance = SIMD3<Double>(repeating: 0)
        var hasLights = false
        for geometry in lights {
            var ancestor: Geometry? = geometry
            var hidden = false
            while let current = ancestor {
                hidden = hidden || current.isHidden
                ancestor = current.parent
            }
            guard !hidden, let light = geometry.light else { continue }
            try Task.checkCancellation()
            hasLights = true
            if light.isAmbient {
                let color = light.color.toLinear()
                radiance += SIMD3(color.red, color.green, color.blue) * max(0, color.alpha)
                continue
            }
            let child = Entity()
            child.name = geometry.name ?? ""
            child.transform = RealityKit.Transform(geometry.worldTransform)
            let color = OSColor(light.color.withAlphaComponent(1))
            let intensity = Float(max(0, light.color.alpha) * 1000)
            switch (light.hasPosition, light.hasOrientation) {
            case (false, true):
                child.components.set(DirectionalLightComponent(color: color, intensity: intensity))
                if light.shadowOpacity > 0 {
                    child.components.set(DirectionalLightComponent.Shadow())
                }
            case (true, false):
                child.components.set(PointLightComponent(
                    color: color, intensity: intensity, attenuationRadius: 10000
                ))
            case (true, true):
                let outerAngle = Float(max(0, min(179, light.spread.degrees)))
                child.components.set(SpotLightComponent(
                    color: color, intensity: intensity,
                    innerAngleInDegrees: outerAngle * Float(1 - max(0, min(1, light.penumbra))),
                    outerAngleInDegrees: outerAngle, attenuationRadius: 10000
                ))
                if light.shadowOpacity > 0 {
                    child.components.set(SpotLightComponent.Shadow())
                }
            case (false, false):
                break
            }
            entity.addChild(child)
        }
        guard hasLights else { return entity }
        let maximum = max(0, radiance.max())
        guard maximum > 0 else {
            entity.components.set(ImageBasedLightComponent(source: .none))
            return entity
        }
        let color = radiance / maximum
        var pixels = [Float]()
        pixels.reserveCapacity(32 * 16 * 4)
        for _ in 0 ..< 32 * 16 {
            pixels += [Float(color.x), Float(color.y), Float(color.z), 1]
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let image = CGImage(
                  width: 32, height: 16, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: 32 * 16,
                  space: space, bitmapInfo: [
                      .floatComponents, .byteOrder32Little,
                      CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  ],
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { throw RuntimeErrorType.assertionFailure("Unable to create ambient lighting image") }
        let environment = try await EnvironmentResource(equirectangular: image)
        try Task.checkCancellation()
        entity.components.set(ImageBasedLightComponent(
            source: .single(environment), intensityExponent: Float(log2(maximum))
        ))
        return entity
    }
}

#endif

private extension Geometry {
    func realityKitMesh(with options: Scene.OutputOptions) -> Mesh {
        let mesh = flattened()
        guard options.wireframe else {
            return mesh
        }
        guard mesh != .empty else {
            return .empty
        }
        let width = options.wireframeLineWidth > 0 ?
            options.wireframeLineWidth : options.lineWidth / 2
        return .stroke(
            mesh.uniqueEdges,
            width: width,
            detail: 3,
            material: Material(color: options.lineColor)
        )
    }

    @available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
    func realityKitEntityDescriptors(
        with options: Scene.OutputOptions,
        debug: Bool
    ) -> [RealityKitEntityDescriptor] {
        guard !isHidden else { return [] }
        let debug = debug || self.debug
        let focus = childIsFocused
        var descriptors = renderedChildren(focus: focus).realityKitEntityDescriptors(
            with: options,
            debug: focus ? false : rendersChildrenAsDebugOverlay,
            focus: focus && !isFocused
        )
        if focus, !isFocused {
            return descriptors
        }
        guard let sourceMesh = directRealityKitMesh(with: options, debug: debug), sourceMesh != .empty else {
            return descriptors
        }
        let mesh = sourceMesh
        descriptors.append(RealityKitEntityDescriptor(
            geometry: self,
            mesh: mesh,
            transform: worldTransform,
            debug: debug,
            options: options
        ))
        return descriptors
    }

    func directRealityKitMesh(
        with options: Scene.OutputOptions,
        debug: Bool
    ) -> Mesh? {
        if let light {
            guard debug, let material = options.debugMaterial, !options.wireframe else {
                return nil
            }
            switch (light.hasPosition, light.hasOrientation) {
            case (false, _):
                return nil
            case (true, false):
                return Mesh.sphere(radius: 0.1)
                    .withMaterial(material)
            case (true, true):
                let adjacent = 10000.0
                let opposite = tan(min(light.spread, .pi * 0.999) / 2) * adjacent
                return Mesh.lathe(Path([
                    .point(0, 0, 0),
                    .point(0, -opposite, adjacent),
                    .point(0, 0, adjacent),
                ]), slices: 64)
                    .rotated(by: .pitch(.halfPi))
                    .withMaterial(material)
            }
        } else if let path = previewPath {
            if options.wireframe {
                return .stroke(
                    path.withColor(nil),
                    width: options.lineWidth,
                    detail: 5,
                    material: Material(color: options.lineColor)
                )
            }
            let renderedPath = debug ? path.withColor(nil) : path
            var material = (debug ? options.debugMaterial : nil) ?? material
            // Preview paths already carry their material color as point colors.
            if renderedPath.hasColors {
                material.albedo = .color(.white)
            }
            return .stroke(
                renderedPath,
                width: options.lineWidth,
                detail: 5,
                material: material
            )
        }
        guard var mesh = cachedMesh else {
            return nil
        }
        if options.wireframe {
            let width = options.wireframeLineWidth > 0 ?
                options.wireframeLineWidth : options.lineWidth / 2
            mesh = .stroke(
                mesh.uniqueEdges,
                width: width,
                detail: 3,
                material: Material(color: options.lineColor)
            )
        } else if debug, let material = options.debugMaterial {
            mesh = mesh.withoutVertexColors().scaled(by: 1.001).withMaterial(material)
        } else {
            mesh = mesh.replacing(nil, with: material)
        }
        return mesh
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
private extension [Geometry] {
    func realityKitEntityDescriptors(
        with options: Scene.OutputOptions,
        debug: Bool,
        focus: Bool
    ) -> [RealityKitEntityDescriptor] {
        var descriptors = [RealityKitEntityDescriptor]()
        for child in self where !child.isHidden {
            if focus {
                guard !child.isFocused else {
                    descriptors += child.realityKitEntityDescriptors(
                        with: options,
                        debug: false
                    )
                    continue
                }
                guard child.childIsFocused else {
                    continue
                }
                descriptors += child.renderedChildren.realityKitEntityDescriptors(
                    with: options,
                    debug: false,
                    focus: true
                )
                continue
            }
            if debug, !child.debug {
                descriptors += child.renderedChildren.realityKitEntityDescriptors(
                    with: options,
                    debug: true,
                    focus: focus
                )
            } else {
                descriptors += child.realityKitEntityDescriptors(
                    with: options,
                    debug: debug
                )
            }
        }
        return descriptors
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
private struct RealityKitDataKey: Hashable, Sendable {
    var debug: Bool
    var options: Scene.OutputOptions
    var vertexColors = false
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
private struct RealityKitData: @unchecked Sendable {
    let resource: MeshResource
    let collisionResource: MeshResource
    let materials: [RealityKit.Material]
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
private extension Geometry {
    var realityKitData: [RealityKitDataKey: RealityKitData] {
        get { associatedData as? [RealityKitDataKey: RealityKitData] ?? [:] }
        set { associatedData = newValue }
    }

    @MainActor func realityKitData(
        for mesh: Mesh,
        key: RealityKitDataKey
    ) throws -> RealityKitData {
        if let data = realityKitData[key] {
            return data
        }
        let entity = try ModelEntity(triangles: mesh) { material in
            let converted = realityKitMaterial(material) ?? PhysicallyBasedMaterial(Color.white)
            return self.previewPath != nil ? unlitMaterial(converted) : converted
        }
        let model = entity.model!
        let data = try RealityKitData(
            resource: model.mesh,
            collisionResource: model.mesh.collisionResource(for: mesh),
            materials: model.materials
        )
        realityKitData[key] = data
        return data
    }

    func realityKitData(
        for mesh: Mesh,
        key: RealityKitDataKey
    ) async throws -> RealityKitData {
        var key = key
        #if compiler(>=6)
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
            key.vertexColors = mesh.hasVertexColors
        }
        #endif
        if let data = realityKitData[key] {
            return data
        }
        let data = try await Self.realityKitData(for: mesh, unlit: previewPath != nil)
        if let data = realityKitData[key] {
            return data
        }
        realityKitData[key] = data
        return data
    }

    @MainActor static func realityKitData(
        for mesh: Mesh,
        unlit: Bool
    ) async throws -> RealityKitData {
        #if compiler(>=6)
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *), mesh.hasVertexColors {
            var materials = [RealityKit.Material]()
            for material in mesh.materials {
                let material = realityKitMaterial(material) ?? PhysicallyBasedMaterial(Color.white)
                let opacity: PhysicallyBasedMaterial.Opacity = switch material.blending {
                case .opaque: .init(floatLiteral: 1)
                case let .transparent(value): value
                @unknown default: .init(floatLiteral: 1)
                }
                let color = Color(material.baseColor.tint)
                var shader = try await RealityKitVertexColorMaterial.make(
                    color: color.withAlphaComponent(color.alpha * Double(opacity.scale)),
                    texture: material.baseColor.texture,
                    normal: material.normal.texture,
                    opacityTexture: opacity.texture,
                    emissionTexture: material.emissiveColor.texture,
                    roughnessTexture: material.roughness.texture,
                    metallicTexture: material.metallic.texture,
                    // Built-in emission uses the texture without a tint; the graph multiplies its inputs.
                    emission: material.emissiveColor.texture == nil ? Color(material.emissiveColor.color) : .white,
                    emissionIntensity: material.emissiveIntensity,
                    roughness: material.roughness.scale,
                    metallic: material.metallic.scale,
                    specular: material.specular.scale,
                    unlit: unlit
                )
                shader.faceCulling = material.faceCulling
                materials.append(shader)
            }
            let resource = try await MeshResource.generate(triangles: mesh)
            return try RealityKitData(
                resource: resource,
                collisionResource: resource.collisionResource(for: mesh),
                materials: materials
            )
        }
        #endif
        let entity = try await ModelEntity(triangles: mesh) { material in
            let converted = realityKitMaterial(material) ?? PhysicallyBasedMaterial(Color.white)
            return unlit ? unlitMaterial(converted) : converted
        }
        let model = entity.model!
        return try RealityKitData(
            resource: model.mesh,
            collisionResource: model.mesh.collisionResource(for: mesh),
            materials: model.materials
        )
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
private extension RealityKitEntityDescriptor {
    @MainActor func realityKitEntityReference() throws -> RealityKitEntityReference {
        let data = try geometry.realityKitData(
            for: mesh,
            key: .init(debug: debug, options: options)
        )
        let entity = ModelEntity(mesh: data.resource, materials: data.materials)
        entity.transform = RealityKit.Transform(transform)
        return RealityKitEntityReference(
            entity: entity,
            geometry: geometry,
            collisionMesh: data.collisionResource
        )
    }

    func realityKitEntityReference() async throws -> RealityKitEntityReference {
        let data = try await geometry.realityKitData(
            for: mesh,
            key: .init(debug: debug, options: options)
        )
        return await MainActor.run {
            let entity = ModelEntity(mesh: data.resource, materials: data.materials)
            entity.transform = RealityKit.Transform(transform)
            return RealityKitEntityReference(
                entity: entity,
                geometry: geometry,
                collisionMesh: data.collisionResource
            )
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
@MainActor private func realityKitMaterial(_ material: Polygon.Material?) -> PhysicallyBasedMaterial? {
    switch material {
    case let material as Material:
        PhysicallyBasedMaterial(material)
    case let color as Color:
        PhysicallyBasedMaterial(color)
    default:
        nil
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
@MainActor private func unlitMaterial(_ material: RealityKit.Material) -> RealityKit.Material {
    guard let material = material as? PhysicallyBasedMaterial else { return material }
    var unlit = UnlitMaterial(color: material.baseColor.tint)
    unlit.color.texture = material.baseColor.texture
    switch material.blending {
    case .opaque: break
    case let .transparent(opacity): unlit.blending = .transparent(opacity: opacity)
    @unknown default: break
    }
    if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
        unlit.faceCulling = material.faceCulling
    }
    return unlit
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
@MainActor private extension Texture {
    enum RealityKitUsage: String {
        case color, normal, scalar, opacity
    }

    static let realityKitResources: NSCache<NSData, TextureResource> = {
        let cache = NSCache<NSData, TextureResource>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    var realityKitTexture: MaterialParameters.Texture? {
        realityKitTexture(usage: .color)
    }

    func realityKitTexture(usage: RealityKitUsage) -> MaterialParameters.Texture? {
        // The same image can be used as both color and normal data, with different decoding.
        let prefix = usage == .normal ? "normal/\(intensity)" : usage.rawValue
        let key = (Data(prefix.utf8) + Data([0]) + data) as NSData
        let resource: TextureResource
        if let cached = Self.realityKitResources.object(forKey: key) {
            resource = cached
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            if usage == .opacity || (usage == .normal && intensity != 1) {
                // Work on raw data, blending toward the flat normal and renormalizing before encoding.
                // Renormalization also avoids clipping components when intensity exceeds one.
                let input = CIImage(cgImage: image, options: [.colorSpace: NSNull()]).unpremultiplyingAlpha()
                let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
                var pixels = [Float](repeating: 0, count: image.width * image.height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    guard let address = buffer.baseAddress else { return }
                    context.render(
                        input,
                        toBitmap: address,
                        rowBytes: image.width * 16,
                        bounds: input.extent,
                        format: .RGBAf,
                        colorSpace: nil
                    )
                }
                var bytes = [UInt8](repeating: 255, count: pixels.count)
                let useAlpha = usage == .opacity && averageOpacity < 1
                for offset in stride(from: 0, to: pixels.count, by: 4) {
                    if usage == .opacity {
                        // ShapeScript masks use alpha when present, otherwise component luminance.
                        let value = useAlpha ? pixels[offset + 3] :
                            pixels[offset] * 0.2126 + pixels[offset + 1] * 0.7152 + pixels[offset + 2] * 0.0722
                        let byte = UInt8(clamping: Int((value * 255).rounded()))
                        bytes[offset] = byte
                        bytes[offset + 1] = byte
                        bytes[offset + 2] = byte
                        continue
                    }
                    var normal = SIMD3<Float>(pixels[offset], pixels[offset + 1], pixels[offset + 2]) * 2 - 1
                    normal = normal * Float(intensity) + SIMD3<Float>(0, 0, Float(1 - intensity))
                    normal = simd_length_squared(normal) > 0 ? simd_normalize(normal) : [0, 0, 1]
                    for channel in 0 ..< 3 {
                        bytes[offset + channel] = UInt8(clamping: Int(((normal[channel] * 0.5 + 0.5) * 255).rounded()))
                    }
                }
                guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                      let adjusted = CGImage(
                          width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
                      )
                else { return nil }
                image = adjusted
            }
            let semantic: TextureResource.Semantic = switch usage {
            case .color: .color
            case .normal: .normal
            case .scalar, .opacity: .scalar
            }
            let options = TextureResource.CreateOptions(semantic: semantic)
            #if os(tvOS)
            guard let generated = try? TextureResource(image: image, options: options) else { return nil }
            #else
            guard let generated = try? TextureResource.generate(from: image, options: options) else { return nil }
            #endif
            resource = generated
            Self.realityKitResources.setObject(resource, forKey: key, cost: image.bytesPerRow * image.height)
        }
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.magFilter = .nearest
        sampler.minFilter = .linear
        sampler.mipFilter = .linear
        return .init(resource, sampler: .init(sampler))
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 26.0, visionOS 1.0, *)
@MainActor private extension PhysicallyBasedMaterial {
    init(_ color: Color) {
        self.init()
        specular = .init(floatLiteral: 0)
        baseColor = .init(tint: OSColor(color.withAlphaComponent(1)))
        if color.alpha < 1 {
            blending = .transparent(opacity: .init(floatLiteral: Float(color.alpha)))
        }
    }

    init(_ material: Material) {
        self.init()
        // SceneKit's default Blinn material has no specular contribution.
        // Keep plain colors matte, while retaining reflections for explicit PBR materials.
        if material.roughness == nil, material.metallicity == nil {
            specular = .init(floatLiteral: 0)
        }
        var opacity = PhysicallyBasedMaterial.Opacity(floatLiteral: 1)
        if let texture = material.opacity?.texture {
            opacity = .init(
                scale: Float(max(0, texture.intensity)),
                texture: texture.realityKitTexture(usage: .opacity)
            )
        } else {
            opacity.scale = Float(material.opacityPropertyAverageOpacity)
        }
        var hasTransparency = opacity.texture != nil || opacity.scale < 1
        if let color = material.color {
            baseColor = .init(tint: OSColor(color.withAlphaComponent(1)))
            opacity.scale *= Float(color.alpha)
            hasTransparency = hasTransparency || color.alpha < 1
        } else if let texture = material.texture, let resource = texture.realityKitTexture {
            let intensity = max(0, texture.intensity)
            // Texture intensity scales linear RGB; alpha remains a separate, linear factor.
            baseColor = .init(tint: OSColor(Euclid.Color(white: intensity).toSRGB()), texture: resource)
            opacity.scale *= Float(intensity)
            hasTransparency = hasTransparency || texture.averageOpacity < 1 || intensity < 1
        }
        if hasTransparency {
            blending = .transparent(opacity: opacity)
        }
        if let color = material.glow?.color {
            emissiveColor = .init(color: OSColor(color.withAlphaComponent(1)))
            emissiveIntensity = Float(color.alpha)
        } else if let texture = material.glow?.texture {
            emissiveColor = .init(texture: texture.realityKitTexture)
            emissiveIntensity = Float(max(0, texture.intensity))
        }
        normal = .init(texture: material.normals?.realityKitTexture(usage: .normal))
        if let texture = material.roughness?.texture {
            roughness = .init(
                scale: Float(max(0, texture.intensity)),
                texture: texture.realityKitTexture(usage: .scalar)
            )
        } else {
            roughness = .init(floatLiteral: Float(material.roughness?.averageLuminance ?? 0.5))
        }
        if let texture = material.metallicity?.texture {
            metallic = .init(
                scale: Float(max(0, texture.intensity)),
                texture: texture.realityKitTexture(usage: .scalar)
            )
        } else {
            metallic = .init(floatLiteral: Float(material.metallicity?.averageLuminance ?? 0))
        }
    }
}

@MainActor
@available(macOS 12.0, iOS 15.0, tvOS 26.0, *)
private extension MeshResource {
    /// LowLevelMesh collision generation fails on older macOS, iOS, and visionOS runtimes. Keep a descriptor-backed
    /// resource for collisions while preserving vertex colors in the rendering resource.
    func collisionResource(for mesh: Mesh) throws -> MeshResource {
        #if compiler(>=6)
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *), lowLevelMesh != nil {
            return try MeshResource.generate(from: [MeshDescriptor(triangles: mesh)])
        }
        #endif
        return self
    }
}

#endif
