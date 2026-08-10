//
//  Texture.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 04/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

public struct Texture: Hashable, Sendable {
    private let info: Info

    public let name: String?
    public var intensity: Double
    public var url: URL? { info.url }
    public var data: Data { info.data }
}

private extension Texture {
    final class Info: Hashable, @unchecked Sendable {
        let url: URL?
        let data: Data

        #if canImport(CoreGraphics) && canImport(ImageIO)
        fileprivate typealias OpacityValues = (
            averageOpacity: Double,
            averageLuminance: Double,
            luminanceAlphaMaskData: Data?
        )

        private let colorLock = NSLock()
        private var hasLoadedAverageColor = false
        private var averageColorIfSet: Color?
        private let opacityLock = NSLock()
        private var hasLoadedOpacityValues = false
        private var opacityValuesIfSet: OpacityValues?
        #endif

        init(url: URL?, data: Data) {
            self.url = url
            self.data = data
        }

        static func == (_: Info, _: Info) -> Bool {
            true
        }

        func hash(into _: inout Hasher) {}
    }

    init(
        name: String?,
        url: URL?,
        data: Data,
        intensity: Double
    ) {
        self.name = name
        self.info = Info(url: url, data: data)
        self.intensity = intensity
    }
}

public extension Texture {
    static func file(name: String, url: URL?, intensity: Double = 1) throws -> Self {
        let url = url ?? URL(fileURLWithPath: name)
        try url.validateFileSize(limit: FileSizeLimit.image)
        let data = try Data(contentsOf: url)
        return .init(name: name, url: url, data: data, intensity: intensity)
    }

    static func data(_ data: Data, intensity: Double = 1) -> Texture {
        .init(name: nil, url: nil, data: data, intensity: intensity)
    }

    func withIntensity(_ intensity: Double) -> Self {
        .init(info: info, name: name, intensity: intensity)
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO)

extension Texture {
    static let checkerboard: Texture = {
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(
            // TODO: use UTType.png once we drop macOS 10.15
            data, "public.png" as CFString, 1, nil
        ) {
            CGImageDestinationAddImage(destination, .checkerboard(), nil)
            CGImageDestinationFinalize(destination)
        }
        return .data(data as Data)
    }()

    var averageColor: Color? {
        info.averageColor
    }

    var averageOpacity: Double {
        info.averageOpacity
    }

    var averageLuminance: Double {
        info.averageLuminance
    }

    var opacityMaskData: Data? {
        info.luminanceAlphaMaskData
    }
}

extension Texture.Info {
    var averageColor: Color? {
        colorLock.lock()
        defer { colorLock.unlock() }
        if !hasLoadedAverageColor {
            averageColorIfSet = cgImage?.averageColor
            hasLoadedAverageColor = true
        }
        return averageColorIfSet
    }

    var averageOpacity: Double {
        opacityValues.averageOpacity
    }

    var averageLuminance: Double {
        opacityValues.averageLuminance
    }

    var luminanceAlphaMaskData: Data? {
        opacityValues.luminanceAlphaMaskData
    }

    private var opacityValues: OpacityValues {
        opacityLock.lock()
        defer { opacityLock.unlock() }
        if !hasLoadedOpacityValues {
            opacityValuesIfSet = cgImage?.opacityValues ?? (
                averageOpacity: 1,
                averageLuminance: 1,
                luminanceAlphaMaskData: nil
            )
            hasLoadedOpacityValues = true
        }
        return opacityValuesIfSet ?? (
            averageOpacity: 1,
            averageLuminance: 1,
            luminanceAlphaMaskData: nil
        )
    }

    private var cgImage: CGImage? {
        let source: CGImageSource? = if let url {
            CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            CGImageSourceCreateWithData(data as CFData, nil)
        }
        return source.flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }
    }
}

private extension CGImage {
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

    var opacityValues: Texture.Info.OpacityValues {
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
            return (
                averageOpacity: 1,
                averageLuminance: 1,
                luminanceAlphaMaskData: nil
            )
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(self, in: rect)

        var alphaTotal = 0
        var luminanceTotal = 0
        var hasTransparentAlpha = false
        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Double(components[index]) / 255
            let green = Double(components[index + 1]) / 255
            let blue = Double(components[index + 2]) / 255
            let alpha = Int(components[index + 3])
            let color = Color(red: red, green: green, blue: blue)
            let luminance = Int(color.luminance * 255)
            alphaTotal += alpha
            luminanceTotal += luminance
            hasTransparentAlpha = hasTransparentAlpha || alpha < 255
        }

        let pixelCount = max(width * height, 1)
        let averageOpacity: Double
        let averageLuminance = Double(luminanceTotal) / Double(pixelCount * 255)
        if hasTransparentAlpha {
            averageOpacity = Double(alphaTotal) / Double(pixelCount * 255)
            return (
                averageOpacity: averageOpacity,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Double(components[index]) / 255
            let green = Double(components[index + 1]) / 255
            let blue = Double(components[index + 2]) / 255
            let color = Color(red: red, green: green, blue: blue)
            let luminance = UInt8(color.luminance * 255)
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
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else {
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        return (
            averageOpacity: 1,
            averageLuminance: averageLuminance,
            luminanceAlphaMaskData: data as Data
        )
    }
}

#else

extension Texture {
    static let checkerboard: Texture = .init(
        name: nil,
        url: nil,
        data: .init(),
        intensity: 0
    )

    var averageColor: Color? {
        Color(0.5, 0.5, 0.5)
    }

    var averageOpacity: Double {
        averageColor?.alpha ?? 1
    }

    var averageLuminance: Double {
        averageColor?.luminance ?? 1
    }

    var opacityMaskData: Data? {
        nil
    }
}

#endif
