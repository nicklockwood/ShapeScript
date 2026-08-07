//
//  PlatformTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 07/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest

#if canImport(UIKit) || canImport(AppKit)

import CoreGraphics
import ImageIO
import SceneKit

final class PlatformTests: XCTestCase {
    // MARK: Texture conversion

    func testTextureToImage() throws {
        let file = testsDirectory.appendingPathComponent("Stars1.jpg")
        let input = try XCTUnwrap(OSImage(contentsOfFile: file.path))
        let texture = try XCTUnwrap(Texture(input))
        let output = try XCTUnwrap(OSImage(texture))
        XCTAssertEqual(input.size, output.size)
    }

    // MARK: SceneKit conversion

    func testMaterialDepthBufferWrites() {
        let opaque = SCNMaterial(Material(color: .red), isOpaque: true)
        let opaqueWithinTransparentGeometry = SCNMaterial(
            Material(color: .red),
            isOpaque: false,
            writesToDepthBuffer: false
        )
        let transparent = SCNMaterial(
            Material(color: .red.withAlphaComponent(0.5)),
            isOpaque: false
        )
        var texturedMaterial = Material.default
        texturedMaterial.opacity = .texture(.data(Data()))
        let textured = SCNMaterial(
            texturedMaterial,
            isOpaque: false
        )

        XCTAssertTrue(opaque.writesToDepthBuffer)
        XCTAssertFalse(opaqueWithinTransparentGeometry.writesToDepthBuffer)
        XCTAssertTrue(transparent.writesToDepthBuffer)
        XCTAssertTrue(textured.writesToDepthBuffer)
        XCTAssertEqual(transparent.transparencyMode, .dualLayer)
    }

    func testOpacityTextureUsesAlphaChannelWhenAvailable() throws {
        let data = try pngData(pixels: [
            .init(red: 255, green: 255, blue: 255, alpha: 0),
            .init(red: 0, green: 0, blue: 0, alpha: 255),
        ])
        var material = Material.default
        material.opacity = .texture(.data(data))

        let scnMaterial = SCNMaterial(material, isOpaque: material.isOpaque)

        XCTAssertFalse(material.isOpaque)
        XCTAssertEqual(scnMaterial.transparent.contents as? Data, data)
    }

    func testOpacityTextureUsesLuminanceWhenAlphaIsFullyOpaque() throws {
        let data = try pngData(pixels: [
            .init(red: 255, green: 255, blue: 255, alpha: 255),
            .init(red: 0, green: 0, blue: 0, alpha: 255),
        ])
        let texture = Texture.data(data)
        var material = Material.default
        material.opacity = .texture(texture)

        let scnMaterial = SCNMaterial(material, isOpaque: material.isOpaque)
        let maskData = try XCTUnwrap(scnMaterial.transparent.contents as? Data)

        XCTAssertFalse(material.isOpaque)
        XCTAssertEqual(material.opacity?.averageOpacity ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(material.opacity?.averageLuminance ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(material.averageOpacity, 0.5, accuracy: 0.01)
        XCTAssertEqual(texture.averageOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(texture.averageLuminance, 0.5, accuracy: 0.01)
        XCTAssertNotEqual(maskData, data)
        XCTAssertEqual(Texture.data(maskData).averageOpacity, 0.5, accuracy: 0.01)
    }

    func testOpaqueAlbedoTextureDoesNotAffectMaterialOpacity() throws {
        let data = try pngData(pixels: [
            .init(red: 16, green: 16, blue: 16, alpha: 255),
        ])
        var material = Material.default
        material.albedo = .texture(.data(data))

        XCTAssertTrue(material.isOpaque)
        XCTAssertTrue(material.isVisible)
    }

    func testSceneBuildPreservesDepthWritesForOpaquePlanarTexturedGeometry() throws {
        let data = try pngData(pixels: [
            .init(red: 16, green: 16, blue: 16, alpha: 255),
        ])
        var material = Material.default
        material.albedo = .texture(.data(data))
        let textured = Geometry(
            type: .mesh(Mesh.fill(Path.rectangle(width: 1, height: 1))),
            name: nil,
            transform: .identity,
            material: material,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
        let opaque = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [textured, opaque], cache: nil)

        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)

        let scnMaterial: SCNMaterial = try XCTUnwrap(textured.scnGeometry.materials.first)
        XCTAssertTrue(textured.isOpaque)
        XCTAssertTrue(scnMaterial.writesToDepthBuffer)
    }

    func testTextureAverageColor() throws {
        let data = try pngData(pixels: [
            .init(red: 255, green: 0, blue: 0, alpha: 255),
        ])
        let color = try XCTUnwrap(Texture.data(data).averageColor)

        XCTAssertEqual(color.red, 1, accuracy: 0.01)
        XCTAssertEqual(color.green, 0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 1, accuracy: 0.01)
    }

    func testSceneBuildDisablesDepthBufferWritesForOverlappingTransparentGeometry() throws {
        let transparent = cube(material: Material(color: .red.withAlphaComponent(0.5)))
        let opaque = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [transparent, opaque], cache: nil)

        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertFalse(material.writesToDepthBuffer)
    }

    func testSceneBuildPreservesDepthBufferWritesForSeparateTransparentGeometry() throws {
        let transparent = cube(
            transform: .translation(.init(2, 0, 0)),
            material: Material(color: .red.withAlphaComponent(0.5))
        )
        let opaque = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [transparent, opaque], cache: nil)

        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertTrue(material.writesToDepthBuffer)
    }

