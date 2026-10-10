//
//  MaterialTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 12/10/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import ShapeScript
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
}
