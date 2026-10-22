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
    private var temporaryCacheDirectories: [URL] = []
    private let alwaysStoreDiskPolicy = GeometryCache.DiskWritePolicy { _ in -.infinity }
    private let neverStoreDiskPolicy = GeometryCache.DiskWritePolicy { _ in .greatestFiniteMagnitude }

    override func tearDown() {
        temporaryCacheDirectories.forEach(removeTemporaryCacheDirectory)
        temporaryCacheDirectories.removeAll()
        super.tearDown()
    }

    private func makeCache(
        directory: URL? = nil,
        diskWritePolicy: GeometryCache.DiskWritePolicy? = nil
    ) -> GeometryCache {
        let diskCache = directory.map(makeDiskCache)
        return makeCache(
            diskCache: diskCache,
            diskWritePolicy: diskWritePolicy ?? neverStoreDiskPolicy
        )
    }

    private func makeCache(
        diskCache: DiskCache?,
        diskWritePolicy: GeometryCache.DiskWritePolicy? = nil
    ) -> GeometryCache {
        .init(
            diskCache: diskCache,
            diskWritePolicy: diskWritePolicy ?? neverStoreDiskPolicy
        )
    }

    private func makeDiskCache(directory: URL) -> DiskCache {
        .init(
            capacity: DiskCache.defaultCapacity,
            directory: directory
        )
    }

    private func makeTemporaryCacheDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func removeTemporaryCacheDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func testBoundsBuildsPopulateCacheDuringEvaluation() throws {
        let cache = makeCache()
        let source = """
        define model {
            difference {
                cube { size 2 }
                sphere
            }
        }
        define dimensions model.bounds.size
        model
        """
        let scene = try evaluate(parse(source), delegate: nil, cache: cache)
        // No Scene.build call: the bounds query must populate the shared cache itself.
        XCTAssertGreaterThan(cache.count, 0)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.cache === cache)
        XCTAssertNotNil(cache[mesh: geometry])
        XCTAssertTrue(geometry.transformed(by: .translation([1, 2, 3])).cache === cache)
        XCTAssertTrue(geometry.with(transform: .identity, material: .default, smoothing: nil, sourceLocation: { nil })
            .cache === cache)
    }

    func testImportedBoundsUseEvaluationCache() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, content, importStatement) in [
            ("model.shape", "define model { difference { cube\nsphere } }", "import "),
            ("model.csg", "difference() { cube(1); sphere(r=0.5); }", "define model import "),
        ] {
            let url = directory.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let source = importStatement + "\"\(url.path)\"\ncube { size model.bounds.size }"
            let cache = makeCache()
            _ = try evaluate(parse(source), delegate: nil, cache: cache)
            XCTAssertGreaterThan(cache.count, 0, name)
        }
    }

    func testBoundsDuringEvaluationReuseDiskAndMemoryCache() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }
        let definition = """
        define model {
            difference {
                cube { size 2 }
                sphere
            }
        }
        """
        let uncached = try evaluate(parse(definition + "\nmodel"), delegate: nil, cache: nil)
        let geometry = try XCTUnwrap(uncached.children.first)
        XCTAssertNil(geometry.cache)
        // Distinct bounds prove the query reads the cached mesh rather than rebuilding.
        let cachedMesh = Mesh.cube(size: [7, 8, 9])
        let diskCache = LRUDiskCache<GeometryCache.Key, Data>(
            capacity: DiskCache.defaultCapacity, directory: directory
        )
        try diskCache.setValue(JSONEncoder().encode(CachedMesh(cachedMesh)), forKey: geometry.cacheKey)
        let cache = makeCache(directory: directory)
        let program = try parse(definition + "\ncube { size model.bounds.size }")
        XCTAssertEqual(cache.count, 0)
        for _ in 0 ..< 2 {
            let scene = try evaluate(program, delegate: nil, cache: cache)
            let cube = try XCTUnwrap(scene.children.first)
            XCTAssertEqual(cube.exactBounds(with: cube.transform).size, [7, 8, 9])
            XCTAssertGreaterThan(cache.count, 0)
        }
    }

    // MARK: Sub-object caching

    func testFilledCharacterCaching() throws {
        let cache = makeCache()
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
        let cache = makeCache()
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

    // MARK: Disk caching

    func testGeometryCachePersistsMeshesBetweenInstances() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("""
        detail 64
        sphere
        """)
        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(program, delegate: nil, cache: cache)
        _ = scene.build { false }
        cache.flushPendingDiskWrites()
        let mesh = try XCTUnwrap(scene.children.first?.mesh)
        XCTAssertGreaterThan(cache.count, 0)

        let restoredCache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        XCTAssertEqual(restoredCache.count, 0)
        let restoredScene = try evaluate(program, delegate: nil, cache: restoredCache)
        _ = restoredScene.build { false }
        let restoredMesh = try XCTUnwrap(restoredScene.children.first?.mesh)
        XCTAssertEqual(restoredMesh.polygons.count, mesh.polygons.count)
        XCTAssertGreaterThan(restoredCache.count, 0)
    }

    func testDocumentLoadFindsFinalMeshWrittenAfterCacheWasCreated() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }
        let reader = makeCache(directory: directory)
        let writer = makeCache(directory: directory, diskWritePolicy: alwaysStoreDiskPolicy)
        let program = try parse("""
        difference {
            cube
            sphere { size 1.2 }
        }
        """)
        let scene = try evaluate(program, delegate: nil, cache: writer)
        XCTAssertTrue(scene.build { false })
        writer.flushPendingDiskWrites()
        let expectedMesh = try XCTUnwrap(scene.children.first?.mesh)

        try reader.withRefresh(false) {
            let loaded = try evaluate(program, delegate: nil, cache: reader)
            XCTAssertTrue(loaded.build { false })
            let difference = try XCTUnwrap(loaded.children.first)
            XCTAssertEqual(difference.mesh?.polygons.count, expectedMesh.polygons.count)
            XCTAssertFalse(difference.children.isEmpty)
            XCTAssertTrue(difference.children.allSatisfy { $0.mesh == nil })
        }
    }

    func testGeometryCachePersistsGeneratedMeshesBetweenInstances() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("""
        detail 64
        difference {
            sphere
            cube { size 0.8 }
        }
        """)
        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(program, delegate: nil, cache: cache)
        _ = scene.build { false }
        cache.flushPendingDiskWrites()
        let mesh = try XCTUnwrap(scene.children.first?.mesh)
        XCTAssertGreaterThan(cache.count, 0)

        let restoredCache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let restoredScene = try evaluate(program, delegate: nil, cache: restoredCache)
        _ = restoredScene.build { false }
        let restoredMesh = try XCTUnwrap(restoredScene.children.first?.mesh)
        XCTAssertEqual(restoredMesh.polygons.count, mesh.polygons.count)
        XCTAssertGreaterThan(restoredCache.count, 0)
    }

    func testGeometryCacheFilenamesAreVersionIndependent() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(parse("""
        detail 64
        sphere
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        cache.flushPendingDiskWrites()

        let cacheFileData = try cacheFileData(at: cacheDataFile(in: directory))
        let keyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: cacheFileData.keyData) as? [String: Any]
        )
        let versionedDirectory = directory.appendingPathComponent("\(ShapeScript.version)", isDirectory: true)
        XCTAssertNil(keyObject["version"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: versionedDirectory.path))
    }

    func testGeometryCachePayloadsAreVersioned() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(parse("""
        detail 64
        sphere
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        cache.flushPendingDiskWrites()

        let cacheFileData = try cacheFileData(at: cacheDataFile(in: directory))
        let cachedMesh = try JSONDecoder().decode(CachedMesh.self, from: cacheFileData.payloadData)
        XCTAssertEqual(cachedMesh.version, ShapeScript.version)
    }

    func testGeometryCacheRejectsStalePayloadVersion() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("cube")
        let key = try XCTUnwrap(
            evaluate(program, delegate: nil, cache: nil).children.first?.cacheKey
        )
        let staleMesh = Mesh.sphere(slices: 16)
        let stalePayload = try JSONEncoder().encode(
            StaleCachedMesh(version: "0.0.0", mesh: staleMesh)
        )
        let rawDiskCache = LRUDiskCache<GeometryCache.Key, Data>(
            capacity: DiskCache.defaultCapacity,
            directory: directory
        )
        try rawDiskCache.setValue(stalePayload, forKey: key)

        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(program, delegate: nil, cache: cache)
        _ = scene.build { false }
        let mesh = try XCTUnwrap(scene.children.first?.mesh)

        XCTAssertEqual(mesh.polygons.count, Mesh.cube().polygons.count)
        XCTAssertNotEqual(mesh.polygons.count, staleMesh.polygons.count)
    }

    func testGeometryCacheAcceptsFuturePayloadVersion() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("cube")
        let key = try XCTUnwrap(
            evaluate(program, delegate: nil, cache: nil).children.first?.cacheKey
        )
        let futureMesh = Mesh.sphere(slices: 16)
        let futurePayload = try JSONEncoder().encode(
            StaleCachedMesh(version: "999.0.0", mesh: futureMesh)
        )
        let rawDiskCache = LRUDiskCache<GeometryCache.Key, Data>(
            capacity: DiskCache.defaultCapacity,
            directory: directory
        )
        try rawDiskCache.setValue(futurePayload, forKey: key)

        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(program, delegate: nil, cache: cache)
        _ = scene.build { false }
        let mesh = try XCTUnwrap(scene.children.first?.mesh)

        XCTAssertEqual(mesh.polygons.count, futureMesh.polygons.count)
        XCTAssertNotEqual(mesh.polygons.count, Mesh.cube().polygons.count)
    }

    func testGeometryCacheCanRemoveAllPersistedMeshes() async throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("""
        detail 64
        hull {
            cube
            sphere
        }
        """)
        let cache = makeCache(
            directory: directory,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(program, delegate: nil, cache: cache)
        _ = scene.build { false }
        await cache.flushPendingDiskWrites()
        XCTAssertGreaterThan(cache.count, 0)

        let restoredDiskCache = makeDiskCache(directory: directory)
        XCTAssertGreaterThan(restoredDiskCache.currentUsage, 0)
        let restoredCache = makeCache(diskCache: restoredDiskCache)
        await restoredCache.removeAll()
        XCTAssertEqual(restoredCache.count, 0)
        XCTAssertEqual(restoredDiskCache.currentUsage, 0)
    }

    func testGeometryCacheCanReloadWithoutReadingOrDeletingDiskCache() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let program = try parse("cube")
        let key = try XCTUnwrap(
            evaluate(program, delegate: nil, cache: nil).children.first?.cacheKey
        )
        let staleMesh = Mesh.sphere(slices: 16)
        let diskCache = makeDiskCache(directory: directory)
        try diskCache.setValue(CachedMesh(staleMesh), forKey: key)

        let cache = makeCache(
            diskCache: diskCache,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let staleScene = try evaluate(program, delegate: nil, cache: cache)
        _ = staleScene.build { false }
        XCTAssertEqual(staleScene.children.first?.mesh?.polygons.count, staleMesh.polygons.count)

        XCTAssertGreaterThan(diskCache.currentUsage, 0)
        let reloadedScene = try cache.withRefresh {
            let scene = try evaluate(program, delegate: nil, cache: cache)
            _ = scene.build { false }
            return scene
        }
        let cubePolygonCount = Mesh.cube().polygons.count
        XCTAssertEqual(reloadedScene.children.first?.mesh?.polygons.count, cubePolygonCount)
        XCTAssertNotEqual(cubePolygonCount, staleMesh.polygons.count)

        cache.flushPendingDiskWrites()
        cache.removeAllFromMemory()
        XCTAssertEqual(cache.count, 0)
        XCTAssertGreaterThan(diskCache.currentUsage, 0)
        let restoredScene = try evaluate(program, delegate: nil, cache: cache)
        _ = restoredScene.build { false }
        XCTAssertEqual(restoredScene.children.first?.mesh?.polygons.count, cubePolygonCount)
    }

    func testGeometryCacheDoesNotPersistEmptyMeshes() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let diskCache = makeDiskCache(directory: directory)
        let cache = makeCache(
            diskCache: diskCache,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(parse("circle"), delegate: nil, cache: cache)
        _ = scene.build { false }
        XCTAssertEqual(diskCache.currentUsage, 0)
    }

    func testGeometryCacheCanStoreMemoryWithoutPersistingToDisk() async throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let diskCache = makeDiskCache(directory: directory)
        let cache = makeCache(
            diskCache: diskCache,
            diskWritePolicy: .init { _ in .greatestFiniteMagnitude }
        )
        let scene = try evaluate(parse("cube"), delegate: nil, cache: cache)
        _ = scene.build { false }
        XCTAssertGreaterThan(cache.count, 0)
        XCTAssertEqual(diskCache.currentUsage, 0)

        await cache.removeAll()
    }

    func testFlushPendingDiskWritesWritesPendingMeshes() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let diskCache = makeDiskCache(directory: directory)
        let cache = makeCache(
            diskCache: diskCache,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let scene = try evaluate(parse("cube"), delegate: nil, cache: cache)
        _ = scene.build { false }

        cache.flushPendingDiskWrites()
        XCTAssertGreaterThan(diskCache.currentUsage, 0)
    }

    func testGeometryCacheAutomaticallyFlushesPendingDiskWrites() async throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let diskCache = makeDiskCache(directory: directory)
        let cache = makeCache(
            diskCache: diskCache,
            diskWritePolicy: alwaysStoreDiskPolicy
        )
        let geometry = Geometry(
            type: .cube,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
        geometry.cache = cache
        XCTAssertEqual(geometry.build { false }, true)

        for _ in 0 ..< 100 where diskCache.currentUsage == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(diskCache.currentUsage, 0)
    }

    func testGeometryCacheDiskWritePolicyReceivesBuiltMeshPolygonCount() throws {
        let directory = makeTemporaryCacheDirectory()
        defer { removeTemporaryCacheDirectory(directory) }

        let policyRecorder = DiskWritePolicyRecorder()
        let cache = makeCache(
            directory: directory,
            diskWritePolicy: .init {
                policyRecorder.polygonCount = $0
                return .greatestFiniteMagnitude
            }
        )
        let scene = try evaluate(parse("cube"), delegate: nil, cache: cache)
        _ = scene.build { false }
        XCTAssertEqual(policyRecorder.polygonCount, Mesh.cube().polygons.count)
    }

    // MARK: Material caching

    func testHullCacheKeyIncludesChildMaterialColors() throws {
        let cache = makeCache()

        func hullMesh(sphereColor: String) throws -> Mesh {
            let scene = try evaluate(parse("""
            detail 8
            hull {
                cube {
                    position -1.5
                    color red
                }
                sphere {
                    color \(sphereColor)
                }
            }
            """), delegate: nil, cache: cache)
            _ = scene.build { false }
            return try XCTUnwrap(scene.children.first?.mesh)
        }

        let greenHull = try hullMesh(sphereColor: "green")
        let blueHull = try hullMesh(sphereColor: "blue")
        let greenColors = Set(greenHull.polygons.flatMap { $0.vertices.map(\.color) })
        let blueColors = Set(blueHull.polygons.flatMap { $0.vertices.map(\.color) })

        XCTAssertTrue(greenColors.contains(.green))
        XCTAssertFalse(greenColors.contains(.blue))
        XCTAssertTrue(blueColors.contains(.blue))
        XCTAssertFalse(blueColors.contains(.green))
        XCTAssertNotEqual(greenHull, blueHull)
    }

    func testHullOfRawPathsInheritsMaterial() throws {
        let scene = try evaluate(parse("""
        define profile path {
            point -0.5 -0.5
            point 0.5 -0.5
            point 0.5 0.5
            point -0.5 0.5
            point -0.5 -0.5
        }
        define body {
            hull {
                profile { position 0 0 -0.5 }
                profile { position 0 0 0.5 }
            }
        }
        body {
            color blue
            metallicity 0.7
            roughness 0.2
        }
        """), delegate: nil, cache: nil)
        XCTAssertTrue(scene.build { false })
        let hull = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(hull.material.color, .blue)
        XCTAssertEqual(hull.cachedMesh?.materials, [nil])
        XCTAssertFalse(try XCTUnwrap(hull.cachedMesh).hasVertexColors)
    }

    func testHullOfPathsPreservesPointColors() throws {
        let scene = try evaluate(parse("""
        define profile path {
            color red
            point -0.5 -0.5
            point 0.5 -0.5
            color blue
            point 0.5 0.5
            point -0.5 0.5
            color red
            point -0.5 -0.5
        }
        hull {
            profile { position 0 0 -0.5 }
            profile { position 0 0 0.5 }
        }
        """), delegate: nil, cache: nil)
        XCTAssertTrue(scene.build { false })
        let mesh = try XCTUnwrap(scene.children.first?.cachedMesh)
        let colors = Set(mesh.polygons.flatMap { $0.vertices.map(\.color) })
        XCTAssertTrue(colors.contains(.red))
        XCTAssertTrue(colors.contains(.blue))
        XCTAssertFalse(colors.contains(.white))
    }

    func testHullColorCaching() throws {
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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
        let cache = makeCache()
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

    func testUnionCachingUsesMaterialIndexes() throws {
        let cache = makeCache()
        let scene = try evaluate(parse("""
        define thing(a b) {
            union {
                cube {
                    color a
                    position -2
                }
                sphere {
                    color b
                    position 2
                }
            }
        }
        thing red blue
        thing green yellow
        """), delegate: nil, cache: cache)
        _ = scene.build { false }
        // Cache should have only 3 entries: cube, sphere and union
        XCTAssertEqual(cache.count, 3)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        XCTAssertEqual(scene.children.first?.material, Material(color: .red))
        XCTAssertEqual(scene.children.last?.material, Material(color: .green))
        XCTAssertEqual(Set(meshes[0].materials.compactMap { $0 as? Material }), [
            Material(color: .blue),
        ])
        XCTAssertEqual(Set(meshes[1].materials.compactMap { $0 as? Material }), [
            Material(color: .yellow),
        ])
    }

    func testMinkowskiColorCaching() throws {
        let cache = makeCache()
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
        // Path primitives have no mesh to cache: only sphere and minkowski are cached.
        XCTAssertEqual(cache.count, 2)
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
        let cache = makeCache()
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
        // Path primitives have no mesh to cache: sphere, minkowski1 and minkowski2.
        XCTAssertEqual(cache.count, 3)
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

private final class DiskWritePolicyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _polygonCount: Int?

    var polygonCount: Int? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _polygonCount
        }
        set {
            lock.lock()
            _polygonCount = newValue
            lock.unlock()
        }
    }
}

