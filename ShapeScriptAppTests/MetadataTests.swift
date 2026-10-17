//
//  MetadataTests.swift
//  ShapeScriptAppTests
//
//  Created by Nick Lockwood on 08/09/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

@testable import Viewer
import XCTest

@MainActor
final class MetadataTests: XCTestCase {
    // MARK: What's New

    func testWhatsNew() throws {
        #if os(iOS)
        let whatsNew = try loadRTF("WhatsNew").string
        #else
        let whatsNew = loadRTF("WhatsNew").string
        #endif
        let version = appVersion
        XCTAssertNotNil(whatsNew.range(of: "ShapeScript \(version)"))
    }
}
