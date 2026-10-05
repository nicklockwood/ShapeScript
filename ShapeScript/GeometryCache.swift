//
//  GeometryCache.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import LRUCache

public extension Notification.Name {
    static let geometryCacheDiskUsageDidChange: Self = .init(
        rawValue: "geometryCacheDiskUsageDidChange"
    )
}

public final class GeometryCache: @unchecked Sendable {
    private let memoryCache: LRUCache<Key, CachedMesh>
    private let diskCache: DiskCache?
    private let associatedDataCache: LRUCache<Key, [Material: Any]>
    private let diskWritePolicy: DiskWritePolicy
    private let pendingDiskWriteLock = NSLock()
    private var pendingDiskWrites: [Key: Mesh?] = [:]
    private var pendingDiskFlushScheduled = false

    init(
        memoryLimit: Int = GeometryCache.defaultMemoryLimit,
        diskCache: DiskCache?,
        diskWritePolicy: DiskWritePolicy
    ) {
        self.memoryCache = LRUCache(totalCostLimit: memoryLimit)
        self.diskCache = diskCache
        self.associatedDataCache = LRUCache(totalCostLimit: memoryLimit)
        self.diskWritePolicy = diskWritePolicy
    }

    deinit {
        flushPendingDiskWrites()
    }
}

public extension GeometryCache {
    /// The number of entries currently cached in memory.
    var count: Int {
        memoryCache.count
    }

    /// Initialize the cache with a given memory limit and the shared disk cache.
    /// - Parameter memoryLimit: The maximum amount of data to cache in memory, in bytes.
    convenience init(
        memoryLimit: Int = GeometryCache.defaultMemoryLimit,
        diskCache: DiskCache? = .shared
    ) {
        self.init(
            memoryLimit: memoryLimit,
            diskCache: diskCache,
            diskWritePolicy: .default
        )
    }

    /// Removes all cached geometry from memory and disk.
    func removeAll() async {
        memoryCache.removeAll()
        associatedDataCache.removeAll()
        _ = removePendingDiskWrites()
        await performDiskOperation {
            self.diskCache?.removeAllSynchronously()
        }
    }

    /// Synchronously writes pending meshes to disk after any already-scheduled writes finish.
    func flushPendingDiskWrites() {
        diskCache?.sync {
            applyDiskWrites(removePendingDiskWrites())
        }
    }

    /// Asynchronously writes pending meshes to disk without blocking the caller's thread.
    func flushPendingDiskWrites() async {
        await performDiskOperation {
            self.flushPendingDiskWrites()
        }
    }

    /// The default memory limit for geometry cache instances.
    static let defaultMemoryLimit: Int = 1024 * 1024 * 1024

    /// The default disk storage capacity for the shared geometry cache.
    static var defaultDiskCapacity: Int { DiskCache.defaultCapacity }
}

/// Persistent storage used by `GeometryCache`.
public final class DiskCache: @unchecked Sendable {
    private let cache: LRUDiskCache<GeometryCache.Key, CachedMesh>
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()

    init(capacity: Int = defaultCapacity, directory: URL = defaultDirectory) {
        self.queue = DispatchQueue(label: "ShapeScript.DiskCache", qos: .utility)
        self.cache = .init(
            capacity: capacity,
            directory: directory
        )
        queue.setSpecific(key: queueKey, value: ())
    }
}

public extension DiskCache {
    /// The shared disk cache used by default `GeometryCache` instances.
    static let shared: DiskCache = .init()

    /// The current size of the disk cache.
    var currentUsage: Int { cache.currentUsage }

    /// The maximum size permitted for the disk cache.
    var capacity: Int { cache.capacity }

    /// Updates the maximum size permitted for the disk cache.
    func setCapacity(_ capacity: Int) async {
        await performOnDiskQueue {
            self.cache.capacity = capacity
            self.postUsageDidChange()
        }
    }

    /// Removes all geometry values from disk.
    func removeAll() async {
        await performOnDiskQueue {
            self.removeAllSynchronously()
        }
    }
}

extension DiskCache {
    static var defaultCapacity: Int {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        250_000_000
        #else
        1_000_000_000
        #endif
    }

