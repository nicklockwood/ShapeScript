//
//  ImportExportTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 19/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

#if canImport(SceneKit)
import SceneKit
#endif

class ImportExportTests: XCTestCase {
    // MARK: Geometry

    func testCog() throws {
        let source = """
        define cog {
            option teeth 6
            path {
                define step 1 / teeth
                for 1 to teeth {
                    point -0.02 0.8
                    point 0.05 1
                    rotate step
                    point -0.05 1
                    point 0.02 0.8
                    rotate step
                }
                point -0.02 0.8
            }
        }

        difference {
            extrude {
                size 1 1 0.5
                cog { teeth 8 }
            }
            rotate 0 0 0.5
            cylinder
        }
        """
        let program = try parse(source)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.children.first?.value as? Geometry)
        XCTAssert(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        let polygons = mesh.polygons
        XCTAssertEqual(polygons.count, 80)
        XCTAssert(polygons.areWatertight)
        let triangles = mesh.triangulate().polygons
        XCTAssertEqual(triangles.count, 256)
        XCTAssert(triangles.areWatertight)

        #if canImport(SceneKit)
        geometry.scnBuild(with: .default)
        let node = SCNNode(geometry)
        let geometry2 = try Geometry(node)
        XCTAssert(geometry2.build { true })
        let mesh2 = try XCTUnwrap(geometry2.mesh)
        XCTAssertEqual(mesh2.polygons.count, 256)
        XCTAssert(mesh2.isWatertight)
        #endif
    }

    // MARK: JSON

    func testParseJSONValues() throws {
        let source = """
        [
            "hello",
            3,
            3.5,
            true,
            null,
            [1, 2, 3],
            {
                "foo": 2,
                "bar": true,
            }
        ]
        """
        let json = try JSONSerialization
            .jsonObject(with: source.data(using: .utf8)!)
        let value = Value(json: json)
        XCTAssertEqual(value, [
            "hello",
            3,
            3.5,
            true,
            [],
            [1, 2, 3],
            [
                "bar": true,
                "foo": 2,
            ],
        ])
        XCTAssertEqual(value["seventh"]?["foo"], 2)
    }

    func testMalformedJSON() throws {
        let json = """
        [
            "🙃,
            "foo"
        ]
        """
        XCTAssertThrowsError(try Value(jsonData: json.data(using: .utf8)!)) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            guard case let .custom(message, _, range)? = error?.type else {
                XCTFail()
                return
            }
            if let range = range {
                XCTAssertEqual(message, "Unescaped control character")
                XCTAssertEqual(range.lowerBound, json.range(of: "🙃,")?.upperBound)
            } else {
                XCTAssert(message.hasPrefix("Unescaped control character") ||
                    message.hasPrefix("Badly formed array"))
            }
        }
    }
}
