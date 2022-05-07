//
//  Document+ModelInfo.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

extension URL {
    var isImageFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            let contentType = try? resourceValues(
                forKeys: [.contentTypeKey]
            ).contentType ?? UTType(
                filenameExtension: pathExtension
            )
            return contentType?.conforms(to: .image) ?? false
        }
        #endif
        return [
            "webp",
            "png", "gif",
            "jpg", "jpeg", "jpe", "jif", "jfif", "jfi",
            "tiff", "tif",
            "psd",
            "raw", "arw", "cr2", "nrw", "k25",
            "bmp", "dib",
            "heif", "heic",
            "ind", "indd", "indt",
            "jp2", "j2k", "jpf", "jpx", "jpm", "mj2",
        ].contains(pathExtension.lowercased())
    }
}

extension Document {
    var importedFileCount: Int {
        linkedResources.filter { !$0.isImageFile }.count
    }

    var textureCount: Int {
        linkedResources.filter { $0.isImageFile }.count
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
            let childCount = selectedGeometry.childCount
            return [
                nameString,
                "Type: \(selectedGeometry.nestedLogDescription)",
                childCount == 0 ? nil : "Children: \(childCount)",
                "Polygons: \(polygonCount)",
                "Triangles: \(triangleCount)",
                "Dimensions: \(dimensions)",
                "Watertight: \(selectedGeometry.isWatertight)",
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
