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
        let camera = try scene.exportCamera(with: options, fallbackSize: (width: 320, height: 320), camera: nil)
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
