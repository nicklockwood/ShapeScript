//
//  Document+ModelInfo.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ShapeScript

extension Geometry {
    var modelInfo: String {
        let polygons = String(polygonCount)
        let triangles = String(triangleCount)
        let dimensions = exactBounds(with: worldTransform).size.logDescription
        let watertight = String(isWatertight)

        return [
            "Objects: \(objectCount)",
            triangles == polygons ? nil : "Polygons: \(polygons)",
            hasMesh ? "Triangles: \(triangles)" : nil,
            bounds.isEmpty ? nil : "Dimensions: \(dimensions)",
            hasMesh ? "Watertight: \(watertight)" : nil,
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
