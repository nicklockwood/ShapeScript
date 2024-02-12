//
//  SVGPathTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 18/02/2024.
//  Copyright © 2024 Nick Lockwood. All rights reserved.
//

import Euclid
import ShapeScript
import SVGPath
import XCTest

class SVGPathTests: XCTestCase {
    func testNoCrashWithEmptyPath() {
        XCTAssertEqual(SVGPath(Path.empty), SVGPath(commands: []))
    }
}
