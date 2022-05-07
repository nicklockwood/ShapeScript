//
//  PlatformTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 07/05/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

#if canImport(UIKit) || canImport(AppKit)

private let testsDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()

class PlatformTests: XCTestCase {
    // MARK: Texture conversion

    func testTextureToImage() throws {
        let file = testsDirectory.appendingPathComponent("Stars1.jpg")
        let input = try XCTUnwrap(OSImage(contentsOfFile: file.path))
        let texture = try XCTUnwrap(Texture(input))
        let output = try XCTUnwrap(OSImage(texture))
        XCTAssertEqual(input.size, output.size)
    }
}

#endif
