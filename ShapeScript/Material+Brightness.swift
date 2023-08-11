//
//  Material+Brightness.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 17/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

public extension MaterialProperty {
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
            return texture.averageColor ?? .clear
        }
    }
}

public extension Color {
    var brightness: Double {
        (r + g + b) / 3
    }

    func brightness(over background: Color) -> Double {
        brightness * a + background.brightness * (1 - a)
    }
}

#if canImport(UIKit)

import UIKit

public extension Texture {
    var averageColor: Color? {
        let image = UIImage(self)
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        defer { UIGraphicsEndImageContext() }
        image?.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage?.averageColor
    }
}

#elseif canImport(AppKit)

import AppKit

public extension Texture {
    var averageColor: Color? {
        let image = NSImage(self)
        var rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        return image?.cgImage(
            forProposedRect: &rect,
            context: nil,
            hints: nil
        )?.averageColor
    }
}

#else

public extension Texture {
    var averageColor: Color? {
        Color(0.5, 0.5, 0.5)
    }
}

#endif

#if canImport(CoreGraphics)

import CoreGraphics

extension CGImage {
    var averageColor: Color? {
        let alphaInfo = CGImageAlphaInfo.premultipliedLast
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel

        var components = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &components,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        context.draw(self, in: rect)
        return Color(
            Double(components[0]) / 255,
            Double(components[1]) / 255,
            Double(components[2]) / 255,
            Double(components[3]) / 255
        )
    }
}

#endif
