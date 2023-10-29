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
    private let cache: LRUCache<Key, (mesh: Mesh, associatedData: [Material: Any])>

    public init(memoryLimit: Int = 1_000_000_000) {
        self.cache = LRUCache(totalCostLimit: memoryLimit)
    }
}

extension GeometryCache {
    struct Key: Hashable {
        let type: GeometryType
        let material: Material?
        let smoothing: Angle?
        let wrapMode: WrapMode?
        let transform: Transform
        let flipped: Bool
        let children: [Key]
    }

    subscript(mesh geometry: Geometry) -> Mesh? {
        get { cache.value(forKey: geometry.cacheKey)?.mesh }
        set {
            guard let newValue = newValue else {
                cache.removeValue(forKey: geometry.cacheKey)
                return
            }
            cache.setValue(
                (newValue, [:]),
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
    var memoryUsage: Int {
        let vertexSize = MemoryLayout<Vertex>.stride
        let polygonSize = 512 // Estimated
        return polygons.reduce(0) { count, polygon in
            count + polygonSize + polygon.vertices.count * vertexSize
        }
    }
}