    static var defaultDirectory: URL {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if let url = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return url
                .appendingPathComponent("ShapeScript", isDirectory: true)
                .appendingPathComponent("GeometryCache", isDirectory: true)
        }
        #endif
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ShapeScript", isDirectory: true)
            .appendingPathComponent("GeometryCache", isDirectory: true)
    }

    func value(forKey key: GeometryCache.Key) -> CachedMesh? {
        cache.value(forKey: key)
    }

    func setValue(_ value: CachedMesh?, forKey key: GeometryCache.Key) throws {
        try cache.setValue(value, forKey: key)
    }

    func removeAllSynchronously() {
        cache.removeAll()
        postUsageDidChange()
    }

    func postUsageDidChange() {
        NotificationCenter.default.post(
            name: .geometryCacheDiskUsageDidChange,
            object: self
        )
    }

    func async(_ action: @escaping @Sendable () -> Void) {
        queue.async(execute: action)
    }

    func sync(_ action: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            action()
        } else {
            queue.sync(execute: action)
        }
    }

    private func performOnDiskQueue(_ action: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                action()
                continuation.resume()
            }
        }
    }
}

extension GeometryCache {
    struct DiskWritePolicy: Sendable {
        var estimatedLoadTime: @Sendable (Int) -> TimeInterval

        init(estimatedLoadTime: @escaping @Sendable (Int) -> TimeInterval) {
            self.estimatedLoadTime = estimatedLoadTime
        }

        static let `default`: Self = .init { polygonCount in
            TimeInterval(polygonCount) * 0.00004
        }
    }

    enum MaterialKey: Hashable, Codable {
        case value(Material)
        case index(Int)
    }

    struct Key: Hashable, Codable {
        let type: GeometryType
        let material: MaterialKey?
        let smoothing: Angle?
        let transform: Transform
        let flipped: Bool
        let children: [Key]
    }

    subscript(mesh geometry: Geometry) -> Mesh? {
        let key = geometry.cacheKey
        if let mesh = memoryCache.value(forKey: key)?.mesh {
            return mesh.replacingMaterialIndexes(using: geometry.materialsByIndex)
        }
        guard let cachedMesh = diskCache?.value(forKey: key) else {
            return nil
        }
        memoryCache.setValue(
            cachedMesh,
            forKey: key,
            cost: cachedMesh.mesh.estimatedCacheCost
        )
        return cachedMesh.mesh.replacingMaterialIndexes(using: geometry.materialsByIndex)
    }

    func buildMesh(for geometry: Geometry, _ build: (Mesh?) -> Bool) -> Bool {
        if let mesh = self[mesh: geometry] {
            return build(mesh)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let succeeded = build(nil)
        if succeeded, let mesh = geometry.mesh {
            storeBuiltMesh(
                mesh,
                for: geometry,
                elapsedTime: CFAbsoluteTimeGetCurrent() - start
            )
        }

        return succeeded
    }

    private func storeBuiltMesh(_ mesh: Mesh, for geometry: Geometry, elapsedTime: TimeInterval) {
        let cachedMeshValue = setMemoryMesh(mesh, for: geometry)
        if shouldStorePersistentMesh(cachedMeshValue, elapsedTime: elapsedTime) {
            setPendingDiskWrite(cachedMeshValue, forKey: geometry.cacheKey)
        }
    }

    private func setMemoryMesh(_ mesh: Mesh, for geometry: Geometry) -> Mesh {
        let key = geometry.cacheKey
        let cachedMeshValue = mesh.replacingMaterialsWithIndexes(using: geometry.indexesByMaterial)
        memoryCache.setValue(
            CachedMesh(cachedMeshValue),
            forKey: key,
            cost: cachedMeshValue.estimatedCacheCost
        )
        associatedDataCache.setValue([:], forKey: key)
        return cachedMeshValue
    }

    private func shouldStorePersistentMesh(_ mesh: Mesh, elapsedTime: TimeInterval) -> Bool {
        guard diskCache != nil, !mesh.polygons.isEmpty else {
            return false
        }
        return elapsedTime > diskWritePolicy.estimatedLoadTime(mesh.polygons.count)
    }

    subscript(associatedData geometry: Geometry) -> Any? {
        get {
            associatedDataCache.value(forKey: geometry.cacheKey)?[geometry.material]
        }
        set {
            let key = geometry.cacheKey
            if var value = associatedDataCache.value(forKey: key) {
                value[geometry.material] = newValue
                associatedDataCache.setValue(value, forKey: key)
            }
        }
    }

    func applyDiskWrites(_ writes: [Key: Mesh?]) {
        guard let diskCache, !writes.isEmpty else {
            return
        }
        for (key, mesh) in writes {
            try? diskCache.setValue(mesh.map(CachedMesh.init), forKey: key)
        }
        postDiskUsageDidChange()
    }
}

private extension Mesh {
    func replacingMaterialsWithIndexes(using indexesByMaterial: [Material: Int]) -> Mesh {
        guard !indexesByMaterial.isEmpty else {
            return self
        }
        return mapPolygons { polygon in
            guard let material = polygon.material as? ShapeScript.Material,
                  let index = indexesByMaterial[material]
            else {
                return polygon
            }
            return polygon.withMaterial(index)
        }
    }

