//
//  RealityKitGeometryTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if canImport(RealityKit)

@testable import ShapeScript
import Euclid
import ImageIO
import Metal
import RealityKit
import XCTest

final class RealityKitGeometryTests: XCTestCase {
    func testEnvironmentLightingDetectionUsesMeshMaterials() {
        let context = EvaluationContext(source: "", delegate: nil)
        var textured = ShapeScript.Material()
        textured.albedo = .texture(.checkerboard)
        var rough = textured
        rough.roughness = .texture(.checkerboard)
        var metallic = ShapeScript.Material()
        metallic.metallicity = .color(.black)
        for (material, expected) in [(textured, false), (rough, true), (metallic, true)] {
            // Imported meshes can carry PBR materials even when their geometry's material is plain.
            let mesh = Mesh.merge([Mesh.cube(material: ShapeScript.Material()), Mesh.sphere(material: material)])
            let geometry = Geometry(type: .mesh(mesh), in: context)
            let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            let descriptors = scene.realityKitEntityDescriptors()
            XCTAssertFalse(descriptors.isEmpty)
            XCTAssertEqual(descriptors.contains(where: \.usesPhysicallyBasedMaterials), expected)
            var wireframe = Scene.OutputOptions.default
            wireframe.wireframe = true
            XCTAssertFalse(scene.realityKitEntityDescriptors(with: wireframe)
                .contains(where: \.usesPhysicallyBasedMaterials))
        }
    }

