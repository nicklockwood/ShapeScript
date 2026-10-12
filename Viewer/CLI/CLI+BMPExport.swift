//
//  CLI+BMPExport.swift
//  CLI
//
//  Created by Nick Lockwood on 11/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

extension CLIRunner {
    func exportBMP(_ scene: Scene, geometry: Geometry, to url: URL, with options: ExportOptions) throws {
        let camera = camera(for: scene, options: options)
        let (width, height) = try camera.pixelSize
        guard width <= Int(Int32.max), height <= Int(Int32.max) else {
            throw CLIError("Image dimensions are too large for BMP export")
        }
        let rowSize = (width * 3 + 3) & ~3
        guard height <= (Int(UInt32.max) - 54) / rowSize else {
            throw CLIError("Image is too large for BMP export")
        }
        let renderedImage = try render(
            mesh: geometry.withoutHiddenOrUnfocused().withoutDebug().merged(),
            camera: camera,
            background: (camera.background ?? scene.background).color ?? .clear
        )

        let image = bitmapData(renderedImage.pixels, width: renderedImage.width, height: renderedImage.height)
        try image.write(to: url, options: .atomic)
    }
}

private func bitmapData(_ pixels: [Color], width: Int, height: Int) -> Data {
    let rowSize = (width * 3 + 3) & ~3
    let imageSize = rowSize * height
    var data = Data()
    data.reserveCapacity(54 + imageSize)
    data.append(contentsOf: [0x42, 0x4D])
    data.appendLittleEndian(UInt32(54 + imageSize))
    data.appendLittleEndian(UInt32(0))
    data.appendLittleEndian(UInt32(54))

    // Bitmap header
    data.appendLittleEndian(UInt32(40))
    data.appendLittleEndian(Int32(width))
    data.appendLittleEndian(Int32(height))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(24))
    data.appendLittleEndian(UInt32(0))
    data.appendLittleEndian(UInt32(imageSize))
    data.append(contentsOf: repeatElement(UInt8(0), count: 16))

    // Rows are stored bottom to top with padding to a multiple of four bytes
    let padding = Array(repeating: UInt8(0), count: rowSize - width * 3)
    for y in (0 ..< height).reversed() {
        for x in 0 ..< width {
            let color = pixels[y * width + x].composited(over: .white)
            data.append(contentsOf: [
                UInt8((color.blue.clamped() * 255).rounded()),
                UInt8((color.green.clamped() * 255).rounded()),
                UInt8((color.red.clamped() * 255).rounded()),
            ])
        }
        data.append(contentsOf: padding)
    }
    return data
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

private extension Scene {
    var primaryCamera: Geometry? {
        cameras.first
    }
}

private extension Geometry {
    var cameraWithTransform: (camera: Camera, transform: Transform)? {
        guard case let .camera(camera) = type else {
            return children.compactMap(\.cameraWithTransform).first
        }
        return (camera, worldTransform)
    }
}

private extension CLIRunner {
    func camera(for scene: Scene, options: ExportOptions) -> ShapeScript.Camera {
        let cameraGeometry = scene.primaryCamera?.cameraWithTransform
        let camera = cameraGeometry?.camera ?? .default
        let bounds = scene.visibleBounds
        let size = bounds.size
        let center = bounds.center

        var width = camera.width.map { max(1, Int($0.rounded())) } ?? 320
        var height = camera.height.map { max(1, Int($0.rounded())) } ?? width
        switch (options.width, options.height) {
        case let (newWidth?, newHeight?):
            width = newWidth
            height = newHeight
        case let (newWidth?, nil):
            height = max(1, Int((Double(height) * Double(newWidth) / Double(width)).rounded()))
            width = newWidth
        case let (nil, newHeight?):
            width = max(1, Int((Double(width) * Double(newHeight) / Double(height)).rounded()))
            height = newHeight
        case (nil, nil):
            break
        }
        let aspectRatio = Double(height) / Double(width)
        let fov = camera.fov ?? .degrees(60)

        let distance = max(size.x * aspectRatio, size.y) + size.z / 2
        var scale = max(size.x * aspectRatio, size.y, size.z * aspectRatio)
        scale /= 1.8

        let explicitOrientation = camera.orientation ?? cameraGeometry?.camera.orientation
        var orientation = cameraGeometry?.transform.rotation ?? explicitOrientation ?? .identity
        let direction = -Vector.unitZ.rotated(by: orientation)
        var position = center - direction * distance + Vector(0, 0.000001, 0)

        if let transform = cameraGeometry?.transform {
            if camera.hasPosition {
                position = transform.translation
            }
            if camera.hasScale {
                let v = transform.scale
                scale = max(v.x, v.y, v.z)
            }
        }

        if explicitOrientation == nil {
            orientation = Rotation(from: -.unitZ, to: center - position)
        }

        var result = camera
        result.position = position
        result.orientation = orientation
        result.scale = Vector(scale, scale, scale)
        result.fov = fov
        result.width = Double(width)
        result.height = Double(height)
        return result
    }
}