    func replacingMaterialIndexes(using materialsByIndex: [Material]) -> Mesh {
        guard !materialsByIndex.isEmpty else {
            return self
        }
        return mapPolygons { polygon in
            guard let index = polygon.material as? Int,
                  materialsByIndex.indices.contains(index)
            else {
                return polygon
            }
            return polygon.withMaterial(materialsByIndex[index])
        }
    }
}

private extension GeometryCache {
    func setPendingDiskWrite(_ mesh: Mesh?, forKey key: Key) {
        guard let diskCache else {
            return
        }
        var shouldScheduleFlush = false
        pendingDiskWriteLock.lock()
        pendingDiskWrites[key] = mesh
        if !pendingDiskFlushScheduled {
            pendingDiskFlushScheduled = true
            shouldScheduleFlush = true
        }
        pendingDiskWriteLock.unlock()

        if shouldScheduleFlush {
            diskCache.async {
                self.applyScheduledDiskWrites()
            }
        }
    }

    func removePendingDiskWrites() -> [Key: Mesh?] {
        pendingDiskWriteLock.lock()
        defer { pendingDiskWriteLock.unlock() }
        let writes = pendingDiskWrites
        pendingDiskWrites.removeAll()
        pendingDiskFlushScheduled = false
        return writes
    }

    func applyScheduledDiskWrites() {
        let writes = removePendingDiskWrites()
        applyDiskWrites(writes)
    }

    func postDiskUsageDidChange() {
        diskCache?.postUsageDidChange()
    }

    func performDiskOperation(_ operation: @escaping @Sendable () -> Void) async {
        if let diskCache {
            await withCheckedContinuation { continuation in
                diskCache.async {
                    operation()
                    continuation.resume()
                }
            }
        } else {
            operation()
        }
    }
}

struct CachedMesh: Codable {
    var version: SemanticVersion = ShapeScript.version
    var mesh: Mesh

    init(_ mesh: Mesh) {
        self.mesh = mesh
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(SemanticVersion.self, forKey: .version)
        guard version == ShapeScript.version else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Cached mesh version does not match app version"
            )
        }
        self.mesh = try container.decode(Mesh.self, forKey: .mesh)
            .decodingCachedMaterials()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(mesh.encodingCachedMaterials(), forKey: .mesh)
    }

    private enum CodingKeys: CodingKey {
        case version
        case mesh
    }
}

private extension Mesh {
    var estimatedCacheCost: Int {
        max(1, polygons.count * 512)
    }

    func encodingCachedMaterials() throws -> Mesh {
        try Mesh(polygons.map { polygon in
            try polygon.withMaterial(polygon.material?.encodingCachedMaterial())
        })
    }

    func decodingCachedMaterials() -> Mesh {
        Mesh(polygons.map { polygon in
            polygon.withMaterial(polygon.material?.decodingCachedMaterial())
        })
    }
}

private extension Polygon.Material {
    func encodingCachedMaterial() throws -> Polygon.Material {
        guard let material = base as? Material else {
            return self
        }
        let data = try JSONEncoder().encode(material)
        return AnyHashable(data)
    }

    func decodingCachedMaterial() -> Polygon.Material {
        guard let data = base as? Data,
              let material = try? JSONDecoder().decode(Material.self, from: data)
        else {
            return self
        }
        return AnyHashable(material)
    }
}
