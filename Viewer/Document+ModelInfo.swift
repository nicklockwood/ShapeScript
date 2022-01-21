//
//  Document+ModelInfo.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

extension Document {
    var importedFileCount: Int {
        linkedResources.filter { !isImageFile($0) }.count
    }

    var textureCount: Int {
        linkedResources.filter { isImageFile($0) }.count
    }

    var modelInfo: String {
        // Geometry info
        let geometry = selectedGeometry ?? self.geometry
        let polygonCount: String
        let triangleCount: String
        let dimensions: String
        if loadingProgress?.didSucceed ?? true {
            polygonCount = String(geometry.polygonCount)
            triangleCount = String(geometry.triangleCount)
            dimensions = geometry.exactBounds.size.logDescription
        } else {
            polygonCount = "calculating…"
            triangleCount = "calculating…"
            dimensions = "calculating…"
        }

        if let selectedGeometry = selectedGeometry {
            var locationString = ""
            if let location = selectedGeometry.sourceLocation {
                locationString = "\nDefined on line \(location.line)"
                if let url = location.file {
                    locationString += " in '\(url.lastPathComponent)'"
                }
            }
            let nameString = selectedGeometry.name.flatMap {
                $0.isEmpty ? nil : "Name: \($0)"
            }
            return [
                nameString,
                "Type: \(selectedGeometry.nestedLogDescription)",
                "Children: \(selectedGeometry.children.count)",
                "Polygons: \(polygonCount)",
                "Triangles: \(triangleCount)",
                "Dimensions: \(dimensions)",
//                "Size: \(selectedGeometry.transform.scale.logDescription)",
//                "Position: \(selectedGeometry.transform.offset.logDescription)",
//                "Orientation: \(selectedGeometry.transform.rotation.logDescription)",
                locationString,
            ].compactMap { $0 }.joined(separator: "\n")
        }
        return """
        Objects: \(geometry.objectCount)
        Polygons: \(polygonCount)
        Triangles: \(triangleCount)
        Dimensions: \(dimensions)

        Imports: \(importedFileCount)
        Textures: \(textureCount)
        """
    }
}