    func testSceneBuildUsesNestedTransformsForTransparentGeometryOverlap() throws {
        let transparent = cube(
            transform: .translation(.init(1, 0, 0)),
            material: Material(color: .red.withAlphaComponent(0.5))
        )
        let group = Geometry(
            type: .group,
            name: nil,
            transform: .translation(.init(2, 0, 0)),
            material: .default,
            smoothing: nil,
            children: [transparent],
            sourceLocation: nil
        )
        let opaque = cube(
            transform: .translation(.init(3, 0, 0)),
            material: Material(color: .blue)
        )
        let scene = Scene(background: .color(.clear), children: [group, opaque], cache: nil)

        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertFalse(material.writesToDepthBuffer)
    }

    func testSceneBuildOnlyRendersFocusedGeometry() {
        let hidden = cube(material: Material(color: .red))
        let focused = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [hidden, focused], cache: nil)

        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)
        XCTAssertGreaterThan(hidden.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)

        focused.isFocused = true
        scene.scnBuild(with: .default)

        XCTAssertEqual(hidden.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)
        XCTAssertGreaterThan(focused.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)
    }

    func testSceneBuildRendersFocusedGeometryInsideCSGContainers() throws {
        for container in ["union", "difference"] {
            let scene = try evaluate(parse("""
            \(container) {
                focus cube {
                    position -1
                }
                cube {
                    position 1
                }
            }
            """), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            let focused = try XCTUnwrap(geometry.children.first)
            let hidden = try XCTUnwrap(geometry.children.last)

            XCTAssertTrue(scene.build { false })
            scene.scnBuild(with: .default)

            XCTAssertEqual(geometry.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)
            XCTAssertGreaterThan(focused.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)
            XCTAssertEqual(hidden.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0, 0)

            let node = SCNNode(geometry)
            XCTAssertEqual(node.childNodes.count, 2)
        }
    }

    func testSceneBuildRendersSelfIntersectingFilledPath() throws {
        let scene = try evaluate(parse("""
        fill path {
            curve 0
            curve 1
            curve 0 2
            curve 1 2
            curve 0
        }
        """), delegate: nil)
        XCTAssertTrue(scene.build { false })
        scene.scnBuild(with: .default)

        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertGreaterThan(try XCTUnwrap(geometry.mesh).polygons.count, 0)
        XCTAssertGreaterThan(
            geometry.scnGeometry.sources(for: .vertex).first?.vectorCount ?? 0,
            0
        )
        XCTAssertGreaterThan(
            geometry.scnGeometry.sources(for: .normal).first?.vectorCount ?? 0,
            0
        )
    }

    private func cube(
        transform: Transform = .identity,
        material: Material
    ) -> Geometry {
        Geometry(
            type: .cube,
            name: nil,
            transform: transform,
            material: material,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
    }

    private struct Pixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    private func pngData(pixels: [Pixel]) throws -> Data {
        var components = pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] }
        let width = pixels.count
        let height = 1
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let context = try XCTUnwrap(CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

#endif
