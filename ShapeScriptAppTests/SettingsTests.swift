//
//  SettingsTests.swift
//  ShapeScriptAppTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Euclid
import XCTest

@MainActor
final class SettingsTests: XCTestCase {
    func testExternalCacheSizeChangesAreAppliedOnActivation() async throws {
        try await withSettings { settings, defaults, cache in
            defaults.set(100 * Settings.megabytes, forKey: "diskCacheCapacity")
            await settings.applyExternalCacheSettings()
            XCTAssertEqual(cache.capacity, 100 * Settings.megabytes)

            defaults.set(0, forKey: "diskCacheCapacity")
            await settings.applyExternalCacheSettings()
            XCTAssertEqual(cache.capacity, 0)
        }
    }

    func testClearCacheRequestIsConsumedOnlyOnce() async throws {
        try await withSettings { settings, defaults, cache in
            let context = EvaluationContext(source: "", delegate: nil) { false }
            let geometry = Geometry(type: .cube, in: context)
            let mesh = CachedMesh(Mesh.cube())
            try cache.setValue(mesh, forKey: geometry.cacheKey)
            XCTAssertGreaterThan(cache.currentUsage, 0)

            defaults.set(true, forKey: "clearDiskCache")
            await settings.applyExternalCacheSettings()
            XCTAssertFalse(defaults.bool(forKey: "clearDiskCache"))
            XCTAssertEqual(cache.currentUsage, 0)

            try cache.setValue(mesh, forKey: geometry.cacheKey)
            await settings.applyExternalCacheSettings()
            XCTAssertGreaterThan(cache.currentUsage, 0)
        }
    }

    private func withSettings(_ body: (Settings, UserDefaults, DiskCache) async throws -> Void) async throws {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(250 * Settings.megabytes, forKey: "diskCacheCapacity")
        let cache = DiskCache(capacity: 250 * Settings.megabytes, directory: directory)
        let settings = Settings(defaults: defaults, diskCache: cache)
        await settings.applyExternalCacheSettings()
        try await body(settings, defaults, cache)
    }
}
