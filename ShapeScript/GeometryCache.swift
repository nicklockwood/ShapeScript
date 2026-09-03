//
//  GeometryCache.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import LRUCache

public final class GeometryCache: @unchecked Sendable {
    private let cache: LRUCache<Key, (mesh: Mesh, associatedData: [Material: Any])>

    /// The number of entries currently stored in the cache
    public var count: Int { cache.count }

    /// Initialize the cache with a given storage limit
    /// - Parameter memoryLimit: The maximum amount of data to cache (in bytes)
    public init(memoryLimit: Int = 1_000_000_000) {
        self.cache = LRUCache(totalCostLimit: memoryLimit)
    }
}

extension GeometryCache {
    enum MaterialKey: Hashable {
        case value(Material)
        case index(Int)
    }

    struct Key: Hashable {
        let type: GeometryType
        let material: MaterialKey?
        let smoothing: Angle?
        let transform: Transform
        let flipped: Bool
        let children: [Key]
    }

    subscript(mesh geometry: Geometry) -> Mesh? {
        get {
            cache.value(forKey: geometry.cacheKey)?.mesh.replacingMaterialIndexes(
                using: geometry.materialsByIndex
            )
        }
        set {
            guard let newValue else {
                cache.removeValue(forKey: geometry.cacheKey)
                return
            }
            cache.setValue(
                (newValue.replacingMaterialsWithIndexes(using: geometry.indexesByMaterial), [:]),
                forKey: geometry.cacheKey,
                cost: newValue.memoryUsage
            )
        }
    }

    subscript(associatedData geometry: Geometry) -> Any? {
        get {
            cache.value(forKey: geometry.cacheKey)?
                .associatedData[geometry.material]
        }
        set {
            if var value = cache.value(forKey: geometry.cacheKey) {
                value.associatedData[geometry.material] = newValue
                cache.setValue(value, forKey: geometry.cacheKey)
            }
        }
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

private extension Mesh {
    var memoryUsage: Int {
        let vertexSize = MemoryLayout<Vertex>.stride
        let polygonSize = 512 // Estimated
        return polygons.reduce(0) { count, polygon in
            count + polygonSize + polygon.vertices.count * vertexSize
        }
    }
}