private func cacheDataFile(in directory: URL) throws -> URL {
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    guard let url = urls.first(where: { $0.lastPathComponent.count == 32 }) else {
        XCTFail("Expected cache data file")
        throw CocoaError(.fileNoSuchFile)
    }
    return url
}

private func cacheFileData(at url: URL) throws -> (keyData: Data, payloadData: Data) {
    let data = try Data(contentsOf: url)
    let compressedDataHeader = Data([0x53, 0x53, 0x44, 0x43, 0x5A, 0x31])
    let cacheFileHeader = Data([0x53, 0x53, 0x44, 0x43, 0x46, 0x31])
    let uncompressedData: Data
    if data.starts(with: compressedDataHeader) {
        #if canImport(Darwin)
        let compressedData = data.dropFirst(compressedDataHeader.count)
        uncompressedData = try (Data(compressedData) as NSData)
            .decompressed(using: .zlib) as Data
        #else
        throw CocoaError(.fileReadCorruptFile)
        #endif
    } else {
        uncompressedData = data
    }
    guard uncompressedData.starts(with: cacheFileHeader) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let cacheFileData = Data(uncompressedData.dropFirst(cacheFileHeader.count))
    guard cacheFileData.count >= 4 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let keyLength = cacheFileData.prefix(4).reduce(UInt32.zero) {
        ($0 << 8) | UInt32($1)
    }
    guard cacheFileData.count - 4 >= Int(keyLength) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let payloadOffset = 4 + Int(keyLength)
    guard cacheFileData.count - payloadOffset >= 8 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let payloadLength = cacheFileData[payloadOffset ..< payloadOffset + 8]
        .reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    guard payloadLength <= UInt64(Int.max),
          cacheFileData.count - payloadOffset - 8 == Int(payloadLength)
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return (
        keyData: Data(cacheFileData.dropFirst(4).prefix(Int(keyLength))),
        payloadData: Data(cacheFileData.suffix(Int(payloadLength)))
    )
}

private struct StaleCachedMesh: Encodable {
    var version: String
    var mesh: Mesh
}
