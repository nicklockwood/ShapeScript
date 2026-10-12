//
//  ExportOptions.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 11/08/2026.
//

import ShapeScript

struct ExportOptions {
    var convertToZUp: Bool
    var camera: String?
    var width, height: Int?
    var antialiased: Bool = true
}

extension ExportOptions {
    /// Camera width and/or height if specified. Used as defaults if export width/height not specified.
    func cameraSize(for camera: Camera?) -> (width: Int?, height: Int?) {
        let settings = camera?.settings
        return (
            settings?.width.map { max(1, $0) },
            settings?.height.map { max(1, $0) }
        )
    }

    /// Export width/height. These override camera and window size if set.
    func outputSize(for camera: Camera?) -> (width: Int?, height: Int?) {
        let cameraSize = cameraSize(for: camera)
        switch (width, height) {
        case let (width?, height?):
            return (width, height)
        case let (width?, nil):
            return (width, scaledHeight(forWidth: width, originalSize: cameraSize))
        case let (nil, height?):
            return (scaledWidth(forHeight: height, originalSize: cameraSize), height)
        case (nil, nil):
            return cameraSize
        }
    }

    func outputSize(
        fallbackSize: (width: Int, height: Int),
        camera: Camera?
    ) -> (width: Int, height: Int) {
        let cameraSize = cameraSize(for: camera)
        let originalSize = (
            width: cameraSize.width ?? fallbackSize.width,
            height: cameraSize.height ?? cameraSize.width ?? fallbackSize.height
        )
        switch (width, height) {
        case let (width?, height?):
            return (width, height)
        case let (width?, nil):
            let height = scaledHeight(forWidth: width, originalSize: originalSize) ?? width
            return (width, height)
        case let (nil, height?):
            let width = scaledWidth(forHeight: height, originalSize: originalSize) ?? height
            return (width, height)
        case (nil, nil):
            return originalSize
        }
    }
}

private func scaledWidth(
    forHeight height: Int,
    originalSize: (width: Int?, height: Int?)
) -> Int? {
    guard let width = originalSize.width, let originalHeight = originalSize.height else {
        return nil
    }
    return max(1, Int((Double(height) * Double(width) / Double(originalHeight)).rounded()))
}

private func scaledHeight(
    forWidth width: Int,
    originalSize: (width: Int?, height: Int?)
) -> Int? {
    guard let originalWidth = originalSize.width, let height = originalSize.height else {
        return nil
    }
    return max(1, Int((Double(width) * Double(height) / Double(originalWidth)).rounded()))
}
