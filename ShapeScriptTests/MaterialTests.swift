//
//  MaterialTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 12/10/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest
#if canImport(SceneKit)
import ImageIO
import SceneKit
#endif

final class MaterialTests: XCTestCase {
    func testRelativeLuminanceAndDataChannelsUseDifferentConventions() {
        let gray = Color(white: 0.5)
        XCTAssertEqual(gray.luminance(over: .black), 0.21404114048223255, accuracy: 1e-12)
        XCTAssertEqual(MaterialProperty.color(gray).averageLuminance, 0.5, accuracy: 1e-12)
        XCTAssertEqual(MaterialProperty.color(gray).averageOpacity, 1)
        XCTAssertEqual(
            gray.withAlphaComponent(0.5).composited(over: .black).red,
            0.3607802138332792,
            accuracy: 1e-12
        )
    }

    func testLuminanceOverOpaqueBackground() {
        let color = Color.red.withAlphaComponent(0.5)
        XCTAssertEqual(color.luminance(over: .blue), (0.2126 + 0.0722) / 2, accuracy: 0.000001)
    }

    func testLuminanceOverTransparentBackground() {
        let color = Color.red.withAlphaComponent(0.5)
        XCTAssertEqual(color.luminance(over: .blue.withAlphaComponent(0)), 0.2126, accuracy: 0.000001)
    }

    func testLuminanceOfTransparentColors() {
        XCTAssertEqual(Color.red.withAlphaComponent(0).luminance(over: .clear), 0)
    }

    func testMaterialLuminanceOverTranslucentBackground() {
        let material = MaterialProperty.color(.red.withAlphaComponent(0.5))
        XCTAssertEqual(
            material.averageLuminance(over: .blue.withAlphaComponent(0.5)),
            (0.2126 * 2 + 0.0722) / 3,
            accuracy: 0.000001
        )
    }

    func testOverridesReplacePaintAlphaAndMultiplySeparateOpacity() {
        var source = Material(color: .red.withAlphaComponent(0.2))
        source.opacity = .color(Color(white: 0.5))
        source.roughness = .color(Color(white: 0.7))
        var override = Material(color: .blue)
        override.opacity = .color(Color(white: 0.25))
        let result = source.withOverrides(override)
        XCTAssertEqual(result.color, .blue)
        XCTAssertEqual(result.opacityPropertyAverageOpacity, 0.125, accuracy: 1e-8)
        XCTAssertEqual(result.roughness, source.roughness)
        override.albedo = nil
        let faded = source.withOverrides(override)
        XCTAssertEqual(faded.color, source.color)
        XCTAssertEqual(faded.averageOpacity, 0.025, accuracy: 1e-8)
        let unchanged = source.withOverrides(.default)
        XCTAssertEqual(unchanged, source)
    }

    func testTextureOverrideReplacesSourcePaintButRetainsSeparateOpacity() {
        var source = Material(color: .red.withAlphaComponent(0.2))
        source.opacity = .color(Color(white: 0.5, alpha: 0.5))
        let texture = Texture.data(Data())
        var override = Material.default
        override.albedo = .texture(texture)
        let result = source.withOverrides(override)
        XCTAssertEqual(result.texture, texture)
        XCTAssertNil(result.color)
        XCTAssertEqual(result.opacity, source.opacity)
    }

    #if canImport(SceneKit)
    func testSceneKitImportCombinesOpacityFactors() throws {
        let source = SCNMaterial()
        source.diffuse.contents = OSColor(Color.red.withAlphaComponent(0.25))
        source.transparent.contents = OSColor(Color.white.withAlphaComponent(0.5))
        source.transparent.intensity = 0.5
        source.transparency = 0.5
        let material = try XCTUnwrap(Material(source))
        XCTAssertEqual(material.averageOpacity, 0.03125, accuracy: 1e-6)
        XCTAssertEqual(source.transparency, 0.5)
        XCTAssertEqual(source.transparent.intensity, 0.5)
    }

