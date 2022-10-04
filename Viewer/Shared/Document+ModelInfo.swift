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

    var isFontFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            let contentType = try? resourceValues(
                forKeys: [.contentTypeKey]
            ).contentType ?? UTType(
                filenameExtension: pathExtension
            )
            return contentType?.conforms(to: .font) ?? false
        }
        #endif
        // NOTE: these values are also hard-coded in EvaluationContext
        return [".otf", ".ttf", ".ttc"].contains(pathExtension.lowercased())
    }
}

extension Document {
    var importedFileCount: Int {
        linkedResources.filter { !$0.isImageFile && !$0.isFontFile }.count
    }

    var textureCount: Int {
        linkedResources.filter { $0.isImageFile }.count
    }

    var fontCount: Int {
        linkedResources.filter { $0.isFontFile }.count
    }

    var modelInfo: String {
        // Geometry info
        let geometry = selectedGeometry ?? self.geometry
        let polygonCount: String
        let triangleCount: String
        let dimensions: String
        let watertight: String
        if loadingProgress?.didSucceed ?? true {
            polygonCount = String(geometry.polygonCount)
            triangleCount = String(geometry.triangleCount)
            dimensions = geometry.exactBounds.size.logDescription
            watertight = String(geometry.isWatertight)
        } else {
            polygonCount = "calculating…"
            triangleCount = "calculating…"
            dimensions = "calculating…"
            watertight = "calculating…"
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
                triangleCount == polygonCount ? nil : "Polygons: \(polygonCount)",
                "Triangles: \(triangleCount)",
                "Dimensions: \(dimensions)",
                "Watertight: \(watertight)",
//                "Size: \(selectedGeometry.transform.scale.logDescription)",
//                "Position: \(selectedGeometry.transform.offset.logDescription)",
//                "Orientation: \(selectedGeometry.transform.rotation.logDescription)",
                locationString,
            ].compactMap { $0 }.joined(separator: "\n")
        }

        let objectCount = geometry.objectCount
        return [
            "Objects: \(objectCount)",
            triangleCount == polygonCount ? nil : "Polygons: \(polygonCount)",
            "Triangles: \(triangleCount)",
            "Dimensions: \(dimensions)",
            objectCount != 1 ? nil : "Watertight: \(watertight)",
            "",
            "Imports: \(importedFileCount)",
            "Textures: \(textureCount)",
            fontCount == 0 ? nil : "Fonts: \(fontCount)",
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
