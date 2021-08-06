//
//  GeometryCache.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 06/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(LRUCache)
import LRUCache
#endif

public final class GeometryCache {
    private let cache: LRUCache<Key, Mesh>

    public init(memoryLimit: Int = 1_000_000_000) {
        cache = LRUCache(totalCostLimit: memoryLimit)
    }
}

extension GeometryCache {
    struct Key: Hashable {
        let type: GeometryType
        let material: Material?
        let transform: Transform
        let children: [Key]
    }

    subscript(geometry: Geometry) -> Mesh? {
        get { cache.value(forKey: geometry.cacheKey) }
        set {
            cache.setValue(
                newValue,
                forKey: geometry.cacheKey,
                cost: newValue?.memoryUsage ?? 0
            )
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
