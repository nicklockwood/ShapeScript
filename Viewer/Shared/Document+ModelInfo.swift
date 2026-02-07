//
//  Document+ModelInfo.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

#if canImport(UIKit)
import UIKit
#endif

extension Document {
    var importedFileCount: Int {
        linkedResources.filter { !$0.isImageFile && !$0.isFontFile }.count
    }

    var textureCount: Int {
        linkedResources.filter(\.isImageFile).count
    }

    var fontCount: Int {
        linkedResources.filter(\.isFontFile).count
    }

    var modelInfo: String {
        // Geometry info
        let geometry = selectedGeometry ?? geometry
        let polygons: String
        let triangles: String
        let dimensions: String
        let volume: String
        let watertight: String
        if loadingProgress?.inProgress ?? true {
            polygons = "calculating…"
            triangles = "calculating…"
            dimensions = "calculating…"
            volume = "calculating…"
            watertight = "calculating…"
        } else {
            polygons = String(geometry.polygons { false }.count)
            triangles = String(geometry.triangles { false }.count)
            dimensions = geometry.exactBounds(with: geometry.worldTransform).size.logDescription
            volume = geometry.volume { false }.logDescription
            watertight = geometry.isWatertight { false }.logDescription
        }

        let hasTriangles = triangles != "0"
        if let selectedGeometry {
            var locationString = ""
            if let location = selectedGeometry.sourceLocation {
                locationString = "\nDefined on line \(location.line)"
                if let url = location.file, url != fileURL {
                    locationString += " in '\(url.lastPathComponent)'"
                }
            }
            let nameString = selectedGeometry.name.flatMap {
                $0.isEmpty ? nil : "Name: \($0)"
            }
            let childCount = selectedGeometry.childCount
            return [
                nameString,
                "Type: \(selectedGeometry.nestedLogDescription)",
                childCount == 0 ? nil : "Children: \(childCount)",
                triangles == polygons ? nil : "Polygons: \(polygons)",
                hasTriangles ? "Triangles: \(triangles)" : nil,
                geometry.overestimatedBounds.isEmpty ? nil : "Dimensions: \(dimensions)",
                hasTriangles ? "Volume: \(volume)" : nil,
                hasTriangles ? "Watertight: \(watertight)" : nil,
//                "Size: \(selectedGeometry.transform.scale.logDescription)",
//                "Position: \(selectedGeometry.transform.offset.logDescription)",
//                "Orientation: \(selectedGeometry.transform.rotation.logDescription)",
                locationString,
            ].compactMap { $0 }.joined(separator: "\n")
        }

        let objectCount = geometry.objectCount
        return [
            "Objects: \(objectCount)",
            triangles == polygons ? nil : "Polygons: \(polygons)",
            hasTriangles ? "Triangles: \(triangles)" : nil,
            geometry.overestimatedBounds.isEmpty ? nil : "Dimensions: \(dimensions)",
            hasTriangles ? "Volume: \(volume)" : nil,
            hasTriangles ? "Watertight: \(watertight)" : nil,
            "",
            importedFileCount == 0 ? nil : "Imports: \(importedFileCount)",
            textureCount == 0 ? nil : "Textures: \(textureCount)",
            fontCount == 0 ? nil : "Fonts: \(fontCount)",
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
