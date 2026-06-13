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
            isOpaque: false
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
        XCTAssertFalse(transparent.writesToDepthBuffer)
        XCTAssertFalse(textured.writesToDepthBuffer)
        XCTAssertEqual(transparent.transparencyMode, .dualLayer)
    }
}

#endif