    #if compiler(>=6)

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testAuthoredLightsPreserveTypesTransformsColorsAndSpotAngles() async throws {
        let scene = try evaluate(parse("""
        group {
            position 3 4 5
            light {
                color 1 0 0 0.5
                orientation 0 0.5 0
                shadow 1
            }
            light {
                color 0 1 0 0.25
                position 1 2 3
            }
            light {
                color blue
                position 3 2 1
                orientation 0 0.5 0
                spread 0.25
                penumbra 0.25
                shadow 1
            }
        }
        """), delegate: nil)
        let lighting = try await scene.realityKitLightingEntity()
        XCTAssertEqual(lighting.children.count, 3)
        for (entity, geometry) in zip(lighting.children, scene.lights) {
            let expected = RealityKit.Transform(geometry.worldTransform)
            XCTAssertEqual(entity.position, expected.translation)
            XCTAssertEqual(entity.orientation.vector, expected.rotation.vector)
        }
        let directional = try XCTUnwrap(lighting.children[0].components[DirectionalLightComponent.self])
        XCTAssertEqual(directional.intensity, 500)
        XCTAssertEqual(Color(directional.color).red, 1, accuracy: 1e-6)
        XCTAssertEqual(Color(directional.color).green, 0, accuracy: 1e-6)
        XCTAssertEqual(Color(directional.color).alpha, 1, accuracy: 1e-6)
        XCTAssertNotNil(lighting.children[0].components[DirectionalLightComponent.Shadow.self])
        let point = try XCTUnwrap(lighting.children[1].components[PointLightComponent.self])
        XCTAssertEqual(point.intensity, 250)
        XCTAssertEqual(Color(point.color).green, 1, accuracy: 1e-6)
        let spot = try XCTUnwrap(lighting.children[2].components[SpotLightComponent.self])
        XCTAssertEqual(spot.outerAngleInDegrees, 45, accuracy: 1e-5)
        XCTAssertEqual(spot.innerAngleInDegrees, 33.75, accuracy: 1e-5)
        XCTAssertNotNil(lighting.children[2].components[SpotLightComponent.Shadow.self])
        let environment = try XCTUnwrap(lighting.components[ImageBasedLightComponent.self])
        guard case .none = environment.source else { return XCTFail("Unexpected ambient light") }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testAmbientLightsAccumulateInLinearLight() async throws {
        let scene = try evaluate(parse("light { color 0.5 0.5 0.5 }\nlight { color 0.5 0.5 0.5 }"), delegate: nil)
        let lighting = try await scene.realityKitLightingEntity()
        XCTAssertTrue(lighting.children.isEmpty)
        let environment = try XCTUnwrap(lighting.components[ImageBasedLightComponent.self])
        XCTAssertEqual(environment.intensityExponent, Float(log2(2 * 0.21404114048223255)), accuracy: 1e-6)
        guard case .single = environment.source else { return XCTFail("Missing ambient environment") }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testNoLightsRetainDefaultsButBlackAmbientSuppressesThem() async throws {
        let empty = try await Scene.empty.realityKitLightingEntity()
        XCTAssertTrue(empty.children.isEmpty)
        XCTAssertNil(empty.components[ImageBasedLightComponent.self])
        let black = try evaluate(parse("light { color black }"), delegate: nil)
        let lighting = try await black.realityKitLightingEntity()
        let environment = try XCTUnwrap(lighting.components[ImageBasedLightComponent.self])
        guard case .none = environment.source else { return XCTFail("Black ambient should remain dark") }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testHiddenLightsDoNotSuppressDefaults() async throws {
        let scene = try evaluate(parse("light { position 1 2 3 }"), delegate: nil)
        scene.lights[0].isHidden = true
        let lighting = try await scene.realityKitLightingEntity()
        XCTAssertTrue(lighting.children.isEmpty)
        XCTAssertNil(lighting.components[ImageBasedLightComponent.self])
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testNormalMapsSurviveBothMaterialPathsAndUseSeparateTextureCache() async throws {
        let context = EvaluationContext(source: "", delegate: nil)
        var material = ShapeScript.Material()
        material.albedo = .texture(.checkerboard)
        material.normals = .checkerboard
        func scene(_ material: ShapeScript.Material, vertexColors: Bool) -> ShapeScript.Scene {
            var mesh = Mesh.cube(material: material)
            if vertexColors { mesh = mesh.mapVertexColors { _ in .gray } }
            let geometry = Geometry(type: .mesh(mesh), in: context)
            let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            return scene
        }
        func builtIn(_ material: ShapeScript.Material) throws -> PhysicallyBasedMaterial {
            let references = try scene(material, vertexColors: false).realityKitEntityReferences()
            let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
            return try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
        }
        let converted = try builtIn(material)
        let color = try XCTUnwrap(converted.baseColor.texture)
        let normal = try XCTUnwrap(converted.normal.texture)
        XCTAssertNotEqual(color.resource, normal.resource)
        let repeated = try XCTUnwrap(builtIn(material).normal.texture)
        XCTAssertEqual(normal.resource, repeated.resource)
        material.normals = .checkerboard.withIntensity(0.25)
        let reduced = try XCTUnwrap(builtIn(material).normal.texture)
        XCTAssertNotEqual(normal.resource, reduced.resource)
        let references = try await scene(material, vertexColors: true).realityKitEntityReferences()
        let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
        let shader = try XCTUnwrap(entity.model?.materials.first as? ShaderGraphMaterial)
        switch shader.getParameter(name: "normalTexture") {
        case let .texture(texture): XCTAssertEqual(texture.resource, reduced.resource)
        case let .textureResource(resource): XCTAssertEqual(resource, reduced.resource)
        default: XCTFail("Missing normal map on vertex-color material")
        }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testAllMaterialTexturesSurviveBothPaths() async throws {
        var material = ShapeScript.Material()
        material.albedo = .texture(.checkerboard.withIntensity(0.8))
        material.opacity = .texture(.checkerboard.withIntensity(0.6))
        material.normals = .checkerboard
        material.roughness = .texture(.checkerboard.withIntensity(0.4))
        material.metallicity = .texture(.checkerboard.withIntensity(0.7))
        material.glow = .texture(.checkerboard.withIntensity(1.5))
        let context = EvaluationContext(source: "", delegate: nil)
        func scene(vertexColors: Bool) -> ShapeScript.Scene {
            var mesh = Mesh.cube(material: material)
            if vertexColors { mesh = mesh.mapVertexColors { _ in .gray } }
            let geometry = Geometry(type: .mesh(mesh), in: context)
            let scene = ShapeScript.Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            return scene
        }
        func builtIn() throws -> PhysicallyBasedMaterial {
            let references = try scene(vertexColors: false).realityKitEntityReferences()
            let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
            return try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
        }
        let converted = try builtIn()
        let base = try XCTUnwrap(converted.baseColor.texture)
        let roughness = try XCTUnwrap(converted.roughness.texture)
        let metallic = try XCTUnwrap(converted.metallic.texture)
        let glow = try XCTUnwrap(converted.emissiveColor.texture)
        guard case let .transparent(opacity) = converted.blending else { return XCTFail("Expected opacity mask") }
        let mask = try XCTUnwrap(opacity.texture)
        XCTAssertEqual(converted.roughness.scale, 0.4)
        XCTAssertEqual(converted.metallic.scale, 0.7)
        XCTAssertEqual(converted.emissiveIntensity, 1.5)
        XCTAssertEqual(Color(converted.emissiveColor.color), .black)
        XCTAssertEqual(Double(opacity.scale), 0.48, accuracy: 1e-6)
        XCTAssertEqual(Color(converted.baseColor.tint).toLinear().red, 0.8, accuracy: 1e-6)
        XCTAssertEqual(base.resource, glow.resource)
        XCTAssertEqual(roughness.resource, metallic.resource)
        XCTAssertNotEqual(base.resource, roughness.resource)
        XCTAssertNotEqual(mask.resource, roughness.resource)
        let references = try await scene(vertexColors: true).realityKitEntityReferences()
        let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
        let shader = try XCTUnwrap(entity.model?.materials.first as? ShaderGraphMaterial)
        for (name, expected) in [
            ("baseTexture", base),
            ("opacityTexture", mask),
            ("emissionTexture", glow),
            ("roughnessTexture", roughness),
            ("metallicTexture", metallic),
        ] {
            switch shader.getParameter(name: name) {
            case let .texture(texture): XCTAssertEqual(texture.resource, expected.resource)
            case let .textureResource(resource): XCTAssertEqual(resource, expected.resource)
            default: XCTFail("Missing texture: \(name)")
            }
        }
        XCTAssertEqual(shader.getParameter(name: "roughness"), .float(0.4))
        XCTAssertEqual(shader.getParameter(name: "metallic"), .float(0.7))
        XCTAssertEqual(shader.getParameter(name: "emissiveIntensity"), .float(1.5))
    }

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testOpacityTexturesUseAlphaOrComponentLuminanceWithoutGammaConversion() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        for (pixels, expected) in [
            ([UInt8](arrayLiteral: 64, 64, 64, 255, 192, 192, 192, 255), [64, 192]),
            ([UInt8](arrayLiteral: 255, 0, 0, 255, 0, 255, 0, 255), [54, 182]),
            ([UInt8](arrayLiteral: 200, 30, 90, 64, 30, 200, 90, 192), [64, 192]),
        ] {
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            var material = ShapeScript.Material(color: .white)
            material.opacity = .texture(.data(data as Data))
            let geometry = Geometry(
                type: .mesh(Mesh.cube(material: material)),
                in: EvaluationContext(source: "", delegate: nil)
            )
            let scene = ShapeScript.Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            let references = try await scene.realityKitEntityReferences()
            let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
            let converted = try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
            guard case let .transparent(opacity) = converted.blending else { return XCTFail("Expected opacity mask") }
            let resource = try XCTUnwrap(opacity.texture?.resource)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: resource.pixelFormat,
                width: 2,
                height: 1,
                mipmapped: false
            )
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            try await resource.copy(to: texture)
            let stride: Int
            let red: Int
            switch resource.pixelFormat {
            case .r8Unorm: stride = 1; red = 0
            case .rgba8Unorm: stride = 4; red = 0
            case .bgra8Unorm: stride = 4; red = 2
            default: return XCTFail("Unexpected data format: \(resource.pixelFormat)")
            }
            var actual = [UInt8](repeating: 0, count: 2 * stride)
            texture.getBytes(&actual, bytesPerRow: 2 * stride, from: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0)
            for index in 0 ..< 2 {
                XCTAssertEqual(Double(actual[index * stride + red]), Double(expected[index]), accuracy: 1)
            }
        }
    }

    #endif

    @MainActor func testPlainColorsAreMatteButExplicitPBRMaterialsRetainSpecular() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        var glossy = ShapeScript.Material(color: .black)
        glossy.roughness = .color(Color(white: 0.2))
        var metallic = ShapeScript.Material(color: .black)
        metallic.metallicity = .color(.white)
        for (material, expectedSpecular) in [
            (ShapeScript.Material(color: .black), Float(0)),
            (glossy, PhysicallyBasedMaterial().specular.scale),
            (metallic, PhysicallyBasedMaterial().specular.scale),
        ] {
            let geometry = Geometry(type: .mesh(Mesh.cube(material: material)), in: context)
            let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            let reference = try XCTUnwrap(scene.realityKitEntityReferences().first)
            let entity = try XCTUnwrap(reference.entity as? ModelEntity)
            let converted = try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
            XCTAssertEqual(converted.specular.scale, expectedSpecular)
        }
    }

    @MainActor func testPlainPathsUseUnlitMaterials() async throws {
        let context = EvaluationContext(source: "", delegate: nil)
        let geometry = Geometry(type: .path(Path([.point(0, 0), .point(1, 0)])), in: context)
        let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
        XCTAssertTrue(scene.build { false })
        func synchronousReferences() throws -> [RealityKitEntityReference] {
            try scene.realityKitEntityReferences()
        }
        let synchronous = try synchronousReferences()
        let asynchronous = try await scene.realityKitEntityReferences()
        for references in [synchronous, asynchronous] {
            let entity = try XCTUnwrap(references.first?.entity as? ModelEntity)
            XCTAssertTrue(entity.model?.materials.first is UnlitMaterial)
        }
    }

    @MainActor func testSynchronousVertexColorsAreAppliedPerMaterial() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        let first = Material(color: .white)
        var second = first
        second.roughness = .color(.init(white: 0.8))
        let mesh = Mesh.merge([
            Mesh.cube(material: first).mapVertexColors { _ in .init(red: 0.5, green: 0.25, blue: 0.75) },
            Mesh.cube(material: second).mapVertexColors { _ in .blue },
        ])
        let geometry = Geometry(type: .mesh(mesh), in: context)
        let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
        XCTAssertTrue(scene.build { false })
        let entity = try XCTUnwrap(scene.realityKitEntityReferences().first?.entity as? ModelEntity)
        let materials = try XCTUnwrap(entity.model?.materials)
        XCTAssertEqual(materials.count, 2)
        for (material, expected) in zip(materials, [Color(red: 0.5, green: 0.25, blue: 0.75), .blue]) {
            let material = try XCTUnwrap(material as? PhysicallyBasedMaterial)
            let color = Color(material.baseColor.tint)
            XCTAssertEqual(color.red, expected.red, accuracy: 0.000001)
            XCTAssertEqual(color.green, expected.green, accuracy: 0.000001)
            XCTAssertEqual(color.blue, expected.blue, accuracy: 0.000001)
        }
    }

    @MainActor func testPathColorAlphaIsNotAppliedTwice() throws {
        let scene = try evaluate(parse("path { color 1 0 0 0.5\npoint -1 0\npoint 1 0 }"), delegate: nil)
        XCTAssertTrue(scene.build { false })
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(geometry.material.averageOpacity, 0.5)
        let entity = try XCTUnwrap(scene.realityKitEntityReferences().first?.entity as? ModelEntity)
        let material = try XCTUnwrap(entity.model?.materials.first as? UnlitMaterial)
        guard case let .transparent(opacity) = material.blending else { return XCTFail("Expected transparency") }
        XCTAssertEqual(opacity.scale, 0.5)
    }

    @MainActor func testSynchronousVertexAlphaMultipliesMaterialOpacity() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        var material = Material(color: .init(white: 1, alpha: 0.5))
        material.opacity = .color(.init(white: 0.5))
        let mesh = Mesh.cube(material: material).mapVertexColors { _ in .init(red: 1, green: 0, blue: 0, alpha: 0.5) }
        let geometry = Geometry(type: .mesh(mesh), in: context)
        let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
        XCTAssertTrue(scene.build { false })
        let entity = try XCTUnwrap(scene.realityKitEntityReferences().first?.entity as? ModelEntity)
        let converted = try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
        guard case let .transparent(opacity) = converted.blending else {
            return XCTFail("Expected transparent material")
        }
        XCTAssertEqual(opacity.scale, 0.125)
    }

