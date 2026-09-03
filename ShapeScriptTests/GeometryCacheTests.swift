//
//  GeometryCacheTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 03/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import Foundation
import XCTest

final class GeometryCacheTests: XCTestCase {
    // MARK: Sub-object caching

    func testFilledCharacterCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        fill text "Hello World"    
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        #if canImport(CoreText)
        // Cache should have only 8 entries as the 'o' and 'l' are repeated
        XCTAssertEqual(cache.count, 8)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 1)
        #endif
    }

    func testExtrudedCharacterCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        extrude text "Hello World"    
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        #if canImport(CoreText)
        // Cache should have only 8 entries as the 'o' and 'l' are repeated
        XCTAssertEqual(cache.count, 8)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 1)
        #endif
    }

    // MARK: Material caching

    func testHullColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along circle
                }
            }
        }
        thing { color red }
        thing { color blue }    
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 2 entries: the extrusion and the hull
        XCTAssertEqual(cache.count, 2)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Meshes should not have baked materials, as they are recolorable
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching2() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along circle
                }
                cube { color blue }
            }
        }
        thing { color red }
        thing { color blue }    
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have 4 entries: cube, extrusion, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // First mesh has a mix of colors, so these are baked into the vertices
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        // Second mesh is uniformly blue, so shouldn't have any baked material
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
    }

    func testHullColorCaching3() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color red
                        curve 0 1 0.75
                        curve -1 0
                        color green
                        curve 0 -1 0.25
                        curve 1 0
                        color blue
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color blue }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have 4 entries: extrusion1, extrusion2, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Meshes both have non-uniform vertex colors so material color must be baked
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.last?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching4() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color red
                        curve 0 1 0.75
                        curve -1 0
                        color green
                        curve 0 -1 0.25
                        curve 1 0
                        color blue
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 2 entries: extrusion and hull
        XCTAssertEqual(cache.count, 2)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though meshes have non-uniform vertex colors, override color is same for both so cache hits
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching5() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color rnd rnd rnd
                        curve 0 1 0.75
                        curve -1 0
                        color rnd rnd rnd
                        curve 0 -1 0.25
                        curve 1 0
                        color rnd rnd rnd
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have 4 entries: extrusion1, extrusion2, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though override colors are the same, each mesh has different random vertex colors
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.materials, meshes.last?.materials)
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
    }

    func testExtrusionColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            extrude {
                path {
                    orientation 0 0 -0.4
                    curve 0 1 0.75
                    curve -1 0
                    curve 0 -1 0.25
                    curve 1 0
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 1 entry: path
        XCTAssertEqual(cache.count, 1)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testTwistedExtrusionColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            extrude {
                square { color blue }
                twist 1
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 1 entry: extrude
        XCTAssertEqual(cache.count, 1)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
        // Geometries are not recolored
        XCTAssertEqual(scene.children.first?.material, Material(color: .blue))
        XCTAssertEqual(scene.children.last?.material, Material(color: .blue))
    }

    func testMinkowskiColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            minkowski {
                sphere {
                    size 0.05
                }
                path {
                    orientation 0 0 -0.4
                    curve 0 1 0.75
                    curve -1 0
                    curve 0 -1 0.25
                    curve 1 0
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 3 entries: sphere, path, minkowski
        XCTAssertEqual(cache.count, 3)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testMinkowskiColorCaching2() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            minkowski {
                sphere {
                    size 0.05
                }
                path {
                    orientation 0 0 -0.4
                    color rnd rnd rnd
                    curve 0 1 0.75
                    curve -1 0
                    color rnd rnd rnd
                    curve 0 -1 0.25
                    curve 1 0
                    color rnd rnd rnd
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have 5 entries: sphere, path1, path2, minkowski1, minkowski2
        XCTAssertEqual(cache.count, 5)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though override colors are the same, each mesh has different random vertex colors
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.materials, meshes.last?.materials)
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
    }
}
