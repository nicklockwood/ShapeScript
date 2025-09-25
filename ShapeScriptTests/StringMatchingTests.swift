//
//  StringMatchingTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 16/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

final class StringMatchingTests: XCTestCase {
    // MARK: Edit distance

    func testEditDistance() {
        XCTAssertEqual("foo".editDistance(from: "fob"), 1)
        XCTAssertEqual("foo".editDistance(from: "boo"), 1)
        XCTAssertEqual("foo".editDistance(from: "bar"), 3)
        XCTAssertEqual("aba".editDistance(from: "bbb"), 2)
        XCTAssertEqual("foob".editDistance(from: "foo"), 1)
        XCTAssertEqual("foo".editDistance(from: "foob"), 1)
        XCTAssertEqual("foo".editDistance(from: "Foo"), 1)
        XCTAssertEqual("FOO".editDistance(from: "foo"), 3)
    }

    func testEditDistanceWithEmptyStrings() {
        XCTAssertEqual("foo".editDistance(from: ""), 3)
        XCTAssertEqual("".editDistance(from: "foo"), 3)
        XCTAssertEqual("".editDistance(from: ""), 0)
    }
}