    #if compiler(>=6)

    @available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 2.0, *)
    @MainActor func testColoredMeshUsesSeparateCollisionResource() async throws {
        let context = EvaluationContext(source: "", delegate: nil)
        let mesh = Mesh.cube().mapVertexColors { _ in .blue }
        let geometry = Geometry(type: .mesh(mesh), in: context)
        let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
        XCTAssertTrue(scene.build { false })
        func synchronousReferences() throws -> [RealityKitEntityReference] {
            try scene.realityKitEntityReferences()
        }
        let synchronous = try synchronousReferences()
        let asynchronous = try await scene.realityKitEntityReferences()
        for references in [synchronous, asynchronous] {
            let reference = try XCTUnwrap(references.first)
            let entity = try XCTUnwrap(reference.entity as? ModelEntity)
            XCTAssertNotNil(entity.model?.mesh.lowLevelMesh)
            let collision = try XCTUnwrap(reference.collisionMesh)
            XCTAssertNil(collision.lowLevelMesh)
            _ = try await ShapeResource.generateStaticMesh(from: collision)
        }
    }

    #endif

    func testDebugMeshDiscardsVertexColors() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        let mesh = Mesh.cube().mapVertexColors { _ in .red }
        let geometry = Geometry(type: .mesh(mesh), in: context)
        geometry.debug = true
        let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
        XCTAssertTrue(scene.build { false })
        var options = Scene.OutputOptions.default
        options.debugMaterial = Material(color: .green)
        let descriptor = try XCTUnwrap(scene.realityKitEntityDescriptors(with: options).first)
        XCTAssertFalse(descriptor.mesh.hasVertexColors)
    }

    func testNestedTextTransformsMatchSceneHierarchy() throws {
        let scene = try Scene(csgString: """
        translate([110,0,80]) {
            translate([100,0,40]) rotate([90,0,0])
                linear_extrude(height=1) text("Open", size=42, font="Helvetica");
            translate([160,0,-30]) rotate([90,0,0])
                linear_extrude(height=1) text("Subtitle", size=18, font="Helvetica");
        }
        """, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        let descriptors = scene.realityKitEntityDescriptors()
        XCTAssertEqual(descriptors.count, 2)
        for descriptor in descriptors {
            for vertex in descriptor.mesh.polygons.flatMap(\.vertices) {
                var expected = vertex.position
                var geometry: Geometry? = descriptor.geometry
                while let current = geometry {
                    expected = expected.transformed(by: current.transform)
                    geometry = current.parent
                }
                let actual = vertex.position.transformed(by: descriptor.transform)
                XCTAssertEqual(actual.x, expected.x, accuracy: 1e-8)
                XCTAssertEqual(actual.y, expected.y, accuracy: 1e-8)
                XCTAssertEqual(actual.z, expected.z, accuracy: 1e-8)
            }
        }
    }

    func testBooleanDebugOverlayExcludesUnmarkedSiblings() throws {
        let scene = try Scene(csgString: """
        difference() {
            sphere(r=3, $fn=12);
            cylinder(h=8, r=1, center=true, $fn=12);
            #rotate([90,0,0]) cylinder(h=8, r=1, center=true, $fn=12);
        }
        """, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        let descriptors = scene.realityKitEntityDescriptors()
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(descriptors.filter(\.debug).count, 1)
        XCTAssertTrue(descriptors.filter(\.debug).allSatisfy(\.geometry.debug))
        XCTAssertEqual(descriptors.filter { !$0.debug }.first?.geometry.type, .difference)
        let debugMesh = try XCTUnwrap(descriptors.first(where: \.debug)?.mesh)
        let expected = try XCTUnwrap(Scene.OutputOptions.default.debugMaterial)
        XCTAssertNil(expected.glow)
        XCTAssertFalse(debugMesh.polygons.isEmpty)
        XCTAssertTrue(debugMesh.polygons.allSatisfy { ($0.material as? ShapeScript.Material) == expected })
    }

    func testPathGroupsDoNotDuplicateChildGeometry() {
        let context = EvaluationContext(source: "", delegate: nil)
        let group = Geometry(type: .group, in: context, children: [
            Geometry(type: .path(Path([.point(0, 0), .point(1, 0)])), in: context),
            Geometry(type: .path(Path([.point(0, 2), .point(1, 2)])), in: context),
        ])
        let scene = Scene(background: .color(.clear), children: [group], cache: nil)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.realityKitEntityDescriptors().count, 2)
    }
}

#endif
