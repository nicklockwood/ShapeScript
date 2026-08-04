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
            color
        case let .texture(texture):
            texture.averageColor ?? .clear
        }
    }
}

public extension Color {
    func brightness(over background: Color) -> Double {
        brightness * alpha + background.brightness * (1 - alpha)
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
        // TODO: memoize this value
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
import ImageIO

public extension Texture {
    var averageOpacity: Double? {
        opacityInfo?.averageOpacity
    }
}

extension Texture {
    var opacityMaskData: Data? {
        opacityInfo?.luminanceAlphaMaskData
    }

    private var opacityInfo: TextureOpacityInfo? {
        let source: CGImageSource? = if let url {
            CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let image = source.flatMap({
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }) else {
            return nil
        }
        return image.opacityInfo
    }
}

private struct TextureOpacityInfo {
    var averageOpacity: Double
    var luminanceAlphaMaskData: Data?
}

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
            red: Double(components[0]) / 255,
            green: Double(components[1]) / 255,
            blue: Double(components[2]) / 255,
            alpha: Double(components[3]) / 255
        )
    }

    fileprivate var opacityInfo: TextureOpacityInfo? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var components = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(self, in: rect)

        var alphaTotal = 0
        var luminanceTotal = 0
        var hasTransparentAlpha = false
        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Int(components[index])
            let green = Int(components[index + 1])
            let blue = Int(components[index + 2])
            let alpha = Int(components[index + 3])
            let luminance = (red * 54 + green * 183 + blue * 19) / 256
            alphaTotal += alpha
            luminanceTotal += luminance
            hasTransparentAlpha = hasTransparentAlpha || alpha < 255
        }

        let pixelCount = max(width * height, 1)
        let averageOpacity: Double
        if hasTransparentAlpha {
            averageOpacity = Double(alphaTotal) / Double(pixelCount * 255)
            return TextureOpacityInfo(
                averageOpacity: averageOpacity,
                luminanceAlphaMaskData: nil
            )
        }

        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Int(components[index])
            let green = Int(components[index + 1])
            let blue = Int(components[index + 2])
            let luminance = UInt8((red * 54 + green * 183 + blue * 19) / 256)
            components[index] = luminance
            components[index + 1] = luminance
            components[index + 2] = luminance
            components[index + 3] = luminance
        }

        guard let context = CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        averageOpacity = Double(luminanceTotal) / Double(pixelCount * 255)
        return TextureOpacityInfo(
            averageOpacity: averageOpacity,
            luminanceAlphaMaskData: data as Data
        )
    }
}

#else

public extension Texture {
    var averageOpacity: Double? {
        averageColor?.alpha
    }
}

extension Texture {
    var opacityMaskData: Data? {
        nil
    }
}

#endif
