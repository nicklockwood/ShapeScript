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
            Material(color: Color.red.withAlpha(0.5)),
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

    func testSceneBuildDisablesDepthBufferWritesForOverlappingTransparentGeometry() throws {
        let transparent = cube(material: Material(color: Color.red.withAlpha(0.5)))
        let opaque = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [transparent, opaque], cache: nil)

        XCTAssertTrue(scene.build { true })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertFalse(material.writesToDepthBuffer)
    }

    func testSceneBuildPreservesDepthBufferWritesForSeparateTransparentGeometry() throws {
        let transparent = cube(
            transform: .translation(.init(2, 0, 0)),
            material: Material(color: Color.red.withAlpha(0.5))
        )
        let opaque = cube(material: Material(color: .blue))
        let scene = Scene(background: .color(.clear), children: [transparent, opaque], cache: nil)

        XCTAssertTrue(scene.build { true })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertTrue(material.writesToDepthBuffer)
    }

    func testSceneBuildUsesNestedTransformsForTransparentGeometryOverlap() throws {
        let transparent = cube(
            transform: .translation(.init(1, 0, 0)),
            material: Material(color: Color.red.withAlpha(0.5))
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

        XCTAssertTrue(scene.build { true })
        scene.scnBuild(with: .default)

        let material = try XCTUnwrap(transparent.scnGeometry.materials.first)
        XCTAssertFalse(material.writesToDepthBuffer)
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
        XCTAssertTrue(scene.build { true })
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
}

#endif
