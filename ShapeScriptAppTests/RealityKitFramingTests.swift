//
//  RealityKitFramingTests.swift
//  ShapeScriptAppTests
//

#if os(macOS)

@testable import Viewer
import Euclid
import Metal
import RealityKit
import SceneKit
import ShapeScript
import XCTest

@available(macOS 15.0, *)
@MainActor
final class RealityKitFramingTests: XCTestCase {
    func testDefaultLightingAdaptsToRenderedMaterialsAndResetsBetweenScenes() async throws {
        let renderer = RealityKitRenderer()
        let root = renderer.realityKitView.rootEntity
        let light = try XCTUnwrap(renderer.cameraEntity.children.first)
        let cases: [(String, Bool)] = [
            ("cube { color red }", false),
            ("cube { roughness 0.2 }", true),
            ("group {\n cube { color red }\n sphere { metallicity 1 }\n }", true),
            ("cube { color blue }", false),
            ("cube { metallicity 0 }", true),
            ("", false),
        ]
        for (source, usesPBR) in cases {
            let scene = try evaluate(parse(source), delegate: nil)
            XCTAssertTrue(scene.build { false })
            await renderer.prepareAsync(scene, options: .default)
            XCTAssertEqual(root.components.has(ImageBasedLightComponent.self), !usesPBR, source)
            XCTAssertEqual(root.components.has(ImageBasedLightReceiverComponent.self), !usesPBR, source)
            XCTAssertEqual(
                light.components[DirectionalLightComponent.self]?.intensity,
                usesPBR ? 1000 : 3000, source
            )
        }
        let scene = try evaluate(parse("cube { metallicity 1 }"), delegate: nil)
        XCTAssertTrue(scene.build { false })
        await renderer.prepareAsync(scene, options: .default)
        var wireframe = ShapeScript.Scene.OutputOptions.default
        wireframe.wireframe = true
        await renderer.prepareAsync(scene, options: wireframe)
        XCTAssertTrue(root.components.has(ImageBasedLightReceiverComponent.self))
        XCTAssertEqual(light.components[DirectionalLightComponent.self]?.intensity, 3000)
    }

