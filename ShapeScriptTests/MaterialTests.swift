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

final class MaterialTests: XCTestCase {
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
}