    func testSceneKitImportPreservesScalarTransparencyWithDefaultMask() throws {
        let source = SCNMaterial()
        source.transparency = 0.25
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 0.25, accuracy: 1e-6)
    }

    func testSceneKitImportScalesColorInLinearLightAndDataWithoutGamma() throws {
        let source = SCNMaterial()
        source.diffuse.contents = OSColor.white
        source.diffuse.intensity = 0.5
        source.lightingModel = .physicallyBased
        source.roughness.contents = 0.5
        source.roughness.intensity = 0.5
        let material = try XCTUnwrap(Material(source))
        XCTAssertEqual(try XCTUnwrap(material.color).red, Color(white: 0.5).toSRGB().red, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(material.roughness?.color).red, 0.25, accuracy: 1e-6)
        XCTAssertEqual(material.averageOpacity, 1, accuracy: 1e-6)
    }

    func testSceneKitImportRGBZeroIgnoresAlphaAndInvertsLuminance() throws {
        let source = SCNMaterial()
        source.transparencyMode = .rgbZero
        source.transparent.contents = OSColor.white
        source.transparent.intensity = 0.25
        source.transparency = 0.5
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 0.875, accuracy: 1e-6)
        source.transparent.contents = OSColor(Color(white: 0.5, alpha: 0.1))
        source.transparent.intensity = 1
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 0.75, accuracy: 1e-6)
        source.transparent.contents = OSColor.black
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 1, accuracy: 1e-6)
    }

    func testSceneKitImportTextureMaskUsesExplicitChannel() throws {
        let bytes: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(try CGImage(
            width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        var grayscaleMask = Material.default
        grayscaleMask.opacity = .texture(.data(data as Data, intensity: 0.25))
        XCTAssertEqual(grayscaleMask.averageOpacity, 0.125, accuracy: 1e-6)
        let source = SCNMaterial()
        source.transparent.contents = image
        source.transparencyMode = .aOne
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 1, accuracy: 1e-6)
        source.transparency = 0.5
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 0.5, accuracy: 1e-6)
        source.transparency = 1
        source.transparencyMode = .rgbZero
        XCTAssertEqual(try XCTUnwrap(Material(source)).averageOpacity, 0.5, accuracy: 1e-6)
    }

    func testSceneKitImportStringTexturePathsAndRGBOnlyDiffuse() throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data([64, 64, 64, 64]) as CFData))
        let image = try XCTUnwrap(try CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " mask.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        for path in [url.path, url.absoluteString] {
            let source = SCNMaterial()
            source.diffuse.contents = path
            source.diffuse.textureComponents = [.red, .green, .blue]
            source.transparent.contents = path
            source.transparent.textureComponents = .alpha
            let material = try XCTUnwrap(Material(source))
            let texture = try XCTUnwrap(material.texture)
            XCTAssertEqual(texture.averageOpacity, 1, accuracy: 1e-6)
            XCTAssertEqual(try XCTUnwrap(texture.averageColor).red, 1, accuracy: 1e-6)
            XCTAssertEqual(material.averageOpacity, 64 / 255.0, accuracy: 1e-6)
            XCTAssertEqual(source.diffuse.textureComponents, [.red, .green, .blue])
        }
    }

    func testModelTexturesUseDocumentResourceResolver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mask.png")
        let data = Data([1, 2, 3])
        try data.write(to: url)
        let material = SCNMaterial()
        material.diffuse.contents = "mask.png"
        material.transparent.contents = url
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        node.geometry?.materials = [material]
        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: "", delegate: delegate)
        try context.resolveTextures(in: node, relativeTo: directory.appendingPathComponent("model.usda"))
        XCTAssertEqual(Set(delegate.imports), [url.path])
        XCTAssertEqual(material.diffuse.contents as? Data, data)
        XCTAssertEqual(material.transparent.contents as? Data, data)
    }

    func testModelTexturePermissionFailureIsNotSilentlyDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mask.png")
        try Data([1, 2, 3]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        guard !FileManager.default.isReadableFile(atPath: url.path) else {
            throw XCTSkip("This environment can read files without read permission")
        }
        let material = SCNMaterial()
        material.transparent.contents = url.path
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        node.geometry?.materials = [material]
        let context = EvaluationContext(source: "", delegate: nil)
        XCTAssertThrowsError(try context.resolveTextures(
            in: node,
            relativeTo: directory.appendingPathComponent("model.usda")
        )) { error in
            guard case let RuntimeErrorType.fileAccessRestricted(_, parent) = error else {
                return XCTFail("Expected texture access error, got \(error)")
            }
            XCTAssertEqual(parent.path, directory.path)
        }
        XCTAssertEqual(material.transparent.contents as? String, url.path)
    }

    func testSceneKitImportPreservesNodeOpacityWithoutMaterials() throws {
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        node.geometry?.materials = []
        node.opacity = 0.25
        let imported = try Geometry(node)
        guard case let .mesh(mesh) = imported.type else { return XCTFail("Expected mesh") }
        let material = try XCTUnwrap(mesh.polygons.first?.material as? Material)
        XCTAssertEqual(material.averageOpacity, 0.25, accuracy: 1e-6)
    }

    func testSceneKitImportAccumulatesNodeOpacity() throws {
        let root = SCNNode()
        root.opacity = 0.5
        let child = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        child.opacity = 0.5
        let material = SCNMaterial()
        material.transparency = 0.5
        child.geometry?.materials = [material]
        root.addChildNode(child)
        let scene = SCNScene()
        scene.rootNode.addChildNode(root)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".scn")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(scene.write(to: url, options: nil, delegate: nil, progressHandler: nil))
        let loaded = try SCNScene(url: url)
        let imported = try Geometry(XCTUnwrap(loaded.rootNode.childNodes.first))
        guard case let .mesh(mesh) = imported.children.first?.type else {
            return XCTFail("Expected imported mesh")
        }
        let result = try XCTUnwrap(mesh.polygons.first?.material as? Material)
        XCTAssertEqual(result.averageOpacity, 0.125, accuracy: 1e-6)
        XCTAssertEqual(child.opacity, 0.5)
        XCTAssertEqual(material.transparency, 0.5)
    }
    #endif
}