    func testGradientEndpointMatchesSolidMaterialColor() async throws {
        let renderer = RealityKitRenderer()
        let outputRenderer = try RealityRenderer()
        outputRenderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        outputRenderer.entities.append(renderer.realityKitView.rootEntity)
        outputRenderer.activeCamera = renderer.cameraEntity
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func pixels() async throws -> [UInt8] {
            for _ in 0 ..< 3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try outputRenderer.updateAndRender(
                            deltaTime: 1 / 60, cameraOutput: output,
                            onComplete: { _ in continuation.resume() }
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
            texture.getBytes(
                &pixels, bytesPerRow: 128 * 4,
                from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
            )
            return pixels
        }

        let colors = [0.05, 0.25, 0.5, 1.0].flatMap { value in
            [
                Color(red: value, green: 0, blue: 0),
                Color(red: 0, green: value, blue: 0),
                Color(red: 0, green: 0, blue: value),
                Color(white: value),
            ]
        } + [Color(red: 0.2, green: 0.4, blue: 0.6)]
        for color in colors {
            let scene = try evaluate(parse("""
            mesh {
                polygon {
                    color black
                    point -0.5 -0.5
                    point 0.5 -0.5
                    color \(color.red) \(color.green) \(color.blue)
                    point 0.5 0
                    point -0.5 0
                }
                polygon {
                    color \(color.red) \(color.green) \(color.blue)
                    point -0.5 0
                    point 0.5 0
                    point 0.5 0.5
                    point -0.5 0.5
                }
            }
            """), delegate: nil)
            XCTAssertTrue(scene.build { false })
            await renderer.prepareAsync(scene, options: .default)
            renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 3], relativeTo: nil)
            let values = try await pixels()
            for channel in 0 ..< 3 {
                let solid = Int(values[(62 * 128 + 64) * 4 + channel])
                let gradient = Int(values[(65 * 128 + 64) * 4 + channel])
                // Just below the endpoint the gradient must be slightly darker, never brighter.
                XCTAssertLessThanOrEqual(
                    gradient,
                    solid + 1,
                    "\(color), channel=\(channel), gradient=\(gradient), solid=\(solid)"
                )
                XCTAssertLessThanOrEqual(
                    solid - gradient,
                    12,
                    "\(color), channel=\(channel), gradient=\(gradient), solid=\(solid)"
                )
            }
        }
    }

    func testAlbedoTexturePreservesWhiteCornersAndAlpha() async throws {
        try await assertAlbedoTexturePreservesWhiteCornersAndAlpha(vertexColors: false)
    }

    func testVertexColoredAlbedoTexturePreservesWhiteCornersAndAlpha() async throws {
        try await assertAlbedoTexturePreservesWhiteCornersAndAlpha(vertexColors: true)
    }

    private func assertAlbedoTexturePreservesWhiteCornersAndAlpha(vertexColors: Bool) async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        if vertexColors {
            // Match Euclid's texturedShaderDevice() guard: this GPU supports built-in
            // materials but cannot compile textured shader graph argument encoders.
            try XCTSkipIf(
                device.name.localizedCaseInsensitiveContains("Paravirtual"),
                "RealityKit textured shader argument encoding is unsupported on \(device.name)"
            )
        }
        let renderer = RealityKitRenderer()
        let outputRenderer = try RealityRenderer()
        outputRenderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        outputRenderer.entities.append(renderer.realityKitView.rootEntity)
        outputRenderer.activeCamera = renderer.cameraEntity
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func pixels() async throws -> [UInt8] {
            for _ in 0 ..< 3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try outputRenderer.updateAndRender(
                            deltaTime: 1 / 60, cameraOutput: output,
                            onComplete: { _ in continuation.resume() }
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
            texture.getBytes(
                &pixels, bytesPerRow: 128 * 4,
                from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
            )
            return pixels
        }

        func imageData(_ bytes: [UInt8]) throws -> Data {
            let cgImage = try XCTUnwrap(try CGImage(
                width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64,
                space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)),
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            return try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        }

        for alpha in [255, 128] {
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
            for y in 0 ..< 16 {
                for x in 0 ..< 16 {
                    let center = (4 ..< 12).contains(x) && (4 ..< 12).contains(y)
                    let offset = (y * 16 + x) * 4
                    bytes[offset] = 255
                    bytes[offset + 1] = center ? 0 : 255
                    bytes[offset + 2] = center ? 0 : 255
                    bytes[offset + 3] = center ? UInt8(alpha) : 255
                }
            }
            let image = try imageData(bytes)
            var material = ShapeScript.Material.default
            let intensity = alpha == 255 ? 1.0 : 0.5
            material.albedo = .texture(.data(image, intensity: intensity))
            let vertices = [
                Vertex([-0.5, -0.5, 0], .unitZ, [0, 0], .white),
                Vertex([0.5, -0.5, 0], .unitZ, [1, 0], vertexColors ? Color(white: 0.9) : .white),
                Vertex([0.5, 0.5, 0], .unitZ, [1, 1], vertexColors ? Color(white: 0.9) : .white),
                Vertex([-0.5, 0.5, 0], .unitZ, [0, 1], .white),
            ]
            let mesh = try Mesh([XCTUnwrap(Polygon(vertices, material: material))])
            let geometry = Geometry(
                type: .mesh(mesh), name: nil, transform: .identity, material: .default,
                smoothing: nil, children: [], sourceLocation: nil
            )
            let scene = Scene(background: .color(.clear), children: [geometry], cache: nil)
            XCTAssertTrue(scene.build { false })
            await renderer.prepareAsync(scene, options: .default)
            renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 2], relativeTo: nil)
            let values = try await pixels()
            let center = Array(values[(64 * 128 + 64) * 4 ..< (64 * 128 + 64) * 4 + 4])
            XCTAssertGreaterThan(center[0], 30, "\(center)")
            XCTAssertGreaterThan(Int(center[0]) - Int(center[1]), 30, "\(center)")
            XCTAssertEqual(Double(center[3]) / 255, Double(alpha) / 255 * intensity, accuracy: 0.02)
            for (x, y) in [(43, 43), (84, 43), (43, 84), (84, 84)] {
                let corner = Array(values[(y * 128 + x) * 4 ..< (y * 128 + x) * 4 + 4])
                XCTAssertGreaterThan(corner[1], 40, "White corner missing: \(corner), shader=\(vertexColors)")
                XCTAssertEqual(Double(corner[0]), Double(corner[1]), accuracy: 3)
                XCTAssertEqual(Double(corner[1]), Double(corner[2]), accuracy: 3)
            }
            // Compare texture alpha with scalar opacity using the same RGB texture
            // path. Solid tints and textures can use different working primaries.
            var opaqueBytes = bytes
            for offset in stride(from: 3, to: opaqueBytes.count, by: 4) {
                opaqueBytes[offset] = 255
            }
            var referenceMaterial = ShapeScript.Material.default
            referenceMaterial.albedo = try .texture(.data(imageData(opaqueBytes), intensity: intensity))
            referenceMaterial.opacity = .color(Color(white: 1, alpha: Double(alpha) / 255))
            let referenceGeometry = Geometry(
                type: .mesh(mesh.withMaterial(referenceMaterial)), name: nil,
                transform: .identity, material: .default, smoothing: nil,
                children: [], sourceLocation: nil
            )
            let referenceScene = Scene(background: .color(.clear), children: [referenceGeometry], cache: nil)
            XCTAssertTrue(referenceScene.build { false })
            await renderer.prepareAsync(referenceScene, options: .default)
            renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 2], relativeTo: nil)
            let referencePixels = try await pixels()
            let reference = Array(referencePixels[(64 * 128 + 64) * 4 ..< (64 * 128 + 64) * 4 + 4])
            for channel in 0 ..< 4 {
                XCTAssertEqual(
                    Double(center[channel]), Double(reference[channel]), accuracy: 2,
                    "alpha=\(alpha), shader=\(vertexColors), channel=\(channel), actual=\(center), reference=\(reference)"
                )
            }
        }
    }

    func testPathVertexColorsAndSelection() async throws {
        let renderer = RealityKitRenderer()
        let scene = try evaluate(parse("""
        path {
            color red
            point -1 0
            color blue
            point 1 0
        }
        """), delegate: nil)
        XCTAssertTrue(scene.build { false })
        var options = ShapeScript.Scene.OutputOptions.default
        options.lineWidth = 0.3
        // A prior synchronous conversion must not hide the shader-backed async version.
        func convertSynchronously() throws {
            _ = try scene.realityKitEntityReferences(with: options)
        }
        try convertSynchronously()
        await renderer.prepareAsync(scene, options: options)
        renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 3], relativeTo: nil)
        let outputRenderer = try RealityRenderer()
        outputRenderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        outputRenderer.entities.append(renderer.realityKitView.rootEntity)
        outputRenderer.activeCamera = renderer.cameraEntity
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func pixels() async throws -> [UInt8] {
            for _ in 0 ..< 3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try outputRenderer.updateAndRender(
                            deltaTime: 1 / 60, cameraOutput: output,
                            onComplete: { _ in continuation.resume() }
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
            texture.getBytes(
                &pixels, bytesPerRow: 128 * 4,
                from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
            )
            return pixels
        }
        let original = try await pixels()
        let lights = renderer.cameraEntity.children.filter { $0.components[DirectionalLightComponent.self] != nil }
        XCTAssertFalse(lights.isEmpty)
        for light in lights {
            light.isEnabled = false
        }
        let unlitPixels = try await pixels()
        XCTAssertEqual(original, unlitPixels, "Path colors must not depend on scene lighting")
        for light in lights {
            light.isEnabled = true
        }
        func pixel(_ x: Int) -> ArraySlice<UInt8> {
            original[((64 * 128 + x) * 4) ..< ((64 * 128 + x) * 4 + 4)]
        }
        let left = Array(pixel(44)), middle = Array(pixel(64)), right = Array(pixel(84))
        XCTAssertGreaterThan(Int(left[0]) - Int(left[2]), 30, "\(left)")
        XCTAssertGreaterThan(Int(right[2]) - Int(right[0]), 30, "\(right)")
        XCTAssertGreaterThan(middle[0], 25, "\(middle)")
        XCTAssertGreaterThan(middle[2], 25, "\(middle)")
        XCTAssertLessThan(middle[1], 40, "\(middle)")
        renderer.select(scene.children.first)
        let selected = try await pixels()
        XCTAssertFalse(original == selected)
        renderer.select(scene.children.first)
        let repeated = try await pixels()
        XCTAssertTrue(selected == repeated)
        renderer.select(nil)
        let restored = try await pixels()
        XCTAssertLessThanOrEqual(zip(original, restored).map { abs(Int($0) - Int($1)) }.max() ?? 0, 1)

        let translucent = try evaluate(parse("""
        path {
            color 1 0 0 0.5
            point -1 0
            point 1 0
        }
        """), delegate: nil)
        XCTAssertTrue(translucent.build { false })
        await renderer.prepareAsync(translucent, options: options)
        renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 3], relativeTo: nil)
        let translucentPixels = try await pixels()
        let centerOffset: Int = (64 * 128 + 64) * 4
        let alpha = translucentPixels[centerOffset + 3]
        XCTAssertEqual(Double(alpha) / 255, 0.5, accuracy: 0.02)

        // Constant colors must look the same in synchronous and asynchronous conversion.
        let uniform = try evaluate(parse("""
        path {
            color 0.2 0.4 0.6 0.5
            point -1 0
            point 1 0
        }
        """), delegate: nil)
        XCTAssertTrue(uniform.build { false })
        func uniformReferences() throws -> [RealityKitEntityReference] {
            try uniform.realityKitEntityReferences(with: options)
        }
        let references = try uniformReferences()
        let nativeRoot = Entity()
        for reference in references {
            nativeRoot.addChild(reference.entity)
        }
        outputRenderer.entities.removeAll()
        outputRenderer.entities.append(nativeRoot)
        outputRenderer.entities.append(renderer.cameraEntity)
        let nativePixels = try await pixels()
        outputRenderer.entities.removeAll()
        outputRenderer.entities.append(renderer.realityKitView.rootEntity)
        await renderer.prepareAsync(uniform, options: options)
        renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 3], relativeTo: nil)
        let shaderPixels = try await pixels()
        for channel in 0 ..< 4 {
            XCTAssertEqual(
                Double(nativePixels[centerOffset + channel]),
                Double(shaderPixels[centerOffset + channel]), accuracy: 1
            )
        }
    }

    func testSelectionRayReachesDistantGeometry() {
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 128, height: 128))
        let root = AnchorEntity(world: .zero)
        let model = ModelEntity(mesh: .generateBox(size: 100))
        model.components.set(CollisionComponent(shapes: [.generateBox(size: [100, 100, 100])]))
        root.addChild(model)
        view.scene.addAnchor(root)
        let origin = SIMD3<Float>(0, 0, 300)
        let direction = SIMD3<Float>(0, 0, -1)
        XCTAssertTrue(view.scene.raycast(origin: origin, direction: direction).isEmpty)
        XCTAssertTrue(root.selectionTarget(origin: origin, direction: direction) === model)
        XCTAssertNil(root.selectionTarget(origin: origin, direction: [1, 0, 0]))
    }

    func testSelectionRestoresMaterialsAndDoesNotAccumulate() async throws {
        let renderer = RealityKitRenderer()
        let source = try String(
            contentsOf: testsDirectory.deletingLastPathComponent()
                .appendingPathComponent("Viewer/Shared/Untitled.shape"),
            encoding: .utf8
        )
        let scene = try evaluate(parse(source), delegate: nil)
        XCTAssertTrue(scene.build { false })
        await renderer.prepareAsync(scene, options: .default)
        let geometries = scene.children
        XCTAssertEqual(geometries.count, 3)
        let content = try XCTUnwrap(renderer.realityKitView.rootEntity.children.first)
        let entities = try content.children.map { try XCTUnwrap($0 as? ModelEntity) }
        XCTAssertEqual(entities.count, 3)
        func material(_ index: Int) throws -> PhysicallyBasedMaterial {
            try XCTUnwrap(entities[index].model?.materials.first as? PhysicallyBasedMaterial)
        }
        let originalTints = try entities.indices.map { try material($0).baseColor.tint }
        let originalEmission = try material(2).emissiveColor.color
        renderer.cameraEntity.look(at: [0, 0, 0], from: [0, 0, 5], relativeTo: nil)
        let outputRenderer = try RealityRenderer()
        outputRenderer.entities.append(renderer.realityKitView.rootEntity)
        outputRenderer.activeCamera = renderer.cameraEntity
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func pixels() async throws -> [UInt8] {
            for _ in 0 ..< 3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try outputRenderer.updateAndRender(
                            deltaTime: 1 / 60, cameraOutput: output,
                            onComplete: { _ in continuation.resume() }
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
            texture.getBytes(
                &pixels, bytesPerRow: 128 * 4,
                from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
            )
            return pixels
        }
        let originalPixels = try await pixels()
        for _ in 0 ..< 3 {
            renderer.select(geometries[1])
            let selectedTint = try material(1).baseColor.tint
            let selectedPixels = try await pixels()
            XCTAssertFalse(selectedPixels == originalPixels, "Selection must visibly highlight the object")
            renderer.select(geometries[1])
            let repeatedPixels = try await pixels()
            XCTAssertTrue(selectedPixels == repeatedPixels, "Repeated selection must not intensify the highlight")
            XCTAssertEqual(try material(1).baseColor.tint, selectedTint)
            XCTAssertEqual(try material(2).baseColor.tint, originalTints[2])
            renderer.select(geometries[2])
            XCTAssertEqual(try material(1).baseColor.tint, originalTints[1])
            XCTAssertEqual(try material(1).emissiveColor.color, originalEmission)
            let switchedPixels = try await pixels()
            renderer.select(nil)
            XCTAssertEqual(try material(2).baseColor.tint, originalTints[2])
            XCTAssertEqual(try material(2).emissiveColor.color, originalEmission)
            let clearedPixels = try await pixels()
            let differences = zip(originalPixels, clearedPixels).map { abs(Int($0) - Int($1)) }
            XCTAssertLessThanOrEqual(
                differences.max() ?? 0, 1,
                "Clearing selection must restore the rendered appearance"
            )
            renderer.select(geometries[2])
            let reselectedPixels = try await pixels()
            XCTAssertTrue(
                switchedPixels == reselectedPixels,
                "Switching selection must clear the previous object's highlight"
            )
            renderer.select(nil)
        }
    }

    func testAxesUseInterfaceColorForLinesAndLabels() throws {
        for color in [Euclid.Color.black, .white, .red, .init(red: 0.2, green: 0.4, blue: 0.6)] {
            func assertColor(_ tint: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
                let tint = try XCTUnwrap(tint.usingColorSpace(.sRGB), file: file, line: line)
                XCTAssertEqual(Double(tint.redComponent), color.red, accuracy: 0.000001, file: file, line: line)
                XCTAssertEqual(Double(tint.greenComponent), color.green, accuracy: 0.000001, file: file, line: line)
                XCTAssertEqual(Double(tint.blueComponent), color.blue, accuracy: 0.000001, file: file, line: line)
            }
            for scale in [0.5, 2.0] {
                let axes = Axes(scale: scale, camera: .default, color: color)
                XCTAssertEqual(SCNNode(axes).childNodes.count, 9)
                let lineWidth = scale * 0.005
                let entity = try Entity(axes, lineWidth: lineWidth)
                XCTAssertEqual(entity.children.count, 9)
                var lineCount = 0
                var labelCount = 0
                for (child, geometry) in zip(entity.children, axes.geometry.children) {
                    let model = try XCTUnwrap((child as? ModelEntity)?.model)
                    for material in model.materials {
                        let material = try XCTUnwrap(material as? UnlitMaterial)
                        try assertColor(material.color.tint)
                        if case .path = geometry.type {
                            lineCount += 1
                            let size = child.visualBounds(relativeTo: entity).extents
                            let dimensions = [size.x, size.y, size.z].sorted()
                            XCTAssertEqual(Double(dimensions[2]), scale * 2, accuracy: lineWidth)
                            XCTAssertGreaterThan(Double(dimensions[0]), lineWidth * 0.8)
                            XCTAssertLessThanOrEqual(Double(dimensions[1]), lineWidth * 1.01)
                        } else {
                            labelCount += 1
                        }
                    }
                }
                XCTAssertEqual(lineCount, 3)
                XCTAssertEqual(labelCount, 6)
            }
        }
    }

    func testDefaultLightingFollowsCameraAndMatchesSceneKitBrightness() async throws {
        let realityKit = RealityKitRenderer()
        let root = realityKit.realityKitView.rootEntity
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white)
        material.roughness = .init(floatLiteral: 0.5)
        material.specular = .init(floatLiteral: 0)
        let sphere = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        root.addChild(sphere)
        let renderer = try RealityRenderer()
        renderer.entities.append(root)
        renderer.activeCamera = realityKit.cameraEntity
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let reference = SCNRenderer(device: device, options: nil)
        let referenceScene = SCNScene()
        reference.scene = referenceScene
        reference.autoenablesDefaultLighting = true
        let referenceCamera = SCNNode()
        referenceCamera.camera = SCNCamera()
        referenceCamera.camera?.fieldOfView = 60
        referenceScene.rootNode.addChildNode(referenceCamera)
        reference.pointOfView = referenceCamera
        let referenceSphere = SCNNode(geometry: SCNSphere(radius: 1))
        referenceSphere.geometry?.firstMaterial?.lightingModel = .blinn
        referenceScene.rootNode.addChildNode(referenceSphere)
        for luminance in [0.25, 0.5, 0.75, 1.0] {
            let color = NSColor(red: luminance, green: luminance, blue: luminance, alpha: 1)
            material.baseColor = .init(tint: color)
            sphere.model?.materials = [material]
            referenceSphere.geometry?.firstMaterial?.diffuse.contents = color
            var centerBrightness = [UInt8]()
            for position: SIMD3<Float> in [[0, 0, 3], [3, 0, 0], [0, 3, 0.01]] {
                realityKit.cameraEntity.look(at: .zero, from: position, relativeTo: nil)
                for _ in 0 ..< 3 {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        do {
                            try renderer.updateAndRender(
                                deltaTime: 1 / 60, cameraOutput: output,
                                onComplete: { _ in continuation.resume() }
                            )
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
                texture.getBytes(
                    &pixels, bytesPerRow: 128 * 4,
                    from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
                )
                let center = pixels[(64 * 128 + 64) * 4]
                centerBrightness.append(center)
                referenceCamera.simdTransform = realityKit.cameraEntity.transform.matrix
                let image = reference.snapshot(
                    atTime: 0, with: CGSize(width: 128, height: 128), antialiasingMode: .multisampling4X
                )
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                // Compare encoded pixels directly; colorAt() introduces a calibrated-RGB conversion.
                for x in [64, 80, 95] {
                    var expected = [Int](repeating: 0, count: 4)
                    bitmap.getPixel(&expected, atX: x, y: 64)
                    let actual = pixels[(64 * 128 + x) * 4]
                    XCTAssertEqual(Double(actual), Double(expected[0]), accuracy: luminance == 1 ? 20 : 8)
                }
                let left = pixels[(64 * 128 + 40) * 4]
                let right = pixels[(64 * 128 + 88) * 4]
                XCTAssertEqual(Double(left), Double(right), accuracy: 15)
                XCTAssertGreaterThan(center, left)
            }
            let brightest = try XCTUnwrap(centerBrightness.max())
            let darkest = try XCTUnwrap(centerBrightness.min())
            XCTAssertLessThan(Int(brightest) - Int(darkest), 10)
        }
    }

    func testWindowCameraMatchesSceneKitAcrossViewsAndResizes() throws {
        let realityKit = RealityKitRenderer()
        let sceneKit = SceneKitRenderer()
        let bounds = Bounds(min: [-2, -1, -0.5], max: [4, 3, 2])
        for type in [CameraType.front, .left, .top] {
            for zUp in [false, true] {
                let camera = Viewer.Camera(type: type, zUp: zUp)
                for size in [CGSize(width: 800, height: 400), CGSize(width: 400, height: 800)] {
                    for showAxes in [false, true] {
                        sceneKit.view.frame.size = size
                        realityKit.updateViewportSize(size)
                        sceneKit.updateAxesAndCamera(
                            showAxes: showAxes, isQuickLook: false, camera: camera,
                            isOrthographic: false, visibleBounds: bounds, interfaceColor: .white
                        )
                        realityKit.updateAxesAndCamera(
                            showAxes: showAxes, isQuickLook: false, camera: camera,
                            isOrthographic: false, visibleBounds: bounds, interfaceColor: .white
                        )
                        let actual = realityKit.cameraEntity.transform.matrix
                        let expected = sceneKit.cameraNode.simdTransform
                        for column in 0 ..< 4 {
                            for row in 0 ..< 4 {
                                XCTAssertEqual(actual[column][row], expected[column][row], accuracy: 0.0001)
                            }
                        }
                        let projection = try XCTUnwrap(realityKit.cameraEntity
                            .components[PerspectiveCameraComponent.self])
                        XCTAssertEqual(
                            Double(projection.fieldOfViewInDegrees),
                            sceneKit.cameraNode.camera.map { Double($0.fieldOfView) }
                        )
                        XCTAssertNil(realityKit.cameraEntity.components[OrthographicCameraComponent.self])
                    }
                }
            }
        }
    }

    func testOrthographicCameraMatchesSceneKitScaleAndSwitchesBack() throws {
        let realityKit = RealityKitRenderer()
        let sceneKit = SceneKitRenderer()
        let size = CGSize(width: 600, height: 600)
        let bounds = Bounds(min: [-1, -1, -1], max: [1, 1, 1])
        sceneKit.view.frame.size = size
        realityKit.updateViewportSize(size)
        for orthographic in [true, false] {
            sceneKit.updateAxesAndCamera(
                showAxes: false, isQuickLook: false, camera: .default,
                isOrthographic: orthographic, visibleBounds: bounds, interfaceColor: .white
            )
            realityKit.updateAxesAndCamera(
                showAxes: false, isQuickLook: false, camera: .default,
                isOrthographic: orthographic, visibleBounds: bounds, interfaceColor: .white
            )
            if orthographic {
                let projection = try XCTUnwrap(realityKit.cameraEntity.components[OrthographicCameraComponent.self])
                let camera = try XCTUnwrap(sceneKit.cameraNode.camera)
                XCTAssertEqual(Double(projection.scale), 1 / Double(camera.projectionTransform.m22), accuracy: 0.0001)
                XCTAssertNil(realityKit.cameraEntity.components[PerspectiveCameraComponent.self])
            } else {
                XCTAssertNotNil(realityKit.cameraEntity.components[PerspectiveCameraComponent.self])
                XCTAssertNil(realityKit.cameraEntity.components[OrthographicCameraComponent.self])
            }
        }
    }

    func testRenderedOrthographicProjectionMatchesSceneKit() async throws {
        let realityKit = RealityKitRenderer()
        let sceneKit = SceneKitRenderer()
        let size = CGSize(width: 600, height: 600)
        let bounds = Bounds(min: [-1, -1, -1], max: [1, 1, 1])
        sceneKit.view.frame.size = size
        realityKit.updateViewportSize(size)
        let camera = Viewer.Camera(type: .front, zUp: false)
        sceneKit.updateAxesAndCamera(
            showAxes: false, isQuickLook: false, camera: camera,
            isOrthographic: true, visibleBounds: bounds, interfaceColor: .white
        )
        realityKit.updateAxesAndCamera(
            showAxes: false, isQuickLook: false, camera: camera,
            isOrthographic: true, visibleBounds: bounds, interfaceColor: .white
        )
        // Render offscreen: opening a RealityView window depends on the CI window server.
        let material = UnlitMaterial(color: .white)
        realityKit.realityKitView.rootEntity.addChild(ModelEntity(mesh: .generateBox(size: 1), materials: [material]))
        let outputRenderer = try RealityRenderer()
        outputRenderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        outputRenderer.entities.append(realityKit.realityKitView.rootEntity)
        outputRenderer.activeCamera = realityKit.cameraEntity
        let description = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 128, height: 128, mipmapped: false
        )
        description.usage = [.renderTarget, .shaderRead, .shaderWrite]
        description.storageMode = .shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        for _ in 0 ..< 3 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try outputRenderer.updateAndRender(
                        deltaTime: 1 / 60, cameraOutput: output,
                        onComplete: { _ in continuation.resume() }
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        texture.getBytes(
            &pixels, bytesPerRow: 128 * 4,
            from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0
        )
        let reference = SCNRenderer(device: device)
        reference.scene = sceneKit.scene
        reference.pointOfView = sceneKit.cameraNode
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        box.firstMaterial?.lightingModel = .constant
        box.firstMaterial?.diffuse.contents = NSColor.white
        sceneKit.scene.rootNode.addChildNode(SCNNode(geometry: box))
        let image = reference.snapshot(atTime: 0, with: CGSize(width: 128, height: 128), antialiasingMode: .none)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var actual = [Int](), expected = [Int]()
        for x in 0 ..< 128 {
            if pixels[(64 * 128 + x) * 4 + 3] > 127 { actual.append(x) }
            var pixel = [Int](repeating: 0, count: 4)
            bitmap.getPixel(&pixel, atX: x, y: 64)
            if pixel[3] > 127 { expected.append(x) }
        }
        XCTAssertFalse(actual.isEmpty)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertLessThan(actual.count, 128)
        XCTAssertEqual(try XCTUnwrap(actual.first), try XCTUnwrap(expected.first), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(actual.last), try XCTUnwrap(expected.last), accuracy: 1)
    }
}

#endif
