//
//  URL+FileType.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 15/01/2026.
//

import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public extension URL {
    var isImageFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        if let contentType {
            return contentType.conforms(to: .image)
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
        if let contentType {
            return contentType.conforms(to: .font)
        }
        #endif
        return ["otf", "ttf", "ttc"].contains(pathExtension.lowercased())
    }

    var isShapeFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        if let contentType {
            return contentType.conforms(to: .shape)
        }
        #endif
        return pathExtension.lowercased() == "shape"
    }

    var isCSGFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        if let contentType {
            return contentType.conforms(to: .csg)
        }
        #endif
        return pathExtension.lowercased() == "csg"
    }

    /// Whether the file format supports editing as source text in the editor
    var isEditableFile: Bool {
        isShapeFile || isCSGFile || ["svg", "json"].contains(pathExtension.lowercased())
    }
}

private extension URL {
    #if canImport(UniformTypeIdentifiers)
    var contentType: UTType? {
        try? resourceValues(
            forKeys: [.contentTypeKey]
        ).contentType ?? UTType(
            filenameExtension: pathExtension
        )
    }
    #endif
}
