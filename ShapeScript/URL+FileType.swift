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
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *),
           let contentType = try? resourceValues(
               forKeys: [.contentTypeKey]
           ).contentType ?? UTType(
               filenameExtension: pathExtension
           )
        {
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
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *),
           let contentType = try? resourceValues(
               forKeys: [.contentTypeKey]
           ).contentType ?? UTType(
               filenameExtension: pathExtension
           )
        {
            return contentType.conforms(to: .font)
        }
        #endif
        return ["otf", "ttf", "ttc"].contains(pathExtension.lowercased())
    }
}
