//
//  Geometry+ModelInfo.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import ShapeScript

extension Geometry {
    var modelInfo: String {
        let polygons = String(polygons { false }.count)
        let triangles = String(triangles { false }.count)
        let dimensions = exactBounds(with: worldTransform).size.logDescription
        let watertight = isWatertight { false }.logDescription

        return [
            "Objects: \(objectCount)",
            triangles == polygons ? nil : "Polygons: \(polygons)",
            hasMesh ? "Triangles: \(triangles)" : nil,
            bounds.isEmpty ? nil : "Dimensions: \(dimensions)",
            hasMesh ? "Watertight: \(watertight)" : nil,
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
