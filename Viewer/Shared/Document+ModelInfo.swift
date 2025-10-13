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
        if loadingProgress?.didSucceed ?? true {
            polygons = String(geometry.polygons { false }.count)
            triangles = String(geometry.triangles { false }.count)
            dimensions = geometry.exactBounds(with: geometry.worldTransform).size.logDescription
            volume = geometry.volume { false }.logDescription
            watertight = geometry.isWatertight { false }.logDescription
        } else {
            polygons = "calculating…"
            triangles = "calculating…"
            dimensions = "calculating…"
            volume = "calculating…"
            watertight = "calculating…"
        }

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
            let isMesh = selectedGeometry.hasMesh
            let childCount = selectedGeometry.childCount
            return [
                nameString,
                "Type: \(selectedGeometry.nestedLogDescription)",
                childCount == 0 ? nil : "Children: \(childCount)",
                triangles == polygons ? nil : "Polygons: \(polygons)",
                isMesh ? "Triangles: \(triangles)" : nil,
                geometry.overestimatedBounds.isEmpty ? nil : "Dimensions: \(dimensions)",
                isMesh ? "Volume: \(volume)" : nil,
                isMesh ? "Watertight: \(watertight)" : nil,
//                "Size: \(selectedGeometry.transform.scale.logDescription)",
//                "Position: \(selectedGeometry.transform.offset.logDescription)",
//                "Orientation: \(selectedGeometry.transform.rotation.logDescription)",
                locationString,
            ].compactMap { $0 }.joined(separator: "\n")
        }

        let objectCount = geometry.objectCount
        let hasMeshes = geometry.hasMesh
        return [
            "Objects: \(objectCount)",
            triangles == polygons ? nil : "Polygons: \(polygons)",
            hasMeshes ? "Triangles: \(triangles)" : nil,
            geometry.overestimatedBounds.isEmpty ? nil : "Dimensions: \(dimensions)",
            hasMeshes ? "Volume: \(volume)" : nil,
            hasMeshes ? "Watertight: \(watertight)" : nil,
            "",
            importedFileCount == 0 ? nil : "Imports: \(importedFileCount)",
            textureCount == 0 ? nil : "Textures: \(textureCount)",
            fontCount == 0 ? nil : "Fonts: \(fontCount)",
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
