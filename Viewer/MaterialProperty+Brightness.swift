//
//  MaterialProperty+Brightness.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 11/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Cocoa
import ShapeScript

extension MaterialProperty {
    var brightness: Double {
        averageColor.brightness
    }

    func brightness(over background: Color) -> Double {
        averageColor.brightness(over: background)
    }

    var averageColor: Color {
        switch self {
        case let .color(color):
            return color
        case let .texture(texture):
            return texture.getAverageColor() ?? .clear
        }
    }
}

extension Color {
    var brightness: Double {
        (r + g + b) / 3
    }

    func brightness(over background: Color) -> Double {
        brightness * a + background.brightness * (1 - a)
    }
}

private extension Texture {
    func getAverageColor() -> Color? {
        let image: NSImage?
        switch self {
        case let .data(data):
            image = NSImage(data: data)
        case let .file(name: _, url: url):
            image = NSImage(contentsOf: url)
        }
        var rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        guard let cgImage = image?.cgImage(
            forProposedRect: &rect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let width = 1, height = 1
        let alphaInfo = CGImageAlphaInfo.premultipliedLast
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var components = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: NSRectToCGRect(rect))
        return Color(
            Double(components[0]) / 255,
            Double(components[1]) / 255,
            Double(components[2]) / 255,
            Double(components[3]) / 255
        )
    }
}
